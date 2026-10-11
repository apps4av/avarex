import 'dart:math';

import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/instruments/pfd_painter.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// One landing direction of a physical runway, carrying everything the PFD
/// needs to draw it in a pilot's-eye perspective.
///
/// All distances are in feet, all headings are true. The runway frame has its
/// origin at the pavement end of the landing direction, `along` increasing
/// toward the far end and `cross` positive to the right of the centerline.
class PfdRunwayEnd {
  static const double ftPerDegLat = 60 * 1852 * 3.28084; // 364,567 ft
  static const double earthRadiusFt = 6371000 * 3.28084;

  final String airportId;
  final String ident;
  final String farIdent;
  final LatLng physicalEnd;
  final LatLng farEnd;
  final double headingTrue;
  final double lengthFt;
  final double widthFt;
  final double displacedFt;
  final double farDisplacedFt;
  final double endElevFt;
  final double farElevFt;

  const PfdRunwayEnd({
    required this.airportId,
    required this.ident,
    required this.farIdent,
    required this.physicalEnd,
    required this.farEnd,
    required this.headingTrue,
    required this.lengthFt,
    required this.widthFt,
    required this.displacedFt,
    required this.farDisplacedFt,
    required this.endElevFt,
    required this.farElevFt,
  });

  String get key => '$airportId|$ident';

  /// Surface elevation at a given along-track position (clamped to pavement).
  double elevationAt(double alongFt) {
    final double t = (alongFt / lengthFt).clamp(0.0, 1.0);
    return endElevFt + (farElevFt - endElevFt) * t;
  }

  /// Aircraft position expressed in the runway frame (along, cross) in feet.
  (double alongFt, double crossFt) frameOf(double lat, double lon) {
    final double n = (lat - physicalEnd.latitude) * ftPerDegLat;
    final double e = (lon - physicalEnd.longitude) * ftPerDegLat *
        cos(GeoCalculations.toRadians(physicalEnd.latitude));
    final double h = GeoCalculations.toRadians(headingTrue);
    final double along = n * cos(h) + e * sin(h);
    final double cross = e * cos(h) - n * sin(h);
    return (along, cross);
  }

  /// Straight-line feet from the aircraft to the landing threshold.
  double distanceToThresholdFt(double lat, double lon) {
    final (along, cross) = frameOf(lat, lon);
    final double dAlong = along - displacedFt;
    return sqrt(dAlong * dAlong + cross * cross);
  }
}

/// Parses database runway rows into landing directions.
class PfdRunwayParser {
  static List<PfdRunwayEnd> parse(AirportDestination ap) {
    final List<PfdRunwayEnd> out = [];
    final GeoCalculations geo = GeoCalculations();
    const Distance haversine = Distance(calculator: Haversine());

    double num(dynamic v, double fallback) {
      try {
        final double d = double.parse(v.toString().trim());
        return d.isFinite ? d : fallback;
      } catch (_) {
        return fallback;
      }
    }

    for (final r in ap.runways) {
      try {
        final String le = (r['LEIdent'] as String?)?.trim() ?? '';
        final String he = (r['HEIdent'] as String?)?.trim() ?? '';
        if (le.isEmpty || he.isEmpty) continue; // helipads / stubs

        final LatLng lePos = LatLng(
            double.parse(r['LELatitude'].toString()),
            double.parse(r['LELongitude'].toString()));
        final LatLng hePos = LatLng(
            double.parse(r['HELatitude'].toString()),
            double.parse(r['HELongitude'].toString()));

        // Pavement geometry comes from the end coordinates so both ends land
        // where the database says they are; published length is a fallback.
        double lengthFt = haversine.as(LengthUnit.Meter, lePos, hePos) * 3.28084;
        if (lengthFt < 300) {
          lengthFt = num(r['Length'], 0);
          if (lengthFt < 300) continue;
        }
        final double widthFt = max(20.0, num(r['Width'], 75));
        final double apElev = ap.elevation ?? 0;
        final double leElev = num(r['LEElevation'], apElev);
        final double heElev = num(r['HEElevation'], apElev);
        final double leDt = max(0.0, num(r['LEDT'], 0));
        final double heDt = max(0.0, num(r['HEDT'], 0));

        out.add(PfdRunwayEnd(
          airportId: ap.locationID,
          ident: le,
          farIdent: he,
          physicalEnd: lePos,
          farEnd: hePos,
          headingTrue: geo.calculateBearing(lePos, hePos),
          lengthFt: lengthFt,
          widthFt: widthFt,
          displacedFt: leDt,
          farDisplacedFt: heDt,
          endElevFt: leElev,
          farElevFt: heElev,
        ));
        out.add(PfdRunwayEnd(
          airportId: ap.locationID,
          ident: he,
          farIdent: le,
          physicalEnd: hePos,
          farEnd: lePos,
          headingTrue: geo.calculateBearing(hePos, lePos),
          lengthFt: lengthFt,
          widthFt: widthFt,
          displacedFt: heDt,
          farDisplacedFt: leDt,
          endElevFt: heElev,
          farElevFt: leElev,
        ));
      } catch (_) {
        continue;
      }
    }
    return out;
  }
}

