import 'dart:math';

import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/instruments/pfd_painter.dart';
import 'package:avaremp/io/gps.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:latlong2/latlong.dart';

/// Active course-line geometry for the PFD CDI and autopilot RMB.
class CdiLeg {
  final LatLng origin;
  final Destination next;
  final LatLng position;
  final double courseBearing;
  final double targetBearing;
  final double distance;

  const CdiLeg({
    required this.origin,
    required this.next,
    required this.position,
    required this.courseBearing,
    required this.targetBearing,
    required this.distance,
  });

  /// Signed cross-track, left of course negative. Same unit as [distance].
  double get crossTrackNm => Cdi.crossTrack(
        courseBearing: courseBearing,
        targetBearing: targetBearing,
        distance: distance,
      );

  /// PFD needle in dots (±5). Positive means fly right to the course.
  double get deflection => Cdi.deflection(
        courseBearing: courseBearing,
        targetBearing: targetBearing,
        distance: distance,
      );
}

class Cdi {
  /// Where a direct-to was activated, so the CDI has a fixed course line.
  static LatLng? _directFrom;
  static String? _directKey;
  static String? _obsDestKey;

  static double angularDifference(double hdg, double brg) {
    final double absDiff = (hdg - brg).abs();
    if (absDiff > 180) {
      return 360 - absDiff;
    }
    return absDiff;
  }

  static bool leftOfCourseLine(double bT, double bC) {
    if (bC <= 180) {
      return (bT >= bC && bT <= bC + 180);
    }
    return (bT > bC || bT < bC - 180);
  }

  /// Signed cross-track, left of course negative.
  static double crossTrack({
    required double courseBearing,
    required double targetBearing,
    required double distance,
  }) {
    final double brgDif = angularDifference(courseBearing, targetBearing);
    double deviation = distance * sin(brgDif * pi / 180);
    if (leftOfCourseLine(targetBearing, courseBearing)) {
      deviation = -deviation;
    }
    return deviation;
  }

  /// PFD needle in dots. One dot per distance unit, ±5 full scale.
  /// Inside [PfdPainter.vnavApproachDistance] the scale is 4×.
  static double deflection({
    required double courseBearing,
    required double targetBearing,
    required double distance,
  }) {
    final double brgDif = angularDifference(courseBearing, targetBearing);
    double value = -crossTrack(
      courseBearing: courseBearing,
      targetBearing: targetBearing,
      distance: distance,
    );
    if (brgDif >= 90) {
      value = -value;
    }
    if (distance < PfdPainter.vnavApproachDistance) {
      value *= 4;
    }
    if (value > 5) {
      return 5;
    }
    if (value < -5) {
      return -5;
    }
    return value;
  }

  static CdiLeg? resolve({
    required LatLng position,
    required Destination? current,
    required Destination? previous,
    required List<Destination> destinations,
  }) {
    if (current == null) {
      _clearDirectOrigin();
      return null;
    }

    Destination next = current;
    final LatLng origin;
    if (previous != null) {
      origin = previous.coordinate;
      _clearDirectOrigin();
    } else if (destinations.length > 1) {
      final int currentIndex = destinations.indexWhere((d) => d == next);
      if (currentIndex == 0) {
        origin = destinations[0].coordinate;
        next = destinations[1];
      } else {
        origin = destinations[0].coordinate;
      }
    } else {
      origin = _directOrigin(next, position);
    }

    final GeoCalculations geo = GeoCalculations();
    return CdiLeg(
      origin: origin,
      next: next,
      position: position,
      courseBearing: geo.calculateBearing(origin, next.coordinate),
      targetBearing: geo.calculateBearing(position, next.coordinate),
      distance: geo.calculateDistance(position, next.coordinate),
    );
  }

  static String? _destKey(Destination? d) {
    if (d == null) {
      return null;
    }
    return "${d.locationID}|${d.secondaryName ?? ""}|"
        "${d.coordinate.latitude.toStringAsFixed(4)}|"
        "${d.coordinate.longitude.toStringAsFixed(4)}";
  }

  /// True heading of the map segment from dest toward an inbound aircraft.
  /// OBS is the TO course, so the dest-to-plane radial is the reciprocal.
  static double obsPathTrueHeading(double magnetic, double variation) {
    return (magnetic + variation + 180 + 360) % 360;
  }

