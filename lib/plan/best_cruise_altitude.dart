import 'dart:math' as math;

import 'package:avaremp/aircraft/aircraft_performance.dart';
import 'package:avaremp/destination/destination_calculations.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:latlong2/latlong.dart';

/// One cruise altitude tried while looking for the shortest time en route.
class CruiseAltitudeSample {
  final int altitudeFt;
  final double ktas;
  final double gph;
  final double timeSeconds;

  const CruiseAltitudeSample({
    required this.altitudeFt,
    required this.ktas,
    required this.gph,
    required this.timeSeconds,
  });
}

/// Result of searching cruise altitudes for the shortest time to destination.
class BestCruiseAltitudeResult {
  final CruiseAltitudeSample? best;

  /// A winds-aloft report was available on at least one sample.
  final bool usedWind;

  /// Every tabulated altitude was below [minAltitudeFt].
  final bool terrainBlockedAll;

  /// At least one cruise altitude was left out because it was below the terrain floor.
  final bool excludedForTerrain;

  const BestCruiseAltitudeResult({
    required this.best,
    required this.usedWind,
    required this.terrainBlockedAll,
    required this.excludedForTerrain,
  });
}

/// Picks the cruise altitude with the shortest time to the destination.
///
/// Time uses the same wind triangle as the navigation log: true airspeed from
/// the cruise table, and headwind, tailwind, and crosswind from winds aloft.
/// A climb starts at [fromAltitudeFt], at [climbSpeedFraction] of cruise speed.
/// Climb rate is [climbRateSeaLevelFpm] near the surface and [climbRateTopFpm]
/// at the top of the cruise table. If the leg is shorter than that climb, the
/// rest of the climb is a circle at climb speed.
class BestCruiseAltitude {
  BestCruiseAltitude._();

  /// Climb true airspeed as a fraction of the cruise true airspeed at the altitude being considered.
  static const double climbSpeedFraction = 0.75;

  /// Feet per minute at sea level. Slows linearly to [climbRateTopFpm].
  static const double climbRateSeaLevelFpm = 700;

  /// Feet per minute at the top of the cruise table.
  static const double climbRateTopFpm = 100;

  static double climbRateFpm({required int altitudeFt, required int topAltitudeFt}) {
    if (topAltitudeFt <= 0) {
      return climbRateSeaLevelFpm;
    }
    final double fraction = (altitudeFt / topAltitudeFt).clamp(0.0, 1.0);
    return climbRateSeaLevelFpm + (climbRateTopFpm - climbRateSeaLevelFpm) * fraction;
  }

  /// Tabulated cruise altitudes plus each 1,000 ft step that falls inside them.
  static List<int> altitudesFt(Iterable<num> tabulatedAltitudesFt) {
    final List<int> tabulated = tabulatedAltitudesFt
        .map((num altitude) => altitude.round())
        .where((int altitude) => altitude >= 0)
        .toSet()
        .toList()
      ..sort();
    if (tabulated.isEmpty) {
      return [];
    }
    final int low = tabulated.first;
    final int high = tabulated.last;
    final Set<int> steps = tabulated.toSet();
    final int start = ((low + 999) ~/ 1000) * 1000;
    final int end = (high ~/ 1000) * 1000;
    if (start <= end) {
      for (int altitude = start; altitude <= end; altitude += 1000) {
        steps.add(altitude);
      }
    }
    final List<int> altitudes = steps.toList()..sort();
    return altitudes;
  }

  /// Cruise altitudes to try for [data]: raw POH rows when present, otherwise the built-in table.
  static List<int> altitudesFor(AircraftPerformanceData data) {
    final Iterable<num> tabulated;
    if (data.rawCruiseEntries != null && data.rawCruiseEntries!.isNotEmpty) {
      tabulated =
          data.rawCruiseEntries!.map((Cruise3DEntry entry) => entry.altitude);
    } else {
      tabulated = data.cruiseTable.entries
          .map((CruiseTableEntry entry) => entry.altitude);
    }
    return altitudesFt(tabulated);
  }

