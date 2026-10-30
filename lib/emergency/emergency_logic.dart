import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Pure logic for Emergency mode. Nothing here reads or writes app settings,
/// so it can be tested without the app running.

/// The fields of an airport that Emergency mode needs, so the logic does not
/// depend on the database classes.
class EmergencyAirport {
  final String id;
  final String name;
  final LatLng coordinate;
  final double elevationFt;
  final double? variation;
  final String ctaf;
  final String unicom;
  /// Rows of the `airportrunways` table.
  final List<Map<String, dynamic>> runways;

  const EmergencyAirport({
    required this.id,
    required this.name,
    required this.coordinate,
    required this.elevationFt,
    required this.variation,
    required this.ctaf,
    required this.unicom,
    required this.runways,
  });
}

/// A runway end that can be landed on from the current position.
class RunwayCandidate {
  final EmergencyAirport airport;
  final String runwayIdent;
  /// Where the landing roll starts.
  final LatLng threshold;
  /// True heading of the landing direction, from the database.
  final double heading;
  final double lengthFt;
  /// Positive is headwind, negative is tailwind, knots.
  final double headwindKt;
  final double crosswindKt;
  final double distanceNm;
  final double bearingDeg;
  /// Landing distance the aircraft needs here, feet. Null when its landing data is unknown.
  final double? requiredFt;
  /// The airport publishes no usable runway. [threshold] is the airport and
  /// [heading] is the direction to land, into the wind.
  final bool noRunwayData;

  const RunwayCandidate({
    required this.airport,
    required this.runwayIdent,
    required this.threshold,
    required this.heading,
    required this.lengthFt,
    required this.headwindKt,
    required this.crosswindKt,
    required this.distanceNm,
    required this.bearingDeg,
    required this.requiredFt,
    this.noRunwayData = false,
  });

  /// Long enough for the aircraft. Unknown aircraft data does not count against a runway.
  bool get longEnough => requiredFt == null || lengthFt >= requiredFt!;
}

class RunwaySelection {
  /// Null when no runway is reachable.
  final RunwayCandidate? runway;
  /// A runway was chosen but it is shorter than the aircraft needs.
  final bool lessThanIdeal;

  const RunwaySelection(this.runway, this.lessThanIdeal);
}

/// Landing direction when no runway is identified.
class OffFieldDirection {
  /// True heading to land on.
  final double heading;
  final bool intoWind;
  final String label;

  const OffFieldDirection(this.heading, this.intoWind, this.label);
}

typedef WindLookup = (double?, double?) Function(EmergencyAirport airport);
typedef RequiredLanding = double? Function(double fieldElevationFt, double headwindKt);

class EmergencyLogic {
  EmergencyLogic._();

  static const double blinkThresholdKt = 5;
  static const double _earthRadiusNm = 3440.065;