/// Picks the runway end the aircraft is most likely landing on and publishes
/// it to [PfdData.runway] for the PFD painter.
///
/// Candidates come from the closest airport and, if different, the airport
/// that is the active plan waypoint. Airports are (re)loaded on the slow
/// [Area.update] cadence; selection runs at 1 Hz and is pure math.
class PfdRunwaySelector {
  /// Show the runway only within this range of the threshold.
  static const double maxRangeNm = 10;
  static const double _maxRangeFt = maxRangeNm * 6076.12;

  /// Track must be within this many degrees of the runway heading.
  static const double _maxTrackDiffDeg = 45;

  /// Aircraft must be within this angle off the extended centerline.
  static const double _maxOffsetDeg = 35;

  /// Below this ground speed the GPS track is noise; use AHRS heading or hold.
  static const double _minTrackSpeedKt = 5;

  /// A new candidate must beat the current one by this much to replace it.
  static const double _switchHysteresis = 10;

  final Map<String, AirportDestination?> _airports = {};
  List<PfdRunwayEnd> _candidates;
  PfdRunwayEnd? _selected;
  double _selectedScore = double.infinity;

  /// [candidates] seeds the runway list (used when no database is available).
  PfdRunwaySelector({List<PfdRunwayEnd> candidates = const []})
      : _candidates = candidates;

  PfdRunwayEnd? get selected => _selected;

  /// Reload candidate airports. Call from [Area.update].
  Future<void> loadAirports(Destination? closest) async {
    final Set<String> ids = {};
    final String? c = closest?.locationID;
    if (c != null && c.isNotEmpty) ids.add(c);
    final Destination? planDest = Storage().route.getCurrentWaypoint()?.destination;
    if (planDest is AirportDestination) ids.add(planDest.locationID);

    final List<PfdRunwayEnd> out = [];
    for (final id in ids) {
      if (!_airports.containsKey(id)) {
        try {
          _airports[id] = await MainDatabaseHelper.db.findAirport(id);
        } catch (_) {
          _airports[id] = null;
        }
      }
      final AirportDestination? ap = _airports[id];
      if (ap != null) out.addAll(PfdRunwayParser.parse(ap));
    }
    // Keep the cache bounded to the airports in play.
    _airports.removeWhere((k, _) => !ids.contains(k));
    _candidates = out;
  }

  /// Select the best runway end for the current position / track, 1 Hz.
  void update(Position position) {
    final double lat = position.latitude;
    final double lon = position.longitude;
    final PfdData pfd = Storage().pfdData;

    double? track;
    if (pfd.ahrsHeadingLive) {
      track = (pfd.yaw + Storage().area.variation + 360) % 360;
    } else if (GeoCalculations.convertSpeed(position.speed) >= _minTrackSpeedKt) {
      track = position.heading;
    }

    PfdRunwayEnd? best;
    double bestScore = double.infinity;
    if (track != null) {
      for (final rw in _candidates) {
        final double? s = _score(rw, lat, lon, track);
        if (s != null && s < bestScore) {
          bestScore = s;
          best = rw;
        }
      }
    }

    // Hysteresis: keep the current selection while it is still plausible
    // unless the challenger is clearly better.
    final PfdRunwayEnd? cur = _selected;
    if (cur != null) {
      final double? curScore = track == null
          ? (cur.distanceToThresholdFt(lat, lon) <= _maxRangeFt ? _selectedScore : null)
          : _score(cur, lat, lon, track);
      if (curScore != null) {
        if (best == null || best.key == cur.key || bestScore > curScore - _switchHysteresis) {
          _selectedScore = curScore;
          pfd.runway = cur;
          return;
        }
      }
    }

    _selected = best;
    _selectedScore = bestScore;
    pfd.runway = best;
  }

  /// Lower is better; null means not a landing candidate from here.
  double? _score(PfdRunwayEnd rw, double lat, double lon, double track) {
    final (along, cross) = rw.frameOf(lat, lon);
    // Past the far end of the pavement: not landing this way.
    if (along > rw.lengthFt + 300) return null;

    final double dAlong = along - rw.displacedFt; // negative on approach
    final double dist = sqrt(dAlong * dAlong + cross * cross);
    if (dist > _maxRangeFt) return null;

    final double trackDiff = _angleDiff(track, rw.headingTrue);
    if (trackDiff > _maxTrackDiffDeg) return null;

    // Angle off the extended centerline as seen from the threshold. Over or
    // right next to the pavement the angle is meaningless; use lateral feet.
    double offsetDeg;
    if (dAlong < -500) {
      offsetDeg = GeoCalculations.toDegrees(atan2(cross.abs(), -dAlong));
      if (offsetDeg > _maxOffsetDeg) return null;
    } else {
      if (cross.abs() > max(1000.0, rw.widthFt * 4)) return null;
      offsetDeg = 0;
    }

    return trackDiff + offsetDeg + dist / 6076.12;
  }

  static double _angleDiff(double a, double b) {
    double d = (a - b).abs() % 360;
    if (d > 180) d = 360 - d;
    return d;
  }
}