  /// Seconds to fly [from] to [to]. Null when the wind triangle has no positive ground speed.
  ///
  /// [windAt] is the wind direction the wind is coming from, in degrees, and the
  /// speed in knots. Null means calm, matching the navigation log.
  static double? legSeconds({
    required LatLng from,
    required LatLng to,
    required double trueAirspeedKt,
    required (double, double)? Function(LatLng point) windAt,
    double skipNm = 0,
  }) {
    if (trueAirspeedKt <= 0 || !trueAirspeedKt.isFinite) {
      return null;
    }
    final GeoCalculations geo = GeoCalculations();
    final List<LatLng> points = geo.findPoints(from, to);
    if (points.length < 2) {
      return geo.calculateDistance(from, to) == 0 ? 0 : null;
    }
    double time = 0;
    double covered = 0;
    for (int index = 0; index < points.length - 1; index++) {
      final double distance =
          geo.calculateDistance(points[index], points[index + 1]);
      final double segmentStart = covered;
      covered += distance;
      if (covered <= skipNm) {
        continue;
      }
      final double course =
          geo.calculateBearing(points[index], points[index + 1]);
      final (double, double)? wind = windAt(points[index]);
      final double? groundSpeed = _groundSpeedKt(
        trueAirspeedKt: trueAirspeedKt,
        courseDeg: course,
        windFrom: wind?.$1,
        windSpeed: wind?.$2,
      );
      if (groundSpeed == null) {
        return null;
      }
      final double flyStart = segmentStart < skipNm ? skipNm : segmentStart;
      time += 3600 * (covered - flyStart) / groundSpeed;
    }
    if (!time.isFinite || time < 0) {
      return null;
    }
    return time;
  }

  /// Seconds to leave [fromAltitudeFt], climb if needed, and reach [to].
  ///
  /// Climb speed is [climbSpeedFraction] of [cruiseKtas]. The clock time to
  /// gain the altitude does not depend on speed. A slower climb covers less
  /// ground, so a short leg finishes the climb in a circle. That circle is
  /// already inside the climb time. Any distance left after leveling off is
  /// flown at cruise speed and at [altitudeFt] wind.
  static double? timeToFly({
    required LatLng from,
    required LatLng to,
    required int altitudeFt,
    required int fromAltitudeFt,
    required double cruiseKtas,
    required int topAltitudeFt,
    required (double?, double?) Function(LatLng point, int altitudeFt) windAt,
    double? climbTrueAirspeedKt,
    double? climbRateConstantFpm,
  }) {
    (double, double)? cruiseWind(LatLng point) {
      final (double? direction, double? speed) = windAt(point, altitudeFt);
      if (direction == null || speed == null) {
        return null;
      }
      return (direction, speed);
    }

    if (altitudeFt <= fromAltitudeFt) {
      return legSeconds(
        from: from,
        to: to,
        trueAirspeedKt: cruiseKtas,
        windAt: cruiseWind,
      );
    }
    final double climbTas = climbTrueAirspeedKt != null && climbTrueAirspeedKt > 0
        ? climbTrueAirspeedKt
        : cruiseKtas * climbSpeedFraction;
    final GeoCalculations geo = GeoCalculations();
    final double course = geo.calculateBearing(from, to);
    double climbSeconds = 0;
    double climbNm = 0;
    int climbed = fromAltitudeFt;
    while (climbed < altitudeFt) {
      final int step = math.min(1000, altitudeFt - climbed);
      final int mid = climbed + step ~/ 2;
      final double roc = climbRateConstantFpm != null && climbRateConstantFpm > 0
          ? climbRateConstantFpm
          : climbRateFpm(altitudeFt: mid, topAltitudeFt: topAltitudeFt);
      if (roc <= 0 || !roc.isFinite) {
        return null;
      }
      final double hours = step / roc / 60.0;
      final (double? direction, double? speed) = windAt(from, mid);
      final double? groundSpeed = _groundSpeedKt(
        trueAirspeedKt: climbTas,
        courseDeg: course,
        windFrom: direction,
        windSpeed: speed,
      );
      if (groundSpeed == null) {
        return null;
      }
      climbSeconds += hours * 3600.0;
      climbNm += groundSpeed * hours;
      climbed += step;
    }
    final double? afterClimb = legSeconds(
      from: from,
      to: to,
      trueAirspeedKt: cruiseKtas,
      skipNm: climbNm,
      windAt: cruiseWind,
    );
    if (afterClimb == null || !climbSeconds.isFinite) {
      return null;
    }
    return climbSeconds + afterClimb;
  }

