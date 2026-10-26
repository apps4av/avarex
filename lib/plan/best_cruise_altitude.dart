import 'dart:math' as math;

import 'package:avaremp/aircraft/aircraft_performance.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/destination/destination_calculations.dart';
import 'package:avaremp/io/gps.dart';
import 'package:avaremp/plan/plan_route.dart';
import 'package:avaremp/plan/waypoint.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:avaremp/weather/winds_cache.dart';
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

/// Picks cruise altitudes for the shortest time to the destination.
///
/// [choose] walks the whole route. A climb is the fastest altitude for the
/// rest of the route, at least [terrainClearanceFt] above the terrain in the
/// next [holdNm] miles, and that climb then waits [holdNm] miles. Once level,
/// the course from the first fix to the last sets the altitude: east is an
/// odd thousand and west is an even thousand. A lower altitude can be chosen
/// after [descentHoldNm] miles, once
/// the airplane is at the current altitude, when the lower one is faster over
/// that stretch.
/// Climb and descent use the aircraft climb speed and climb rate. Time and
/// fuel while the altitude is changing use that climb speed.
///
/// [search] scores one altitude for a whole leg. A climb starts at
/// [fromAltitudeFt], at [climbSpeedFraction] of cruise speed. Climb rate is
/// [climbRateSeaLevelFpm] near the surface and [climbRateTopFpm] at the top of
/// the cruise table. If the leg is shorter than that climb, the rest of the
/// climb is a circle at climb speed. A descent in [search] does not add time.
class BestCruiseAltitude {
  BestCruiseAltitude._();

  /// Miles before the altitude may go up. The altitude also has to clear the terrain this far ahead.
  static const double holdNm = 50;

  /// Miles before the altitude may go down, when the lower altitude is faster.
  static const double descentHoldNm = 20;

  /// Feet above the highest terrain in the next [holdNm] miles.
  static const int terrainClearanceFt = 1000;

  /// Terrain sample spacing. Matches the plan chart, which draws elevation every mile.
  static const double terrainSpacingNm = 1;

  /// Climb true airspeed as a fraction of the cruise true airspeed at the altitude being considered.
  static const double climbSpeedFraction = 0.75;

  /// Feet per minute at sea level. Slows linearly to [climbRateTopFpm].
  static const double climbRateSeaLevelFpm = 700;

  /// Feet per minute at the top of the cruise table.
  static const double climbRateTopFpm = 100;

  /// Level cruise altitude for a magnetic course. East (0–179) is an odd
  /// thousand. West (180–359) is an even thousand. Both are multiples of 500.
  /// An altitude still being climbed toward is not required to match.
  static bool matchesCourse(int altitudeFt, double magneticCourseDeg) {
    if (altitudeFt <= 0 || altitudeFt % 500 != 0 || altitudeFt % 1000 != 0) {
      return false;
    }
    final double course = (magneticCourseDeg % 360 + 360) % 360;
    final bool east = course < 180;
    final bool oddThousand = (altitudeFt ~/ 1000).isOdd;
    return east ? oddThousand : !oddThousand;
  }

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

  /// Points about [spacingNm] apart along [legs], with the distance at the end of each leg.
  static RouteTrack buildTrack(
    List<({LatLng from, LatLng to})> legs, {
    double spacingNm = 5,
  }) {
    final GeoCalculations geo = GeoCalculations();
    final List<({double nm, LatLng at})> points = [];
    final List<double> legEndNm = [];
    if (legs.isEmpty) {
      return RouteTrack(points: points, legEndNm: legEndNm);
    }
    double nm = 0;
    points.add((nm: 0, at: legs.first.from));
    for (final ({LatLng from, LatLng to}) leg in legs) {
      final List<LatLng> samples = geo.findPoints(leg.from, leg.to, spacingNm);
      if (samples.length < 2) {
        nm += geo.calculateDistance(leg.from, leg.to);
        points.add((nm: nm, at: leg.to));
        legEndNm.add(nm);
        continue;
      }
      for (int index = 1; index < samples.length; index++) {
        nm += geo.calculateDistance(samples[index - 1], samples[index]);
        points.add((nm: nm, at: samples[index]));
      }
      legEndNm.add(nm);
    }
    return RouteTrack(points: points, legEndNm: legEndNm);
  }

  /// Cruise altitudes along [track]. A climb is the fastest altitude for the
  /// rest of the route, then it waits [holdNm] miles. A descent can be chosen
  /// every [descentHoldNm] miles after the airplane reaches that altitude.
  ///
  /// Each choice stays [terrainClearanceFt] above the terrain until the next choice.
  /// The airplane climbs and descends at [climbTrueAirspeedKt] and [climbRateConstantFpm]
  /// when those are set. Otherwise climb speed is [climbSpeedFraction] of the cruise
  /// speed it is climbing toward, and the rate slows from [climbRateSeaLevelFpm] to
  /// [climbRateTopFpm]. When [arriveAtEnd] is set, the flight finishes at [endAltitudeFt].
  static RouteCruiseResult choose({
    required RouteTrack track,
    required List<double?> terrainFt,
    required List<int> altitudesFt,
    required int startAltitudeFt,
    required int endAltitudeFt,
    required bool arriveAtEnd,
    required CruiseResult Function(int altitudeFt) cruiseAt,
    required (double?, double?) Function(LatLng point, int altitudeFt) windAt,
    double? climbTrueAirspeedKt,
    double? climbRateConstantFpm,
    int? topAltitudeFt,
    double Function(double nm)? variationAt,
  }) {
    return _planRoute(
      track: track,
      terrainFt: terrainFt,
      altitudesFt: altitudesFt,
      startAltitudeFt: startAltitudeFt,
      endAltitudeFt: endAltitudeFt,
      arriveAtEnd: arriveAtEnd,
      cruiseAt: cruiseAt,
      windAt: windAt,
      climbTasKt: climbTrueAirspeedKt ?? 0,
      climbRateFpm: climbRateConstantFpm ?? 0,
      topAltitudeFt: topAltitudeFt ?? 0,
      variationAt: variationAt,
    );
  }
}

/// One chosen cruise altitude, in effect from [startNm] until the next step.
class CruiseStep {
  final double startNm;
  final int altitudeFt;
  final double ktas;
  final double gph;

  const CruiseStep({
    required this.startNm,
    required this.altitudeFt,
    required this.ktas,
    required this.gph,
  });

  Map<String, Object> toJson() => {
        'nm': startNm,
        'alt': altitudeFt,
        'ktas': ktas,
        'gph': gph,
      };
}

/// Altitudes chosen along a route, plus the climb used to fly between them.
class CruiseProfile {
  final List<CruiseStep> steps;
  final double climbTasKt;
  final double climbRateFpm;
  final int topAltitudeFt;
  final int startAltitudeFt;
  final int endAltitudeFt;
  final bool arriveAtEnd;
  final double totalNm;

  /// Terrain elevation along the route. Empty when elevation is unavailable.
  final List<({double nm, double ft})> terrain;

  const CruiseProfile({
    required this.steps,
    required this.climbTasKt,
    required this.climbRateFpm,
    required this.topAltitudeFt,
    required this.startAltitudeFt,
    required this.endAltitudeFt,
    required this.arriveAtEnd,
    required this.totalNm,
    this.terrain = const [],
  });

  CruiseStep stepAt(double nm) {
    CruiseStep step = steps.first;
    for (final CruiseStep next in steps) {
      if (next.startNm <= nm + 0.001) {
        step = next;
      }
    }
    return step;
  }