  /// Ray casting on latitude/longitude. Fine at glide-ring scale.
  static bool pointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) {
      return false;
    }
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final double yi = polygon[i].latitude;
      final double xi = polygon[i].longitude;
      final double yj = polygon[j].latitude;
      final double xj = polygon[j].longitude;
      final bool crosses = (yi > point.latitude) != (yj > point.latitude) &&
          point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi;
      if (crosses) {
        inside = !inside;
      }
    }
    return inside;
  }

  static double distanceNm(LatLng a, LatLng b) {
    final double lat1 = a.latitudeInRad;
    final double lat2 = b.latitudeInRad;
    final double dLat = lat2 - lat1;
    final double dLon = b.longitudeInRad - a.longitudeInRad;
    final double h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
    return 2 * _earthRadiusNm * math.asin(math.min(1.0, math.sqrt(h)));
  }

  static double bearingDeg(LatLng a, LatLng b) {
    final double lat1 = a.latitudeInRad;
    final double lat2 = b.latitudeInRad;
    final double dLon = b.longitudeInRad - a.longitudeInRad;
    final double y = math.sin(dLon) * math.cos(lat2);
    final double x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// Indicated airspeed, knots, from GPS ground speed and the wind. The wind
  /// triangle gives true airspeed, then 2 percent per 1000 ft takes it down to
  /// indicated, the same lapse the glide ring uses. Without wind the ground
  /// speed stands in for true airspeed.
  static double indicatedAirspeedKt({
    required double groundSpeedKt,
    required double trackDeg,
    required double altitudeFt,
    double? windFromDeg,
    double? windSpeedKt,
  }) {
    double tas = groundSpeedKt;
    if (windFromDeg != null && windSpeedKt != null && windSpeedKt > 0) {
      final double angle = (trackDeg - (windFromDeg + 180)) * math.pi / 180;
      final double squared = groundSpeedKt * groundSpeedKt +
          windSpeedKt * windSpeedKt -
          2 * groundSpeedKt * windSpeedKt * math.cos(angle);
      tas = math.sqrt(math.max(0, squared));
    }
    final double lapse = 1 + 0.02 * (altitudeFt / 1000.0);
    return tas / (lapse <= 0 ? 1 : lapse);
  }

  /// True when the airspeed is off best glide by more than [blinkThresholdKt].
  static bool airspeedOff(double airspeedKt, double bestGlideKt) {
    return (airspeedKt - bestGlideKt).abs() > blinkThresholdKt;
  }

  /// Wind component along a runway, knots. Positive is headwind.
  static double headwindComponent(double runwayHeading, double? windFromDeg, double? windSpeedKt) {
    if (windFromDeg == null || windSpeedKt == null) {
      return 0;
    }
    return math.cos((windFromDeg - runwayHeading) * math.pi / 180) * windSpeedKt;
  }

  /// Wind component across a runway, knots. Positive is from the right.
  static double crosswindComponent(double runwayHeading, double? windFromDeg, double? windSpeedKt) {
    if (windFromDeg == null || windSpeedKt == null) {
      return 0;
    }
    return math.sin((windFromDeg - runwayHeading) * math.pi / 180) * windSpeedKt;
  }

  static double? _number(dynamic value) {
    if (value == null) {
      return null;
    }
    return double.tryParse(value.toString().trim());
  }

  /// Point [distanceNm] from [from] on [bearing] degrees true.
  static LatLng offsetPoint(LatLng from, double distanceNm, double bearing) {
    final double d = distanceNm / _earthRadiusNm;
    final double b = bearing * math.pi / 180;
    final double lat1 = from.latitudeInRad;
    final double lon1 = from.longitudeInRad;
    final double lat2 = math.asin(math.sin(lat1) * math.cos(d) + math.cos(lat1) * math.sin(d) * math.cos(b));
    final double lon2 = lon1 +
        math.atan2(math.sin(b) * math.sin(d) * math.cos(lat1), math.cos(d) - math.sin(lat1) * math.sin(lat2));
    return LatLng(lat2 * 180 / math.pi, ((lon2 * 180 / math.pi) + 540) % 360 - 180);
  }

  /// Helipad ends (H1, H2A) are never landing runways, even at an airport.
  static bool isHelipadIdent(String ident) {
    return ident.trim().toUpperCase().startsWith('H');
  }

  /// Landing heading from the database: `LEHeadingT` for the low end and
  /// `HEHeading` for the high end, both true. The high end falls back to the
  /// opposite of the low end. Last resort is the ident number times ten plus
  /// the airport's magnetic variation.
  static double? runwayHeading(Map<String, dynamic> row, String end, double? variation) {
    final double? own = _number(end == 'LE' ? row['LEHeadingT'] : row['HEHeading']);
    if (own != null && own > 0 && own <= 360) {
      return own;
    }
    if (end == 'HE') {
      final double? le = _number(row['LEHeadingT']);
      if (le != null && le > 0 && le <= 360) {
        return (le + 180) % 360;
      }
    }
    final String ident = (row['${end}Ident'] ?? '').toString().trim().toUpperCase();
    // 09, 27L. Helipad idents like H1 are not runways.
    final RegExpMatch? match = RegExp(r'^(\d{1,2})[LRC]?$').firstMatch(ident);
    if (match == null) {
      return null;
    }
    final double? number = double.tryParse(match.group(1)!);
    if (number == null || number <= 0 || number > 36) {
      return null;
    }
    return ((number * 10 + (variation ?? 0)) % 360 + 360) % 360;
  }

  /// Every runway end whose landing threshold is inside [glidePolygon]. The far
  /// end of the runway does not have to be inside.
  static List<RunwayCandidate> findCandidates({
    required List<EmergencyAirport> airports,
    required List<LatLng> glidePolygon,
    required LatLng position,
    required WindLookup windFor,
    required RequiredLanding requiredLanding,
  }) {
    final List<RunwayCandidate> found = [];
    for (final EmergencyAirport airport in airports) {
      final (double? windFrom, double? windKt) = windFor(airport);
      for (final Map<String, dynamic> row in airport.runways) {
        final double? length = _number(row['Length']);
        if (length == null || length <= 0) {
          continue;
        }
        final String surface = (row['Surface'] ?? '').toString().toUpperCase();
        if (surface.startsWith('WATER')) {
          continue;
        }
        for (final String end in const ['LE', 'HE']) {
          final String ident = (row['${end}Ident'] ?? '').toString().trim();
          if (ident.isEmpty || isHelipadIdent(ident)) {
            continue;
          }
          final double? heading = runwayHeading(row, end, airport.variation);
          if (heading == null) {
            continue;
          }
          final double? lat = _number(row['${end}Latitude']);
          final double? lon = _number(row['${end}Longitude']);
          LatLng threshold;
          if (lat != null && lon != null && !(lat == 0 && lon == 0)) {
            threshold = LatLng(lat, lon);
          } else {
            // Many fields, private ones especially, publish no runway end
            // coordinates. Put the runway on the airport reference point:
            // the landing end is half a runway length behind it.
            threshold = offsetPoint(airport.coordinate, length / 2 / 6076.12, heading + 180);
          }
          if (!pointInPolygon(threshold, glidePolygon)) {
            continue;
          }
          final double headwind = headwindComponent(heading, windFrom, windKt);
          found.add(RunwayCandidate(
            airport: airport,
            runwayIdent: ident,
            threshold: threshold,
            heading: heading,
            lengthFt: length,
            headwindKt: headwind,
            crosswindKt: crosswindComponent(heading, windFrom, windKt),
            distanceNm: distanceNm(position, threshold),
            bearingDeg: bearingDeg(position, threshold),
            requiredFt: requiredLanding(airport.elevationFt, headwind),
          ));
        }
      }
    }
    return found;
  }

  /// True when the airport has at least one runway row with a length and a
  /// heading for one of its ends.
  static bool hasRunwayData(EmergencyAirport airport) {
    for (final Map<String, dynamic> row in airport.runways) {
      final double? length = _number(row['Length']);
      if (length == null || length <= 0) {
        continue;
      }
      if ((row['Surface'] ?? '').toString().toUpperCase().startsWith('WATER')) {
        continue;
      }
      for (final String end in const ['LE', 'HE']) {
        if (isHelipadIdent((row['${end}Ident'] ?? '').toString())) {
          continue;
        }
        if (runwayHeading(row, end, airport.variation) != null) {
          return true;
        }
      }
    }
    return false;
  }

  /// Airports inside the ring that publish no usable runway data. They can be
  /// landed at as a last resort, into the wind. Without a wind the direction is
  /// straight to the field.
  static List<RunwayCandidate> findNoDataAirports({
    required List<EmergencyAirport> airports,
    required List<LatLng> glidePolygon,
    required LatLng position,
    required WindLookup windFor,
  }) {
    final List<RunwayCandidate> found = [];
    for (final EmergencyAirport airport in airports) {
      if (hasRunwayData(airport) || !pointInPolygon(airport.coordinate, glidePolygon)) {
        continue;
      }
      final (double? windFrom, double? windKt) = windFor(airport);
      final bool wind = windFrom != null && windKt != null && windKt >= 1;
      final double bearing = bearingDeg(position, airport.coordinate);
      found.add(RunwayCandidate(
        airport: airport,
        runwayIdent: '',
        threshold: airport.coordinate,
        heading: wind ? (windFrom % 360 + 360) % 360 : bearing,
        lengthFt: 0,
        headwindKt: wind ? windKt : 0,
        crosswindKt: 0,
        distanceNm: distanceNm(position, airport.coordinate),
        bearingDeg: bearing,
        requiredFt: null,
        noRunwayData: true,
      ));
    }
    return found;
  }

  /// Most headwind among the runways that are long enough, nearest on a tie.
  /// When none is long enough, the longest one is still offered as less than ideal.
  /// When there is no runway at all, the nearest airport without runway data is
  /// offered, also as less than ideal.
  static RunwaySelection select(List<RunwayCandidate> candidates, {List<RunwayCandidate> noData = const []}) {
    if (candidates.isEmpty) {
      if (noData.isEmpty) {
        return const RunwaySelection(null, false);
      }
      final List<RunwayCandidate> nearest = List.of(noData)..sort((a, b) => a.distanceNm.compareTo(b.distanceNm));
      return RunwaySelection(nearest.first, true);
    }
    final List<RunwayCandidate> good = candidates.where((c) => c.longEnough).toList();
    if (good.isNotEmpty) {
      good.sort((a, b) {
        final int byWind = b.headwindKt.round().compareTo(a.headwindKt.round());
        return byWind != 0 ? byWind : a.distanceNm.compareTo(b.distanceNm);
      });
      return RunwaySelection(good.first, false);
    }
    final List<RunwayCandidate> all = List.of(candidates);
    all.sort((a, b) {
      final int byLength = b.lengthFt.compareTo(a.lengthFt);
      if (byLength != 0) {
        return byLength;
      }
      final int byWind = b.headwindKt.round().compareTo(a.headwindKt.round());
      return byWind != 0 ? byWind : a.distanceNm.compareTo(b.distanceNm);
    });
    return RunwaySelection(all.first, true);
  }

  /// Direction to land when no runway is identified: directly into the wind.
  /// Without a usable wind it is the current track.
  static OffFieldDirection offFieldDirection({
    required double? windFromDeg,
    required double? windSpeedKt,
    required double trackDeg,
  }) {
    if (windFromDeg != null && windSpeedKt != null && windSpeedKt >= 1) {
      final double heading = (windFromDeg % 360 + 360) % 360;
      return OffFieldDirection(heading, true, 'Into wind ${heading.round().toString().padLeft(3, '0')}');
    }
    final double track = (trackDeg % 360 + 360) % 360;
    return OffFieldDirection(track, false, 'Straight ahead (no wind data)');
  }
}

/// Used when the Emergency profile has no checklist chosen.
const List<String> defaultEmergencyChecklist = [
  'Best glide speed - establish and trim',
  'Best landing area - pick it, turn toward it',
  'Fuel selector - fullest tank / BOTH',
  'Mixture - RICH',
  'Carburetor heat - ON',
  'Primer - IN and LOCKED',
  'Fuel pump - ON',
  'Magnetos - BOTH (try L, then R)',
  'If it will not restart - mixture IDLE CUTOFF, fuel OFF, master OFF',
  'Fire: fuel OFF, mixture IDLE CUTOFF, cabin heat OFF, dive to blow out flames',
  'Seat belts and shoulder harness - tight',
  'Doors - unlatch before touchdown',
  'Declare emergency - 121.5 and squawk 7700',
];