  static double? _groundSpeedKt({
    required double trueAirspeedKt,
    required double courseDeg,
    required double? windFrom,
    required double? windSpeed,
  }) {
    if (trueAirspeedKt <= 0 || !trueAirspeedKt.isFinite) {
      return null;
    }
    final WindSolution solution = WindSolution.solveWindTriangle(
      windSpeed: windSpeed ?? 0,
      windDirectionDeg: windFrom ?? 0,
      courseDeg: courseDeg,
      trueAirspeed: trueAirspeedKt,
    );
    if (!solution.groundSpeed.isFinite || solution.groundSpeed <= 0) {
      return null;
    }
    return solution.groundSpeed;
  }

  /// Lowest time. Equal times keep the lower altitude.
  static CruiseAltitudeSample? fastest(Iterable<CruiseAltitudeSample> samples) {
    CruiseAltitudeSample? best;
    for (final CruiseAltitudeSample sample in samples) {
      if (sample.ktas <= 0 ||
          !sample.timeSeconds.isFinite ||
          sample.timeSeconds <= 0) {
        continue;
      }
      if (best == null ||
          sample.timeSeconds < best.timeSeconds ||
          (sample.timeSeconds == best.timeSeconds &&
              sample.altitudeFt < best.altitudeFt)) {
        best = sample;
      }
    }
    return best;
  }

  /// [windAt] returns direction-from degrees and speed knots, or nulls when no report exists.
  /// Altitudes below [minAltitudeFt] are not flown.
  /// [fromAltitudeFt] is the altitude at the start of the first leg. Omit it to
  /// score each altitude as if the airplane is already level there.
  static BestCruiseAltitudeResult search({
    required List<({LatLng from, LatLng to})> legs,
    required List<int> altitudesFt,
    required int minAltitudeFt,
    required CruiseResult Function(int altitudeFt) cruiseAt,
    required (double?, double?) Function(LatLng point, int altitudeFt) windAt,
    int? fromAltitudeFt,
    double? climbTrueAirspeedKt,
    double? climbRateConstantFpm,
  }) {
    bool usedWind = false;
    bool triedAltitude = false;
    final int topAltitudeFt = altitudesFt.isEmpty
        ? (fromAltitudeFt ?? 0)
        : altitudesFt.reduce((int a, int b) => a > b ? a : b);
    final Set<int> candidateSet = altitudesFt.where((int altitude) => altitude >= 0).toSet();
    if (fromAltitudeFt != null && fromAltitudeFt >= minAltitudeFt && fromAltitudeFt >= 0) {
      candidateSet.add(fromAltitudeFt);
    }
    final List<int> candidates = candidateSet.toList()..sort();
    final List<CruiseAltitudeSample> samples = [];
    (double?, double?) rememberWind(LatLng point, int altitude) {
      final (double? direction, double? speed) = windAt(point, altitude);
      if (direction != null && speed != null) {
        usedWind = true;
      }
      return (direction, speed);
    }

    for (final int altitude in candidates) {
      if (altitude < minAltitudeFt) {
        continue;
      }
      triedAltitude = true;
      final CruiseResult cruise = cruiseAt(altitude);
      if (cruise.ktas <= 0 || !cruise.ktas.isFinite) {
        continue;
      }
      double time = 0;
      bool usable = true;
      for (int index = 0; index < legs.length; index++) {
        final ({LatLng from, LatLng to}) leg = legs[index];
        final int legStart = index == 0 ? (fromAltitudeFt ?? altitude) : altitude;
        final double? seconds = timeToFly(
          from: leg.from,
          to: leg.to,
          altitudeFt: altitude,
          fromAltitudeFt: legStart,
          cruiseKtas: cruise.ktas,
          topAltitudeFt: topAltitudeFt,
          windAt: rememberWind,
          climbTrueAirspeedKt: climbTrueAirspeedKt,
          climbRateConstantFpm: climbRateConstantFpm,
        );
        if (seconds == null) {
          usable = false;
          break;
        }
        time += seconds;
      }
      if (!usable) {
        continue;
      }
      samples.add(CruiseAltitudeSample(
        altitudeFt: altitude,
        ktas: cruise.ktas,
        gph: cruise.gph,
        timeSeconds: time,
      ));
    }
    return BestCruiseAltitudeResult(
      best: fastest(samples),
      usedWind: usedWind,
      terrainBlockedAll: altitudesFt.isNotEmpty && !triedAltitude,
      excludedForTerrain:
          altitudesFt.any((int altitude) => altitude < minAltitudeFt),
    );
  }

  static String hoursMinutes(double seconds) {
    final Duration duration = Duration(seconds: seconds.round());
    final int minutes = duration.inMinutes % 60;
    return "${duration.inHours}:${minutes.toString().padLeft(2, "0")}";
  }
}