  /// Use [altitudeFt] from [fromNm] until [toNm]. Steps after [toNm] stay in effect.
  CruiseProfile replaceSpan({
    required double fromNm,
    required double toNm,
    required int altitudeFt,
    required double ktas,
    required double gph,
  }) {
    if (steps.isEmpty || toNm <= fromNm + 0.001) {
      return this;
    }
    final CruiseStep resume = stepAt(toNm);
    final List<CruiseStep> kept = [
      for (final CruiseStep step in steps)
        if (step.startNm < fromNm - 0.001 || step.startNm >= toNm - 0.001) step,
    ];
    kept.add(CruiseStep(
      startNm: fromNm,
      altitudeFt: altitudeFt,
      ktas: ktas,
      gph: gph,
    ));
    final bool hasResume = kept.any((CruiseStep step) => (step.startNm - toNm).abs() <= 0.05);
    if (!hasResume && toNm < totalNm - 0.05) {
      kept.add(CruiseStep(
        startNm: toNm,
        altitudeFt: resume.altitudeFt,
        ktas: resume.ktas,
        gph: resume.gph,
      ));
    }
    kept.sort((CruiseStep a, CruiseStep b) => a.startNm.compareTo(b.startNm));
    return CruiseProfile(
      steps: kept,
      climbTasKt: climbTasKt,
      climbRateFpm: climbRateFpm,
      topAltitudeFt: topAltitudeFt,
      startAltitudeFt: startAltitudeFt,
      endAltitudeFt: endAltitudeFt,
      arriveAtEnd: arriveAtEnd,
      totalNm: totalNm,
      terrain: terrain,
    );
  }

  String signature() {
    return steps
        .map((CruiseStep step) =>
            '${step.startNm.toStringAsFixed(0)}:${step.altitudeFt}')
        .join(',');
  }

  Map<String, Object> toJson() => {
        'steps': steps.map((CruiseStep step) => step.toJson()).toList(),
        'climbKt': climbTasKt,
        'climbFpm': climbRateFpm,
        'topFt': topAltitudeFt,
        'startFt': startAltitudeFt,
        'endFt': endAltitudeFt,
        'arrive': arriveAtEnd,
        'totalNm': totalNm,
        'terrain': [
          for (final ({double nm, double ft}) sample in terrain)
            {'nm': sample.nm, 'ft': sample.ft},
        ],
      };

  static CruiseProfile? tryParse(Map<String, dynamic> map) {
    try {
      final Object? raw = map['steps'];
      if (raw is! List || raw.isEmpty) {
        return null;
      }
      final List<CruiseStep> steps = [];
      for (final Object? item in raw) {
        if (item is! Map) {
          return null;
        }
        final Map<String, dynamic> step = Map<String, dynamic>.from(item);
        steps.add(CruiseStep(
          startNm: (step['nm'] as num).toDouble(),
          altitudeFt: (step['alt'] as num).round(),
          ktas: (step['ktas'] as num).toDouble(),
          gph: (step['gph'] as num).toDouble(),
        ));
      }
      return CruiseProfile(
        steps: steps,
        climbTasKt: (map['climbKt'] as num?)?.toDouble() ?? 0,
        climbRateFpm: (map['climbFpm'] as num?)?.toDouble() ?? 0,
        topAltitudeFt: (map['topFt'] as num?)?.round() ?? 0,
        startAltitudeFt: (map['startFt'] as num?)?.round() ?? steps.first.altitudeFt,
        endAltitudeFt: (map['endFt'] as num?)?.round() ?? 0,
        arriveAtEnd: map['arrive'] == true,
        totalNm: (map['totalNm'] as num?)?.toDouble() ?? 0,
        terrain: _terrainFromJson(map['terrain']),
      );
    } catch (_) {
      return null;
    }
  }

  /// Fly this profile on [track]. Null wind is calm. A wind the airplane cannot
  /// make headway against is treated as calm so the log still has a time.
  ProfileFlight fly(
    RouteTrack track,
    (double?, double?) Function(LatLng point, int altitudeFt) windAt,
  ) {
    final List<FlownSample> samples = [];
    _integrate(
      track: track,
      fromNm: 0,
      toNm: totalNm,
      startAlt: startAltitudeFt.toDouble(),
      totalNm: totalNm,
      endAltitudeFt: endAltitudeFt,
      arriveAtEnd: arriveAtEnd,
      climbTasKt: climbTasKt,
      climbRateFpm: climbRateFpm,
      topAltitudeFt: topAltitudeFt,
      cruiseAltAt: (double nm) => stepAt(nm).altitudeFt,
      cruiseTasAt: (double nm) => stepAt(nm).ktas,
      gphAt: (double nm) => stepAt(nm).gph,
      windAt: windAt,
      strict: false,
      terrain: terrain,
      samples: samples,
    );
    return ProfileFlight(profile: this, track: track, samples: samples);
  }
}

/// Sampled route used to choose and fly altitudes.
class RouteTrack {
  final List<({double nm, LatLng at})> points;
  final List<double> legEndNm;

  const RouteTrack({required this.points, required this.legEndNm});

  double get totalNm => points.isEmpty ? 0 : points.last.nm;

  double nearest(LatLng point, double fromNm, double toNm) {
    final GeoCalculations geo = GeoCalculations();
    double bestNm = fromNm;
    double best = double.infinity;
    for (final ({double nm, LatLng at}) sample in points) {
      if (sample.nm < fromNm - 0.01 || sample.nm > toNm + 0.01) {
        continue;
      }
      final double distance = geo.calculateDistance(sample.at, point);
      if (distance < best) {
        best = distance;
        bestNm = sample.nm;
      }
    }
    if (bestNm < fromNm) {
      return fromNm;
    }
    if (bestNm > toNm) {
      return toNm;
    }
    return bestNm;
  }
}

/// One point on the flown altitude, with time and fuel from the start of the route.
class FlownSample {
  final double nm;
  final double altitudeFt;
  final double timeSeconds;
  final double fuelGal;

  const FlownSample({
    required this.nm,
    required this.altitudeFt,
    required this.timeSeconds,
    required this.fuelGal,
  });
}

/// Time, fuel, and altitude that result from flying a [CruiseProfile].
class ProfileFlight {
  final CruiseProfile profile;
  final RouteTrack track;
  final List<FlownSample> samples;

  const ProfileFlight({
    required this.profile,
    required this.track,
    required this.samples,
  });

  List<double> get fixNm => [0, ...track.legEndNm];

  double timeAt(double nm) => _valueAt(nm, (FlownSample sample) => sample.timeSeconds);

  double fuelAt(double nm) => _valueAt(nm, (FlownSample sample) => sample.fuelGal);

  double altitudeAt(double nm) => _valueAt(nm, (FlownSample sample) => sample.altitudeFt);

  /// Altitude for a plan row or a navigation-log column. A climb that has not
  /// reached its cruise step keeps the altitude flown so far. Once that step
  /// has been reached, the arrival descent leaves the number on the step.
  double reportedAltitudeAt(double nm) {
    final double flown = altitudeAt(nm);
    final CruiseStep step = profile.stepAt(nm);
    if ((flown - step.altitudeFt).abs() <= 100) {
      return step.altitudeFt.toDouble();
    }
    if (flown > step.altitudeFt) {
      return flown;
    }
    for (final FlownSample sample in samples) {
      if (sample.nm + 0.05 < step.startNm) {
        continue;
      }
      if (sample.nm > nm + 0.05) {
        break;
      }
      if ((sample.altitudeFt - step.altitudeFt).abs() <= 100) {
        return step.altitudeFt.toDouble();
      }
    }
    return flown;
  }