  /// Map path for the selected OBS course: from the destination toward
  /// an inbound aircraft (full 360°, no nearest-reciprocal fold).
  static List<LatLng> obsPath() {
    final double? obs = Storage().pfdData.obs;
    if (obs == null) {
      return [];
    }
    final Destination? dest =
        Storage().route.getCurrentWaypoint()?.destination;
    if (dest == null) {
      return [];
    }
    final LatLng plane = Gps.toLatLng(Storage().position);
    final GeoCalculations geo = GeoCalculations();
    final double dist = geo.calculateDistance(dest.coordinate, plane);
    if (dist <= 0) {
      return [];
    }
    final double fromDest = obsPathTrueHeading(obs, Storage().area.variation);
    final LatLng planeEnd =
        geo.calculateOffset(dest.coordinate, dist, fromDest);
    final List<LatLng> points = geo.findPoints(dest.coordinate, planeEnd);
    return points.isEmpty ? [dest.coordinate, planeEnd] : points;
  }

  static void setObs(double? magnetic) {
    Storage().pfdData.obs = magnetic == null ? null : (magnetic + 360) % 360;
    if (magnetic != null) {
      Storage().pfdData.to = Storage().pfdData.obs!;
    }
    updatePfd();
    Storage().pfdChange.value++;
  }

  /// Step the OBS course. Starts from the current course when OBS is unset.
  static void nudgeObs(double deltaDeg) {
    final PfdData pfd = Storage().pfdData;
    setObs(((pfd.obs ?? pfd.to) + deltaDeg + 360) % 360);
  }

  /// Publish the current GPS/route CDI onto [PfdData].
  static void updatePfd() {
    final Destination? current =
        Storage().route.getCurrentWaypoint()?.destination;
    final String? destKey = _destKey(current);
    if (_obsDestKey != null && destKey != _obsDestKey) {
      Storage().pfdData.obs = null;
    }
    _obsDestKey = destKey;

    final CdiLeg? leg = resolve(
      position: Gps.toLatLng(Storage().position),
      current: current,
      previous: Storage().route.getPreviousDestination(),
      destinations: Storage().route.getAllDestinations(),
    );
    final PfdData pfd = Storage().pfdData;
    if (pfd.obs != null) {
      pfd.to = pfd.obs!;
    } else if (current != null) {
      pfd.to = GeoCalculations.getMagneticHeading(
          GeoCalculations().calculateBearing(
              Gps.toLatLng(Storage().position), current.coordinate),
          current.geoVariation ?? Storage().area.variation);
    }
    if (leg == null) {
      pfd.gpsCdi = 0;
      return;
    }
    final double variation = Storage().area.variation;
    final double courseTrue = pfd.obs != null
        ? (pfd.obs! + variation + 360) % 360
        : leg.courseBearing;
    final double value = deflection(
      courseBearing: courseTrue,
      targetBearing: leg.targetBearing,
      distance: leg.distance,
    );
    pfd.setCdi(value);
    pfd.gpsCdi = value;
  }

  static LatLng _directOrigin(Destination destination, LatLng position) {
    final String key = "${destination.locationID}|${destination.secondaryName ?? ""}|"
        "${destination.coordinate.latitude.toStringAsFixed(4)}|"
        "${destination.coordinate.longitude.toStringAsFixed(4)}";
    if (_directKey != key || _directFrom == null) {
      _directKey = key;
      _directFrom = position;
    }
    return _directFrom!;
  }

  static void _clearDirectOrigin() {
    _directKey = null;
    _directFrom = null;
  }
}

class Vdi {
  static double glideSlope({
    required double relativeAglFt,
    required double distance,
  }) {
    if (distance <= 0) {
      return 0;
    }
    final double destInFeet = distance * 6076.12;
    final double vdi = atan(relativeAglFt / destInFeet) * 180 / pi;
    if (vdi >= PfdPainter.vnavHigh) {
      return PfdPainter.vnavHigh;
    }
    if (vdi <= PfdPainter.vnavLow) {
      return PfdPainter.vnavLow;
    }
    return vdi;
  }

  static void updatePfd() {
    final Destination? dest =
        Storage().route.getCurrentWaypoint()?.destination;
    double vdi = 0;
    if (dest is AirportDestination && dest.elevation != null) {
      final double distance = GeoCalculations().calculateDistance(
          Gps.toLatLng(Storage().position), dest.coordinate);
      final double relativeAgl =
          Storage().units.mToF * Storage().position.altitude - dest.elevation!;
      vdi = glideSlope(relativeAglFt: relativeAgl, distance: distance);
    }
    Storage().pfdData.vdi = vdi;
  }
}
