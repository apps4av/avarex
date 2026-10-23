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

/// Picks cruise altitudes for the shortest time to the destination.
///
/// [choose] walks the whole route. About every [holdNm] miles it picks the
/// fastest cruise altitude that is at least [terrainClearanceFt] above the
/// terrain in the next [holdNm] miles, then holds that altitude. Climb and
/// descent use the aircraft climb speed and climb rate. Time and fuel while
/// the altitude is changing use that climb speed.
///
/// [search] scores one altitude for a whole leg. A climb starts at
/// [fromAltitudeFt], at [climbSpeedFraction] of cruise speed. Climb rate is
/// [climbRateSeaLevelFpm] near the surface and [climbRateTopFpm] at the top of
/// the cruise table. If the leg is shorter than that climb, the rest of the
/// climb is a circle at climb speed. A descent in [search] does not add time.
class BestCruiseAltitude {
  BestCruiseAltitude._();

  /// Miles between altitude changes. The altitude also has to clear the terrain this far ahead.
  static const double holdNm = 50;

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

  /// Cruise altitudes along [track]. A new altitude is chosen every [holdNm] miles.
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
  final double total = track.totalNm;

  while (pos < total - 0.05) {
    final double windowEnd = math.min(pos + BestCruiseAltitude.holdNm, total);
    if (windowEnd <= pos + 0.01) {
      break;
    }
    final int floor = _terrainFloor(track, terrainFt, pos, windowEnd);
    final List<int> candidates = _cruiseCandidates(sorted, floor, altitude, lowest);
    if (candidates.isEmpty) {
      break;
    }
    CruiseStep? best;
    double? bestTime;
    double bestEnd = altitude;
    for (final int candidate in candidates) {
      final CruiseResult cruise = cruiseAt(candidate);
      if (cruise.ktas <= 0 || !cruise.ktas.isFinite) {
        continue;
      }
      final _LegFly? flown = _integrate(
        track: track,
        fromNm: pos,
        toNm: windowEnd,
        startAlt: altitude,
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
    if (best == null) {
      break;
    }
    if (best.altitudeFt < floor) {
      terrainShort = true;
    }
    if (steps.isEmpty || steps.last.altitudeFt != best.altitudeFt) {
      steps.add(best);
    }
    altitude = bestEnd;
    pos = windowEnd;
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
    bool finish = false;
    if (arriveAtEnd && (safeAlt - endAltitudeFt).abs() > 1 && rate > 0 && verticalTas > 0) {
      final (double? climbDirection, double? climbSpeed) = windAt(point, safeAlt.round());
      final double? climbGs = BestCruiseAltitude._groundSpeedKt(
        trueAirspeedKt: verticalTas,
        courseDeg: _courseAt(track.points, mid),
        windFrom: climbDirection,
        windSpeed: climbSpeed,
      );
      final double speed = (climbGs != null && climbGs > 0) ? climbGs : verticalTas;
      final double needNm = (safeAlt - endAltitudeFt).abs() / rate / 60.0 * speed;
      // Start within this step so the arrival is at the field, not still descending.
      if (totalNm - nm <= needNm + step) {
        finish = true;
      }
    }

    final bool landing = arriveAtEnd && (nm + step) >= totalNm - 1e-6;
    int target = finish ? endAltitudeFt : cruiseTarget;
    if (floor != null && !landing && target < floor) {
      target = floor.ceil();
    }
    // Wind, time, and fuel use an altitude at least 1,000 ft above the terrain here.
    final double calcAlt = safeAlt;
    final bool changing = rate > 0 && (target - calcAlt).abs() > 1;
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
    if (floor != null && altitude < floor) {
      altitude = floor;
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
  ({double nm, double ft})? before;
  ({double nm, double ft})? after;
  for (final ({double nm, double ft}) sample in terrain) {
    if (sample.nm <= nm) {
      before = sample;
    }
    if (sample.nm >= nm) {
      after ??= sample;
    }
  }
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

LatLng _pointAt(List<({double nm, LatLng at})> points, double nm) {
  if (points.isEmpty) {
    return const LatLng(0, 0);
  }
  if (nm <= points.first.nm) {
    return points.first.at;
  }
  for (int index = 1; index < points.length; index++) {
    if (nm <= points[index].nm) {
      final double span = points[index].nm - points[index - 1].nm;
      final double t = span <= 0 ? 0 : (nm - points[index - 1].nm) / span;
      return LatLng(
        points[index - 1].at.latitude + (points[index].at.latitude - points[index - 1].at.latitude) * t,
        points[index - 1].at.longitude + (points[index].at.longitude - points[index - 1].at.longitude) * t,
      );
    }
  }
  return points.last.at;
}

double _courseAt(List<({double nm, LatLng at})> points, double nm) {
  if (points.length < 2) {
    return 0;
  }
  final GeoCalculations geo = GeoCalculations();
  for (int index = 1; index < points.length; index++) {
    if (nm <= points[index].nm) {
      return geo.calculateBearing(points[index - 1].at, points[index].at);
    }
  }
  return geo.calculateBearing(points[points.length - 2].at, points.last.at);
}