  ({double timeSeconds, double fuelGal, double distanceNm}) span(double fromNm, double toNm) {
    final double end = profile.totalNm;
    final double a = fromNm.clamp(0.0, end).toDouble();
    final double b = toNm.clamp(0.0, end).toDouble();
    final double time = timeAt(b) - timeAt(a);
    final double fuel = fuelAt(b) - fuelAt(a);
    final double distance = b - a;
    return (
      timeSeconds: time < 0 ? 0 : time,
      fuelGal: fuel < 0 ? 0 : fuel,
      distanceNm: distance < 0 ? 0 : distance,
    );
  }

  double _valueAt(double nm, double Function(FlownSample sample) read) {
    if (samples.isEmpty) {
      return 0;
    }
    if (nm <= samples.first.nm) {
      return read(samples.first);
    }
    for (int index = 1; index < samples.length; index++) {
      if (nm <= samples[index].nm) {
        final double span = samples[index].nm - samples[index - 1].nm;
        final double t = span <= 0 ? 0 : (nm - samples[index - 1].nm) / span;
        return read(samples[index - 1]) + (read(samples[index]) - read(samples[index - 1])) * t;
      }
    }
    return read(samples.last);
  }
}

/// One altitude flown level from the start, so later decisions can reuse its time.
class _LevelFlight {
  final _LegFly? flown;
  final List<FlownSample> samples;

  const _LevelFlight(this.flown, this.samples);

  double? remainingSeconds(double nm) {
    if (flown == null || samples.isEmpty) {
      return null;
    }
    final double rest = samples.last.timeSeconds - _flownValue(samples, nm, (FlownSample sample) => sample.timeSeconds);
    return rest < 0 ? 0 : rest;
  }

  double altitudeAt(double nm) {
    if (samples.isEmpty) {
      return 0;
    }
    return _flownValue(samples, nm, (FlownSample sample) => sample.altitudeFt);
  }
}

double _flownValue(List<FlownSample> samples, double nm, double Function(FlownSample sample) read) {
  if (samples.isEmpty) {
    return 0;
  }
  if (nm <= samples.first.nm) {
    return read(samples.first);
  }
  if (nm >= samples.last.nm) {
    return read(samples.last);
  }
  int lo = 1;
  int hi = samples.length - 1;
  while (lo < hi) {
    final int mid = (lo + hi) >> 1;
    if (samples[mid].nm < nm) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  final FlownSample before = samples[lo - 1];
  final FlownSample after = samples[lo];
  final double span = after.nm - before.nm;
  final double t = span <= 0 ? 0 : (nm - before.nm) / span;
  return read(before) + (read(after) - read(before)) * t;
}

/// Altitudes chosen for a route, and whether terrain or wind limited them.
class RouteCruiseResult {
  final CruiseProfile? profile;
  final bool usedWind;

  /// A chosen altitude is still below the terrain clearance.
  final bool terrainShort;

  const RouteCruiseResult({
    required this.profile,
    required this.usedWind,
    required this.terrainShort,
  });
}

RouteCruiseResult _planRoute({
  required RouteTrack track,
  required List<double?> terrainFt,
  required List<int> altitudesFt,
  required int startAltitudeFt,
  required int endAltitudeFt,
  required bool arriveAtEnd,
  required CruiseResult Function(int altitudeFt) cruiseAt,
  required (double?, double?) Function(LatLng point, int altitudeFt) windAt,
  required double climbTasKt,
  required double climbRateFpm,
  required int topAltitudeFt,
  double Function(double nm)? variationAt,
}) {
  if (track.points.length < 2 || track.totalNm <= 0 || altitudesFt.isEmpty) {
    return const RouteCruiseResult(profile: null, usedWind: false, terrainShort: false);
  }
  bool usedWind = false;
  bool terrainShort = false;
  (double?, double?) remember(LatLng point, int altitude) {
    final (double? direction, double? speed) = windAt(point, altitude);
    if (direction != null && speed != null) {
      usedWind = true;
    }
    return (direction, speed);
  }

  final List<({double nm, double ft})> terrain = _knownTerrain(track, terrainFt);
  final List<int> sorted = altitudesFt.where((int altitude) => altitude >= 0).toSet().toList()..sort();
  if (sorted.isEmpty) {
    return const RouteCruiseResult(profile: null, usedWind: false, terrainShort: false);
  }
  final int lowest = sorted.first;
  final List<CruiseStep> steps = [];
  double pos = 0;
  double altitude = startAltitudeFt.toDouble();
  double lastChangeNm = 0;
  double lastClimbNm = 0;
  final double total = track.totalNm;
  // One course for the whole plan: first fix to last fix.
  final double routeCourse = _routeMagneticCourse(track.points, variationAt);
  // Miles of climb or descent to simulate before using the level-flight time.
  // Far enough to finish a climb, and short enough that a long route is not
  // integrated again at every decision.
  const double climbLookNm = 250;
  final Map<int, _LevelFlight> levelFlights = {};

  _LegFly? flyCandidate({
    required int candidate,
    required CruiseResult cruise,
    required double fromNm,
    required double toNm,
    required double startAlt,
    List<FlownSample>? samples,
  }) {
    return _integrate(
      track: track,
      fromNm: fromNm,
      toNm: toNm,
      startAlt: startAlt,
      totalNm: total,
      endAltitudeFt: endAltitudeFt,
      arriveAtEnd: arriveAtEnd,
      climbTasKt: climbTasKt,
      climbRateFpm: climbRateFpm,
      topAltitudeFt: topAltitudeFt,
      cruiseAltAt: (double nm) => candidate,
      cruiseTasAt: (double nm) => cruise.ktas,
      gphAt: (double nm) => cruise.gph,
      windAt: remember,
      strict: true,
      terrain: terrain,
      samples: samples,
    );
  }

  _LevelFlight levelFlight(int candidate, CruiseResult cruise) {
    final _LevelFlight? saved = levelFlights[candidate];
    if (saved != null) {
      return saved;
    }
    final List<FlownSample> samples = [];
    final _LegFly? flown = flyCandidate(
      candidate: candidate,
      cruise: cruise,
      fromNm: 0,
      toNm: total,
      startAlt: candidate.toDouble(),
      samples: samples,
    );
    final _LevelFlight flight = _LevelFlight(flown, samples);
    levelFlights[candidate] = flight;
    return flight;
  }

  /// Time from [pos] to the end at [candidate]. The level cruise is computed
  /// once per altitude. A climb or descent is simulated only until that altitude.
  _LegFly? timeOverRest(int candidate, CruiseResult cruise) {
    final _LevelFlight level = levelFlight(candidate, cruise);
    if (level.flown == null) {
      return null;
    }
    if ((altitude - level.altitudeAt(pos)).abs() <= 100) {
      final double? rest = level.remainingSeconds(pos);
      if (rest == null) {
        return null;
      }
      return _LegFly(timeSeconds: rest, fuelGal: 0, endAltitude: candidate.toDouble());
    }
    final double climbEnd = math.min(pos + climbLookNm, total);
    final _LegFly? climb = flyCandidate(
      candidate: candidate,
      cruise: cruise,
      fromNm: pos,
      toNm: climbEnd,
      startAlt: altitude,
    );
    if (climb == null) {
      return null;
    }
    if (climbEnd >= total - 0.05) {
      return climb;
    }
    if ((climb.endAltitude - level.altitudeAt(climbEnd)).abs() > 250) {
      return flyCandidate(
        candidate: candidate,
        cruise: cruise,
        fromNm: pos,
        toNm: total,
        startAlt: altitude,
      );
    }
    final double? rest = level.remainingSeconds(climbEnd);
    if (rest == null) {
      return climb;
    }
    return _LegFly(
      timeSeconds: climb.timeSeconds + rest,
      fuelGal: climb.fuelGal,
      endAltitude: climb.endAltitude,
    );
  }

  ({CruiseStep step, double endAltitude, double timeSeconds})? bestOver(
    double windowEnd,
    List<int> candidates,
  ) {
    if (windowEnd <= pos + 0.01 || candidates.isEmpty) {
      return null;
    }
    final bool wholeRoute = windowEnd >= total - 0.05;
    CruiseStep? best;
    double? bestTime;
    double bestEnd = altitude;
    for (final int candidate in candidates) {
      final CruiseResult cruise = cruiseAt(candidate);
      if (cruise.ktas <= 0 || !cruise.ktas.isFinite) {
        continue;
      }
      final _LegFly? flown = wholeRoute
          ? timeOverRest(candidate, cruise)
          : flyCandidate(
              candidate: candidate,
              cruise: cruise,
              fromNm: pos,
              toNm: windowEnd,
              startAlt: altitude,
            );
      if (flown == null) {
        continue;
      }
      if (best == null ||
          flown.timeSeconds < bestTime! ||
          (flown.timeSeconds == bestTime && candidate < best.altitudeFt)) {
        best = CruiseStep(
          startNm: pos,
          altitudeFt: candidate,
          ktas: cruise.ktas,
          gph: cruise.gph,
        );
        bestTime = flown.timeSeconds;
        bestEnd = flown.endAltitude;
      }
    }
    if (best == null || bestTime == null) {
      return null;
    }
    return (step: best, endAltitude: bestEnd, timeSeconds: bestTime);
  }

  double nextAfter(double origin, double step) {
    double at = origin + step;
    while (at <= pos + 0.05) {
      at += step;
    }
    return at;
  }

  while (pos < total - 0.05) {
    final bool first = steps.isEmpty;
    final bool allowClimb = first || pos - lastClimbNm >= BestCruiseAltitude.holdNm - 0.05;
    final bool allowDescent = !first && pos - lastChangeNm >= BestCruiseAltitude.descentHoldNm - 0.05;
    final double terrainEnd = math.min(pos + BestCruiseAltitude.holdNm, total);
    final int floor = _terrainFloor(track, terrainFt, pos, terrainEnd);
    final List<int> forCourse = [
      for (final int altitude in sorted)
        if (BestCruiseAltitude.matchesCourse(altitude, routeCourse)) altitude,
    ];
    // A cruise table with only one side still flies. Otherwise the route uses
    // an odd thousand when the course from start to end is east, and an even
    // thousand when that course is west.
    final List<int> pool = forCourse.isEmpty ? sorted : forCourse;
    final List<int> opened = [
      for (final int altitude in _cruiseCandidates(pool, floor, altitude, lowest))
        if (pool.contains(altitude)) altitude,
    ];
    final List<int> candidates = opened.isEmpty ? pool : opened;
    if (candidates.isEmpty) {
      break;
    }
    final int? current = first ? null : steps.last.altitudeFt;
    ({CruiseStep step, double endAltitude, double timeSeconds})? chosen;
    // A 20-mile descent check while still climbing would give back an altitude
    // that is faster for the rest of the route.
    final bool atCruise = current != null && altitude >= current - 100;

    // A descent is scored over the next 20 miles against staying put.
    // Terrain clearance still looks 50 miles ahead, so a step down stays
    // 1,000 ft above the terrain in that longer stretch.
    if (allowDescent && atCruise) {
      final List<int> lower = [
        for (final int candidate in candidates)
          if (candidate < current) candidate,
      ];
      final double descentEnd = math.min(pos + BestCruiseAltitude.descentHoldNm, total);
      final stay = bestOver(descentEnd, [current]);
      final down = bestOver(descentEnd, lower);
      if (down != null && (stay == null || down.timeSeconds < stay.timeSeconds)) {
        chosen = down;
      }
    }
    if (chosen == null && allowClimb) {
      // Score the climb over the miles still ahead. A 50-mile window can be
      // spent entirely in the climb, so a higher altitude that is faster for
      // the rest of the route would never be chosen.
      chosen = bestOver(total, candidates);
    }
    double nextLook() {
      return math.min(
        total,
        math.min(
          nextAfter(lastChangeNm, BestCruiseAltitude.descentHoldNm),
          nextAfter(lastClimbNm, BestCruiseAltitude.holdNm),
        ),
      );
    }

    void flyTo(double endNm, CruiseStep flying) {
      if (endNm <= pos + 0.01) {
        return;
      }
      final _LegFly? state = _integrate(
        track: track,
        fromNm: pos,
        toNm: endNm,
        startAlt: altitude,
        totalNm: total,
        endAltitudeFt: endAltitudeFt,
        arriveAtEnd: arriveAtEnd,
        climbTasKt: climbTasKt,
        climbRateFpm: climbRateFpm,
        topAltitudeFt: topAltitudeFt,
        cruiseAltAt: (double nm) => flying.altitudeFt,
        cruiseTasAt: (double nm) => flying.ktas,
        gphAt: (double nm) => flying.gph,
        windAt: remember,
        strict: false,
        terrain: terrain,
      );
      if (state != null) {
        altitude = state.endAltitude;
      }
    }

    if (chosen == null) {
      final double next = nextLook();
      if (next <= pos + 0.05 || steps.isEmpty) {
        break;
      }
      flyTo(next, steps.last);
      pos = next;
      continue;
    }
    if (chosen.step.altitudeFt < floor) {
      terrainShort = true;
    }
    final bool changed = first || steps.last.altitudeFt != chosen.step.altitudeFt;
    if (changed) {
      steps.add(chosen.step);
      lastChangeNm = pos;
      lastClimbNm = pos;
    } else if (allowClimb) {
      lastClimbNm = pos;
    }
    final double next = nextLook();
    if (next <= pos + 0.05) {
      break;
    }
    flyTo(next, chosen.step);
    pos = next;
  }
  if (steps.isEmpty) {
    return RouteCruiseResult(profile: null, usedWind: usedWind, terrainShort: terrainShort);
  }
  return RouteCruiseResult(
    profile: CruiseProfile(
      steps: steps,
      climbTasKt: climbTasKt,
      climbRateFpm: climbRateFpm,
      topAltitudeFt: topAltitudeFt,
      startAltitudeFt: startAltitudeFt,
      endAltitudeFt: endAltitudeFt,
      arriveAtEnd: arriveAtEnd,
      totalNm: total,
      terrain: terrain,
    ),
    usedWind: usedWind,
    terrainShort: terrainShort,
  );
}

List<int> _cruiseCandidates(List<int> sorted, int floor, double currentAlt, int lowest) {
  final Set<int> open = {};
  for (final int altitude in sorted) {
    if (altitude >= floor) {
      open.add(altitude);
    }
  }
  final int have = currentAlt.round();
  if (have >= floor && have >= lowest) {
    open.add(have);
  }
  if (open.isEmpty && sorted.isNotEmpty) {
    return [sorted.last];
  }
  final List<int> candidates = open.toList()..sort();
  return candidates;
}

int _terrainFloor(RouteTrack track, List<double?> terrain, double fromNm, double toNm) {
  double? highest;
  for (int index = 0; index < track.points.length; index++) {
    final double nm = track.points[index].nm;
    if (nm < fromNm - 0.01 || nm > toNm + 0.01) {
      continue;
    }
    if (index >= terrain.length) {
      continue;
    }
    final double? elevation = terrain[index];
    if (elevation == null || !elevation.isFinite) {
      continue;
    }
    if (highest == null || elevation > highest) {
      highest = elevation;
    }
  }
  if (highest == null) {
    return 0;
  }
  return (highest + BestCruiseAltitude.terrainClearanceFt).ceil();
}

class _LegFly {
  final double timeSeconds;
  final double fuelGal;
  final double endAltitude;

  const _LegFly({
    required this.timeSeconds,
    required this.fuelGal,
    required this.endAltitude,
  });
}

/// Mile where the arrival descent begins so the airplane reaches [endAltitudeFt]
/// at [totalNm]. Each mile uses the wind on that mile, and the point does not move.
double? _arrivalDescentNm({
  required RouteTrack track,
  required double totalNm,
  required int endAltitudeFt,
  required double climbTasKt,
  required double climbRateFpm,
  required int topAltitudeFt,
  required int Function(double nm) cruiseAltAt,
  required double Function(double nm) cruiseTasAt,
  required (double?, double?) Function(LatLng point, int altitudeFt) windAt,
  required List<({double nm, double ft})> terrain,
}) {
  if (track.points.length < 2 || totalNm <= 0) {
    return null;
  }
  double nm = totalNm;
  double alt = endAltitudeFt.toDouble();
  while (nm > 0.05) {
    final double step = math.min(1.0, nm);
    final double mid = nm - step / 2;
    final int cruiseTarget = cruiseAltAt(mid);
    if (alt >= cruiseTarget - 1) {
      return nm;
    }
    final double cruiseTas = cruiseTasAt(mid);
    final double rate = climbRateFpm > 0
        ? climbRateFpm
        : BestCruiseAltitude.climbRateFpm(altitudeFt: alt.round(), topAltitudeFt: topAltitudeFt);
    final double verticalTas = climbTasKt > 0
        ? climbTasKt
        : (cruiseTas > 0 ? cruiseTas * BestCruiseAltitude.climbSpeedFraction : 0);
    if (rate <= 0 || verticalTas <= 0) {
      return nm;
    }
    final LatLng point = _pointAt(track.points, mid);
    final double? floor = _clearanceFt(terrain, mid);
    final double windAlt = floor == null ? alt : math.max(alt, floor);
    final (double? direction, double? windSpeed) = windAt(point, windAlt.round());
    final double? groundSpeed = BestCruiseAltitude._groundSpeedKt(
      trueAirspeedKt: verticalTas,
      courseDeg: _courseAt(track.points, mid),
      windFrom: direction,
      windSpeed: windSpeed,
    );
    final double speed = (groundSpeed != null && groundSpeed > 0) ? groundSpeed : verticalTas;
    alt += rate * (step / speed) * 60.0;
    nm -= step;
    if (alt >= cruiseAltAt(math.max(0, nm)) - 1) {
      return nm;
    }
  }
  return 0;
}

_LegFly? _integrate({
  required RouteTrack track,
  required double fromNm,
  required double toNm,
  required double startAlt,
  required double totalNm,
  required int endAltitudeFt,
  required bool arriveAtEnd,
  required double climbTasKt,
  required double climbRateFpm,
  required int topAltitudeFt,
  required int Function(double nm) cruiseAltAt,
  required double Function(double nm) cruiseTasAt,
  required double Function(double nm) gphAt,
  required (double?, double?) Function(LatLng point, int altitudeFt) windAt,
  required bool strict,
  List<({double nm, double ft})> terrain = const [],
  List<FlownSample>? samples,
}) {
  double nm = fromNm;
  double altitude = startAlt;
  double time = 0;
  double fuel = 0;
  // One descent point for the whole arrival. Recomputing it from the ground
  // speed at each mile starts down in a tailwind, then climbs back when the
  // next leg is slower.
  final double? descentFromNm = arriveAtEnd
      ? _arrivalDescentNm(
          track: track,
          totalNm: totalNm,
          endAltitudeFt: endAltitudeFt,
          climbTasKt: climbTasKt,
          climbRateFpm: climbRateFpm,
          topAltitudeFt: topAltitudeFt,
          cruiseAltAt: cruiseAltAt,
          cruiseTasAt: cruiseTasAt,
          windAt: windAt,
          terrain: terrain,
        )
      : null;
  samples?.add(FlownSample(nm: nm, altitudeFt: altitude, timeSeconds: time, fuelGal: fuel));
  while (nm < toNm - 1e-6) {
    final double step = math.min(1.0, toNm - nm);
    final double mid = nm + step / 2;
    final LatLng point = _pointAt(track.points, mid);
    final int cruiseTarget = cruiseAltAt(nm);
    final double cruiseTas = cruiseTasAt(nm);
    final double burn = gphAt(nm);
    final double rate = climbRateFpm > 0
        ? climbRateFpm
        : BestCruiseAltitude.climbRateFpm(altitudeFt: altitude.round(), topAltitudeFt: topAltitudeFt);
    final double verticalTas = climbTasKt > 0
        ? climbTasKt
        : (cruiseTas > 0 ? cruiseTas * BestCruiseAltitude.climbSpeedFraction : 0);
    if (verticalTas <= 0 && cruiseTas <= 0) {
      return strict ? null : _LegFly(timeSeconds: time, fuelGal: fuel, endAltitude: altitude);
    }

    final double? floor = _clearanceFt(terrain, mid);
    final double safeAlt = floor == null ? altitude : math.max(altitude, floor);
    final bool finish = descentFromNm != null &&
        (safeAlt - endAltitudeFt).abs() > 1 &&
        mid >= descentFromNm;

    final bool landing = arriveAtEnd && (nm + step) >= totalNm - 1e-6;
    int target = finish ? endAltitudeFt : cruiseTarget;
    if (floor != null && !landing && target < floor) {
      target = floor.ceil();
    }
    // Wind, time, and fuel use an altitude at least 1,000 ft above the terrain here.
    // The airplane still climbs toward that altitude at its climb rate. Jumping
    // to the clearance in one mile is steeper than the aircraft can fly.
    final double calcAlt = safeAlt;
    final bool changing = rate > 0 && (target - altitude).abs() > 1;
    final double tas = changing ? verticalTas : (cruiseTas > 0 ? cruiseTas : verticalTas);
    double windFeet = changing ? calcAlt : target.toDouble();
    if (floor != null && windFeet < floor) {
      windFeet = floor;
    }
    final int windAltitude = windFeet.round();
    final (double? direction, double? speed) = windAt(point, windAltitude);
    final double? solved = BestCruiseAltitude._groundSpeedKt(
      trueAirspeedKt: tas,
      courseDeg: _courseAt(track.points, mid),
      windFrom: direction,
      windSpeed: speed,
    );
    if (solved == null && strict) {
      return null;
    }
    final double groundSpeed = (solved != null && solved > 0) ? solved : tas;
    if (groundSpeed <= 0) {
      return strict ? null : _LegFly(timeSeconds: time, fuelGal: fuel, endAltitude: altitude);
    }
    final double hours = step / groundSpeed;
    if (changing) {
      final double delta = rate * hours * 60.0;
      if (target > altitude) {
        altitude = math.min(target.toDouble(), altitude + delta);
      } else {
        altitude = math.max(target.toDouble(), altitude - delta);
      }
    }
    time += hours * 3600.0;
    fuel += (burn > 0 ? burn : 0) * hours;
    nm += step;
    samples?.add(FlownSample(nm: nm, altitudeFt: altitude, timeSeconds: time, fuelGal: fuel));
  }
  if (arriveAtEnd && samples != null && samples.isNotEmpty && toNm >= totalNm - 0.05) {
    final FlownSample last = samples.last;
    samples[samples.length - 1] = FlownSample(
      nm: last.nm,
      altitudeFt: endAltitudeFt.toDouble(),
      timeSeconds: last.timeSeconds,
      fuelGal: last.fuelGal,
    );
  }
  return _LegFly(timeSeconds: time, fuelGal: fuel, endAltitude: altitude);
}

List<({double nm, double ft})> _knownTerrain(RouteTrack track, List<double?> terrainFt) {
  final List<({double nm, double ft})> terrain = [];
  for (int index = 0; index < track.points.length && index < terrainFt.length; index++) {
    final double? elevation = terrainFt[index];
    if (elevation == null || !elevation.isFinite) {
      continue;
    }
    terrain.add((nm: track.points[index].nm, ft: elevation));
  }
  return terrain;
}

List<({double nm, double ft})> _terrainFromJson(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  final List<({double nm, double ft})> terrain = [];
  for (final Object? item in raw) {
    if (item is! Map) {
      continue;
    }
    final Map<String, dynamic> sample = Map<String, dynamic>.from(item);
    final Object? nm = sample['nm'];
    final Object? feet = sample['ft'];
    if (nm is num && feet is num && feet.isFinite) {
      terrain.add((nm: nm.toDouble(), ft: feet.toDouble()));
    }
  }
  return terrain;
}

/// Elevation plus 1,000 ft at [nm]. Null when no terrain was sampled nearby.
double? _clearanceFt(List<({double nm, double ft})> terrain, double nm) {
  final double? elevation = _terrainElevation(terrain, nm);
  if (elevation == null) {
    return null;
  }
  return elevation + BestCruiseAltitude.terrainClearanceFt;
}

double? _terrainElevation(List<({double nm, double ft})> terrain, double nm) {
  if (terrain.isEmpty) {
    return null;
  }
  int lo = 0;
  int hi = terrain.length - 1;
  int found = -1;
  while (lo <= hi) {
    final int mid = (lo + hi) >> 1;
    if (terrain[mid].nm <= nm) {
      found = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  final ({double nm, double ft})? before = found >= 0 ? terrain[found] : null;
  final ({double nm, double ft})? after = found >= 0 && terrain[found].nm >= nm
      ? terrain[found]
      : (found + 1 < terrain.length ? terrain[found + 1] : null);
  if (before != null && after != null) {
    final double span = after.nm - before.nm;
    if (span <= 0) {
      return before.ft;
    }
    if (span > 6) {
      if ((nm - before.nm) <= 3) {
        return before.ft;
      }
      if ((after.nm - nm) <= 3) {
        return after.ft;
      }
      return null;
    }
    final double t = (nm - before.nm) / span;
    return before.ft + (after.ft - before.ft) * t;
  }
  final ({double nm, double ft})? nearest = before ?? after;
  if (nearest == null || (nearest.nm - nm).abs() > 6) {
    return null;
  }
  return nearest.ft;
}

/// First point index at or after [nm]. The segment is the previous point to this one.
int _segmentEnd(List<({double nm, LatLng at})> points, double nm) {
  if (nm <= points[1].nm) {
    return 1;
  }
  if (nm >= points.last.nm) {
    return points.length - 1;
  }
  int lo = 1;
  int hi = points.length - 1;
  while (lo < hi) {
    final int mid = (lo + hi) >> 1;
    if (points[mid].nm < nm) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

LatLng _pointAt(List<({double nm, LatLng at})> points, double nm) {
  if (points.isEmpty) {
    return const LatLng(0, 0);
  }
  if (points.length == 1 || nm <= points.first.nm) {
    return points.first.at;
  }
  final int index = _segmentEnd(points, nm);
  final double span = points[index].nm - points[index - 1].nm;
  final double t = span <= 0 ? 0 : (nm - points[index - 1].nm) / span;
  return LatLng(
    points[index - 1].at.latitude + (points[index].at.latitude - points[index - 1].at.latitude) * t,
    points[index - 1].at.longitude + (points[index].at.longitude - points[index - 1].at.longitude) * t,
  );
}

double _courseAt(List<({double nm, LatLng at})> points, double nm) {
  if (points.length < 2) {
    return 0;
  }
  final int index = _segmentEnd(points, nm);
  return GeoCalculations().calculateBearing(points[index - 1].at, points[index].at);
}

/// Magnetic course from the first point to the last. East and west altitudes
/// use this course for the whole route.
double _routeMagneticCourse(
  List<({double nm, LatLng at})> points,
  double Function(double nm)? variationAt,
) {
  if (points.length < 2) {
    return 0;
  }
  final double trueCourse = GeoCalculations().calculateBearing(points.first.at, points.last.at);
  final double variation = variationAt?.call(points.last.nm / 2) ?? 0;
  return GeoCalculations.getMagneticHeading(trueCourse, variation);
}

/// Time and fuel for one leg after a climb profile is applied.
class FlownLeg {
  final double tas;
  final double gph;
  final double altitude;
  final double? timeSeconds;
  final double? fuelGal;
  final double? distanceNm;
  final double? groundSpeed;

  const FlownLeg({
    required this.tas,
    required this.gph,
    required this.altitude,
    this.timeSeconds,
    this.fuelGal,
    this.distanceNm,
    this.groundSpeed,
  });
}

/// One calculated leg and the waypoint row whose Alt column shows it.
class PlanLegTarget {
  final LatLng from;
  final LatLng to;
  final Waypoint waypoint;
  final int? fixIndex;

  /// Altitude the airplane is already at when this leg begins.
  final int fromAltitudeFt;

  const PlanLegTarget({
    required this.from,
    required this.to,
    required this.waypoint,
    required this.fixIndex,
    required this.fromAltitudeFt,
  });
}

/// Altitude, climb, and navigation-log numbers for a plan.
class PlanAltitudes {
  final PlanRoute route;

  PlanAltitudes(this.route);

  /// Altitude for each point [_makePathPoints] already walks, in that order.
  double Function(int leg, int sample, int fullCount, LatLng point) along(List<Destination> path, bool slope) {
    final _PathAltitudes walk = _PathAltitudes(this, path, slope);
    return walk.at;
  }

  List<Waypoint> get _waypoints {
    return [for (int index = 0; index < route.length; index++) route.getWaypointAt(index)];
  }

  ProfileFlight? profileFlight() {
    final CruiseProfile? profile = route.cruiseProfile;
    final List<Destination> destinations = route.getAllDestinations();
    if (profile == null || destinations.length < 2) {
      return null;
    }
    final RouteTrack track = BestCruiseAltitude.buildTrack([
      for (int index = 0; index < destinations.length - 1; index++)
        (from: destinations[index].coordinate, to: destinations[index + 1].coordinate),
    ], spacingNm: BestCruiseAltitude.terrainSpacingNm);
    if (track.points.length < 2 || (track.totalNm - profile.totalNm).abs() > 2) {
      return null;
    }
    return profile.fly(
      track,
      (LatLng point, int altitude) =>
          WindsCache.getWindsAt(point, altitude.toDouble(), route.fore),
    );
  }

  FlownLeg flownLeg(int index, Destination to, bool active) {
    final ({double tas, double gph, double altitude}) numbers = _legNumbers(to);
    final ProfileFlight? flight = route.flight;
    double tas = numbers.tas;
    double gph = numbers.gph;
    double altitude = numbers.altitude;
    if (flight == null || index + 1 >= flight.fixNm.length) {
      return FlownLeg(tas: tas, gph: gph, altitude: altitude);
    }
    double nm0 = flight.fixNm[index];
    double nm1 = flight.fixNm[index + 1];
    if (active) {
      nm0 = flight.track.nearest(Gps.toLatLng(Storage().position), nm0, nm1);
    }
    if (nm0 > nm1) {
      nm0 = nm1;
    }
    final CruiseStep step = flight.profile.stepAt((nm0 + nm1) / 2);
    if (step.ktas > 0) {
      tas = step.ktas;
    }
    if (step.gph > 0) {
      gph = step.gph;
    }
    final bool lastLeg = flight.profile.arriveAtEnd && index + 1 == flight.fixNm.length - 1;
    altitude = flight.reportedAltitudeAt(flight.fixNm[lastLeg ? index : index + 1]);
    final ({double timeSeconds, double fuelGal, double distanceNm}) span = flight.span(nm0, nm1);
    final double? groundSpeed = span.timeSeconds > 0 && span.distanceNm > 0
        ? span.distanceNm / (span.timeSeconds / 3600.0)
        : null;
    return FlownLeg(
      tas: tas,
      gph: gph,
      altitude: altitude,
      timeSeconds: span.timeSeconds,
      fuelGal: span.fuelGal,
      distanceNm: span.distanceNm,
      groundSpeed: groundSpeed,
    );
  }

  bool applyEndpointFieldElevations() {
    if (_waypoints.isEmpty) {
      return false;
    }
    bool changed = _setAirportFieldElevation(_waypoints.first);
    if (_waypoints.length > 1) {
      changed = _setAirportFieldElevation(_waypoints.last) || changed;
    }
    return changed;
  }

  int rowAltitude(Waypoint waypoint, [int? fixIndex]) {
    if (fixIndex == null && _waypoints.isNotEmpty && identical(waypoint, _waypoints.first)) {
      final int? field = Waypoint.airportFieldElevationFt(
        waypoint.planDestination.type,
        waypoint.planDestination.elevation,
      );
      if (field != null) {
        return field;
      }
    }
    final ProfileFlight? flight = route.flight;
    if (fixIndex == null && isArrivalAirport(waypoint)) {
      if (flight != null && flight.fixNm.length >= 2) {
        return flight.reportedAltitudeAt(flight.fixNm[flight.fixNm.length - 2]).round();
      }
    } else if (flight != null) {
      final Destination? destination = _altitudeDestination(waypoint, fixIndex);
      if (destination != null) {
        final double? reached = _reportedAltitude(destination);
        if (reached != null) {
          return reached.round();
        }
      }
      return waypoint.effectiveAltitude(route.altitude, fixIndex);
    }
    if (fixIndex != null || !isArrivalAirport(waypoint)) {
      return waypoint.effectiveAltitude(route.altitude, fixIndex);
    }
    if (waypoint.navAltitudeFt != null) {
      return waypoint.navAltitudeFt!;
    }
    final int? field = Waypoint.airportFieldElevationFt(
      waypoint.planDestination.type,
      waypoint.planDestination.elevation,
    );
    if (waypoint.altitudeFt != null && waypoint.altitudeFt != field) {
      return waypoint.altitudeFt!;
    }
    if (_waypoints.length >= 2) {
      return _waypoints[_waypoints.length - 2].effectiveAltitude(route.altitude);
    }
    return waypoint.effectiveAltitude(route.altitude);
  }

  bool isArrivalAirport(Waypoint waypoint) {
    return _waypoints.length > 1 &&
        identical(waypoint, _waypoints.last) &&
        Waypoint.airportFieldElevationFt(waypoint.planDestination.type, waypoint.planDestination.elevation) != null;
  }

  void setLegAltitude(Waypoint waypoint, int? fixIndex, int value) {
    waypoint.setAltitudeOnly(fixIndex, value);
    if (fixIndex == null) {
      waypoint.navAltitudeFt = value;
    }
    _retargetSpan(waypoint, fixIndex, value);
    route.update();
  }

  void clearLegAltitude(Waypoint waypoint, int? fixIndex) {
    waypoint.clearLegCruise(fixIndex);
    _retargetSpan(waypoint, fixIndex, route.altitude);
    route.update();
  }

  String altitudeSignature() {
    final String legs = _waypoints.map((Waypoint waypoint) {
      final List<int> indexes = {
        ...waypoint.fixAltitudeFt.keys,
        ...waypoint.fixCruiseKtas.keys,
        ...waypoint.fixCruiseGph.keys,
      }.toList()
        ..sort();
      final String fixes = indexes
          .map((int index) =>
              "$index:${waypoint.fixAltitudeFt[index] ?? ""}@${waypoint.fixCruiseKtas[index] ?? ""}/${waypoint.fixCruiseGph[index] ?? ""}")
          .join(",");
      return "${waypoint.altitudeFt ?? ""}:${waypoint.navAltitudeFt ?? ""}@${waypoint.cruiseKtas ?? ""}/${waypoint.cruiseGph ?? ""}[$fixes]";
    }).join(";");
    return "$legs|${route.cruiseProfile?.signature() ?? ""}";
  }

  List<PlanLegTarget> cruiseLegs() {
    final List<Destination> destinations = route.getAllDestinations();
    final Waypoint? current = route.getCurrentWaypoint();
    if (destinations.length < 2 || current == null) {
      return [];
    }
    final Destination active = current.destination;
    final LatLng gps = Gps.toLatLng(Storage().position);
    final List<PlanLegTarget> legs = [];
    for (int index = 0; index < destinations.length - 1; index++) {
      final Destination to = destinations[index + 1];
      final LatLng from = active == to ? gps : destinations[index].coordinate;
      int fromAltitudeFt = _legNumbers(destinations[index]).altitude.round();
      if (index == 0) {
        final int? field = Waypoint.airportFieldElevationFt(
          destinations[index].type,
          destinations[index].elevation,
        );
        if (field != null) {
          fromAltitudeFt = field;
        }
      }
      final PlanLegTarget? target = _targetFor(to, from, fromAltitudeFt);
      if (target != null) {
        legs.add(target);
      }
    }
    return legs;
  }

  static Map<int, int> profileAltitudesForFixes(
    List<String> fixIds,
    List<({String fix, double? altitudeFt})> points,
  ) {
    final Map<String, int> byFix = {};
    for (final ({String fix, double? altitudeFt}) point in points) {
      final double? altitude = point.altitudeFt;
      if (altitude == null) {
        continue;
      }
      byFix[point.fix.trim().toUpperCase()] = altitude.round();
    }
    final Map<int, int> matched = {};
    for (int index = 0; index < fixIds.length; index++) {
      final int? altitude = byFix[fixIds[index].trim().toUpperCase()];
      if (altitude != null) {
        matched[index] = altitude;
      }
    }
    return matched;
  }

  void applyProcedureProfileAltitudes(
    String procedureName,
    List<({String fix, double? altitudeFt})> points,
  ) {
    Waypoint? match;
    for (final Waypoint waypoint in _waypoints.reversed) {
      if (waypoint.planDestination.locationID == procedureName) {
        match = waypoint;
        break;
      }
    }
    if (match == null || match.destinationsOnRoute.isEmpty) {
      return;
    }
    final List<String> fixIds = match.destinationsOnRoute.map((Destination destination) {
      final String name = destination.secondaryName ?? '';
      return name.isNotEmpty ? name : destination.locationID;
    }).toList();
    final Map<int, int> altitudes = profileAltitudesForFixes(fixIds, points);
    if (altitudes.isEmpty) {
      return;
    }
    route.cruiseProfile = null;
    for (final MapEntry<int, int> entry in altitudes.entries) {
      match.setAltitudeOnly(entry.key, entry.value);
    }
    route.update();
  }

  bool _setAirportFieldElevation(Waypoint waypoint) {
    final int? feet = Waypoint.airportFieldElevationFt(
      waypoint.planDestination.type,
      waypoint.planDestination.elevation,
    );
    if (feet == null) {
      return false;
    }
    if (waypoint.altitudeFt == feet &&
        waypoint.navAltitudeFt == null &&
        waypoint.cruiseKtas == null &&
        waypoint.cruiseGph == null) {
      return false;
    }
    waypoint.setAltitudeOnly(null, feet);
    waypoint.navAltitudeFt = null;
    return true;
  }

  void _retargetSpan(Waypoint waypoint, int? fixIndex, int altitudeFt) {
    final ({double fromNm, double toNm})? span = _legSpan(waypoint, fixIndex);
    final CruiseProfile? profile = route.cruiseProfile;
    if (profile == null || span == null) {
      return;
    }
    final CruiseStep previous = profile.stepAt(span.fromNm);
    final double tas = Storage().settings.getTas();
    final double gph = Storage().settings.getFuelBurn();
    route.cruiseProfile = profile.replaceSpan(
      fromNm: span.fromNm,
      toNm: span.toNm,
      altitudeFt: altitudeFt,
      ktas: tas > 0 ? tas : previous.ktas,
      gph: gph > 0 ? gph : previous.gph,
    );
  }

  ({double fromNm, double toNm})? _legSpan(Waypoint waypoint, int? fixIndex) {
    final ProfileFlight? flight = route.flight;
    final List<Destination> destinations = route.getAllDestinations();
    if (flight == null || destinations.length < 2) {
      return null;
    }
    for (int index = 0; index < destinations.length - 1; index++) {
      if (index + 1 >= flight.fixNm.length) {
        break;
      }
      final ({Waypoint waypoint, int? fixIndex})? owner = _owner(destinations[index + 1]);
      if (owner == null || !identical(owner.waypoint, waypoint) || owner.fixIndex != fixIndex) {
        continue;
      }
      return (fromNm: flight.fixNm[index], toNm: flight.fixNm[index + 1]);
    }
    return null;
  }

  ({Waypoint waypoint, int? fixIndex})? _owner(Destination to) {
    for (final Waypoint waypoint in _waypoints) {
      if (waypoint.destinationsOnRoute.isNotEmpty) {
        final int index = waypoint.destinationsOnRoute.indexOf(to);
        if (index >= 0) {
          return (waypoint: waypoint, fixIndex: index);
        }
      } else if (identical(waypoint.planDestination, to)) {
        return (waypoint: waypoint, fixIndex: null);
      }
    }
    return null;
  }

  ({double tas, double gph, double altitude}) _legNumbers(Destination to) {
    final double planTas = Storage().settings.getTas();
    final double planGph = Storage().settings.getFuelBurn();
    final ({Waypoint waypoint, int? fixIndex})? owner = _owner(to);
    if (owner == null) {
      return (tas: planTas, gph: planGph, altitude: route.altitude.toDouble());
    }
    final int? index = owner.fixIndex;
    final double? legTas = index == null ? owner.waypoint.cruiseKtas : owner.waypoint.fixCruiseKtas[index];
    final double? legGph = index == null ? owner.waypoint.cruiseGph : owner.waypoint.fixCruiseGph[index];
    final int feet = index == null
        ? (owner.waypoint.navAltitudeFt ?? owner.waypoint.effectiveAltitude(route.altitude))
        : owner.waypoint.effectiveAltitude(route.altitude, index);
    return (
      tas: legTas != null && legTas > 0 ? legTas : planTas,
      gph: legGph != null && legGph > 0 ? legGph : planGph,
      altitude: feet.toDouble(),
    );
  }

  PlanLegTarget? _targetFor(Destination to, LatLng from, int fromAltitudeFt) {
    final ({Waypoint waypoint, int? fixIndex})? owner = _owner(to);
    if (owner == null) {
      return null;
    }
    return PlanLegTarget(
      from: from,
      to: to.coordinate,
      waypoint: owner.waypoint,
      fixIndex: owner.fixIndex,
      fromAltitudeFt: fromAltitudeFt,
    );
  }

  double _storedAltitude(Destination destination) {
    final double? reached = _flightAltitude(destination, (ProfileFlight flight, double nm) => flight.altitudeAt(nm));
    if (reached != null) {
      return reached;
    }
    final ({Waypoint waypoint, int? fixIndex})? owner = _owner(destination);
    if (owner == null) {
      return destination.calculations?.altitude ?? route.altitude.toDouble();
    }
    return owner.waypoint.effectiveAltitude(route.altitude, owner.fixIndex).toDouble();
  }

  int _fixIndex(Destination destination) {
    final int exact = route.getAllDestinations().indexOf(destination);
    if (exact >= 0) {
      return exact;
    }
    return route.getAllDestinations().indexWhere(
      (Destination other) => other.coordinate == destination.coordinate,
    );
  }

  double? _flightAltitude(Destination destination, double Function(ProfileFlight flight, double nm) read) {
    final ProfileFlight? flight = route.flight;
    if (flight == null) {
      return null;
    }
    final int index = _fixIndex(destination);
    if (index < 0 || index >= flight.fixNm.length) {
      return null;
    }
    return read(flight, flight.fixNm[index]);
  }

  double? _reportedAltitude(Destination destination) {
    return _flightAltitude(destination, (ProfileFlight flight, double nm) => flight.reportedAltitudeAt(nm));
  }

  Destination? _altitudeDestination(Waypoint waypoint, int? fixIndex) {
    if (fixIndex != null) {
      if (fixIndex < 0 || fixIndex >= waypoint.destinationsOnRoute.length) {
        return null;
      }
      return waypoint.destinationsOnRoute[fixIndex];
    }
    if (waypoint.destinationsOnRoute.isNotEmpty) {
      return null;
    }
    return waypoint.planDestination;
  }

}

/// Altitudes for the points [PlanRoute] builds with one pass of [GeoCalculations.findPoints].
class _PathAltitudes {
  final PlanAltitudes altitudes;
  final List<Destination> path;
  final bool slope;
  final bool climbed;
  bool useProfile = false;
  double nm = 0;
  LatLng? previous;
  final GeoCalculations geo = GeoCalculations();

  _PathAltitudes(this.altitudes, this.path, this.slope) : climbed = altitudes.route.flight != null {
    final ProfileFlight? flight = altitudes.route.flight;
    if (flight == null || path.isEmpty) {
      return;
    }
    final int start = altitudes._fixIndex(path[0]);
    if (start >= 0 && start < flight.fixNm.length) {
      nm = flight.fixNm[start];
      useProfile = true;
    }
  }

  double at(int leg, int sample, int fullCount, LatLng point) {
    if (useProfile) {
      if (previous != null) {
        nm += geo.calculateDistance(previous!, point);
      }
      previous = point;
      return altitudes.route.flight!.altitudeAt(nm);
    }
    final double storedTo = altitudes._storedAltitude(path[leg + 1]);
    final double toAltitude = (slope || climbed)
        ? storedTo
        : (path[leg + 1].calculations?.altitude ?? storedTo);
    if ((!slope && !climbed) || fullCount <= 1) {
      return toAltitude;
    }
    final double fromAltitude = (slope || climbed) ? altitudes._storedAltitude(path[leg]) : toAltitude;
    final double t = sample / (fullCount - 1);
    return fromAltitude + (toAltitude - fromAltitude) * t;
  }
}
