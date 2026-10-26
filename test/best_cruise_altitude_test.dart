import 'package:avaremp/aircraft/aircraft_performance.dart';
import 'package:avaremp/plan/best_cruise_altitude.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/unit_conversion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  setUp(() {
    Storage().units = UnitConversion("Nautical");
  });

  test("steps every 1000 ft inside the cruise table", () {
    expect(
      BestCruiseAltitude.altitudesFt([4000, 6000, 8000, 10000, 12000]),
      [4000, 5000, 6000, 7000, 8000, 9000, 10000, 11000, 12000],
    );
    expect(
      BestCruiseAltitude.altitudesFt([2500, 11500]),
      [2500, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000, 11000, 11500],
    );
    expect(BestCruiseAltitude.altitudesFt([4500]), [4500]);
    expect(BestCruiseAltitude.altitudesFt([]), isEmpty);
  });

  test("C172 cruise search stays inside the POH table", () {
    final List<int> altitudes =
        BestCruiseAltitude.altitudesFor(CommonAircraftData.cessna172sp);
    expect(altitudes.first, 4000);
    expect(altitudes.last, 12000);
    expect(altitudes, contains(5000));
    expect(altitudes, isNot(contains(3000)));
    expect(altitudes, isNot(contains(13000)));
    final CruiseResult between = CommonAircraftData.cessna172sp.getCruisePerformance(5000, 65, 0);
    expect(between.ktas, inInclusiveRange(100, 130));
    expect(between.gph, greaterThan(0));
  });

  test("tailwind at a slower cruise speed beats a headwind", () {
    const LatLng from = LatLng(42, -71);
    const LatLng to = LatLng(42, -70);
    final BestCruiseAltitudeResult result = BestCruiseAltitude.search(
      legs: [(from: from, to: to)],
      altitudesFt: [4000, 8000],
      minAltitudeFt: 0,
      cruiseAt: (int altitude) => CruiseResult(
        ktas: altitude == 4000 ? 130 : 110,
        gph: 8,
      ),
      // Eastbound. Wind from 090 is a headwind; wind from 270 is a tailwind.
      windAt: (LatLng point, int altitude) =>
          altitude == 4000 ? (90.0, 30.0) : (270.0, 40.0),
    );
    expect(result.usedWind, isTrue);
    expect(result.best!.altitudeFt, 8000);
    expect(result.best!.ktas, 110);
  });

  test("calm wind keeps the faster cruise speed", () {
    final BestCruiseAltitudeResult result = BestCruiseAltitude.search(
      legs: [(from: const LatLng(42, -71), to: const LatLng(42, -70))],
      altitudesFt: [4000, 8000],
      minAltitudeFt: 0,
      cruiseAt: (int altitude) => CruiseResult(
        ktas: altitude == 4000 ? 130 : 100,
        gph: 8,
      ),
      windAt: (LatLng point, int altitude) => (0.0, 0.0),
    );
    expect(result.best!.altitudeFt, 4000);
  });

  test("missing winds aloft still returns the fastest cruise speed", () {
    final BestCruiseAltitudeResult result = BestCruiseAltitude.search(
      legs: [(from: const LatLng(42, -71), to: const LatLng(42, -70))],
      altitudesFt: [6000, 10000],
      minAltitudeFt: 0,
      cruiseAt: (int altitude) => CruiseResult(
        ktas: altitude == 10000 ? 140 : 100,
        gph: 8,
      ),
      windAt: (LatLng point, int altitude) => (null, null),
    );
    expect(result.usedWind, isFalse);
    expect(result.best!.altitudeFt, 10000);
  });

  test("altitudes below terrain are not chosen", () {
    final BestCruiseAltitudeResult result = BestCruiseAltitude.search(
      legs: [(from: const LatLng(42, -71), to: const LatLng(42, -70))],
      altitudesFt: [4000, 8000],
      minAltitudeFt: 6000,
      cruiseAt: (int altitude) => CruiseResult(
        ktas: altitude == 4000 ? 200 : 100,
        gph: 8,
      ),
      windAt: (LatLng point, int altitude) => (0.0, 0.0),
    );
    expect(result.excludedForTerrain, isTrue);
    expect(result.terrainBlockedAll, isFalse);
    expect(result.best!.altitudeFt, 8000);
  });

  test("reports when terrain is above the whole cruise table", () {
    final BestCruiseAltitudeResult result = BestCruiseAltitude.search(
      legs: [(from: const LatLng(42, -71), to: const LatLng(42, -70))],
      altitudesFt: [4000, 8000],
      minAltitudeFt: 20000,
      cruiseAt: (int altitude) => CruiseResult(ktas: 120, gph: 8),
      windAt: (LatLng point, int altitude) => (0.0, 0.0),
    );
    expect(result.terrainBlockedAll, isTrue);
    expect(result.best, isNull);
  });

  test("rejects an altitude the wind triangle cannot fly", () {
    final BestCruiseAltitudeResult result = BestCruiseAltitude.search(
      legs: [(from: const LatLng(42, -71), to: const LatLng(42, -70))],
      altitudesFt: [6000],
      minAltitudeFt: 0,
      cruiseAt: (int altitude) => CruiseResult(ktas: 40, gph: 8),
      windAt: (LatLng point, int altitude) => (90.0, 80.0),
    );
    expect(result.best, isNull);
    expect(result.usedWind, isTrue);
  });

  test("equal time keeps the lower altitude", () {
    final CruiseAltitudeSample? best = BestCruiseAltitude.fastest([
      const CruiseAltitudeSample(
          altitudeFt: 8000, ktas: 120, gph: 8, timeSeconds: 3600),
      const CruiseAltitudeSample(
          altitudeFt: 6000, ktas: 120, gph: 9, timeSeconds: 3600),
    ]);
    expect(best!.altitudeFt, 6000);
  });

  test("formats enroute time like the navigation log", () {
    expect(BestCruiseAltitude.hoursMinutes(3660), "1:01");
  });

  test("opposite legs pick opposite altitudes in the same wind", () {
    CruiseResult cruiseAt(int altitude) => CruiseResult(
          ktas: altitude == 4000 ? 120 : 120,
          gph: 8,
        );
    (double?, double?) windAt(LatLng point, int altitude) =>
        altitude == 4000 ? (90.0, 40.0) : (270.0, 40.0);

    final BestCruiseAltitudeResult east = BestCruiseAltitude.search(
      legs: [(from: const LatLng(42, -71), to: const LatLng(42, -70))],
      altitudesFt: [4000, 8000],
      minAltitudeFt: 0,
      cruiseAt: cruiseAt,
      windAt: windAt,
    );
    final BestCruiseAltitudeResult west = BestCruiseAltitude.search(
      legs: [(from: const LatLng(42, -70), to: const LatLng(42, -71))],
      altitudesFt: [4000, 8000],
      minAltitudeFt: 0,
      cruiseAt: cruiseAt,
      windAt: windAt,
    );
    expect(east.best!.altitudeFt, 8000);
    expect(west.best!.altitudeFt, 4000);
  });

  test("one mile leg stays at the altitude it already has", () {
    const LatLng from = LatLng(42, -71);
    final LatLng to = LatLng(42 + 1 / 60, -71);
    final BestCruiseAltitudeResult result = BestCruiseAltitude.search(
      legs: [(from: from, to: to)],
      altitudesFt: [4000, 8000, 12000],
      minAltitudeFt: 1000,
      fromAltitudeFt: 2000,
      cruiseAt: (int altitude) => CruiseResult(
        ktas: altitude >= 12000 ? 130 : 110,
        gph: 8,
      ),
      // Northbound. Wind from 180 is a tailwind. Wind from 0 is a headwind.
      windAt: (LatLng point, int altitude) =>
          altitude >= 8000 ? (180.0, 50.0) : (0.0, 40.0),
    );
    expect(result.best!.altitudeFt, 2000);
  });

  test("a saved climb rate replaces the default climb", () {
    const LatLng from = LatLng(42, -71);
    final LatLng to = LatLng(42 + 1 / 60, -71);
    final double? slow = BestCruiseAltitude.timeToFly(
      from: from,
      to: to,
      altitudeFt: 6000,
      fromAltitudeFt: 2000,
      cruiseKtas: 120,
      topAltitudeFt: 12000,
      windAt: (LatLng point, int altitude) => (null, null),
      climbTrueAirspeedKt: 80,
      climbRateConstantFpm: 200,
    );
    final double? fast = BestCruiseAltitude.timeToFly(
      from: from,
      to: to,
      altitudeFt: 6000,
      fromAltitudeFt: 2000,
      cruiseKtas: 120,
      topAltitudeFt: 12000,
      windAt: (LatLng point, int altitude) => (null, null),
      climbTrueAirspeedKt: 80,
      climbRateConstantFpm: 2000,
    );
    expect(slow!, greaterThan(fast! * 3));
  });

  test("climbing to 12000 on a one mile leg is a long circle", () {
    const LatLng from = LatLng(42, -71);
    final LatLng to = LatLng(42 + 1 / 60, -71);
    final double? high = BestCruiseAltitude.timeToFly(
      from: from,
      to: to,
      altitudeFt: 12000,
      fromAltitudeFt: 2000,
      cruiseKtas: 120,
      topAltitudeFt: 12000,
      windAt: (LatLng point, int altitude) => (null, null),
    );
    final double? low = BestCruiseAltitude.timeToFly(
      from: from,
      to: to,
      altitudeFt: 2000,
      fromAltitudeFt: 2000,
      cruiseKtas: 120,
      topAltitudeFt: 12000,
      windAt: (LatLng point, int altitude) => (null, null),
    );
    expect(high!, greaterThan(15 * 60));
    expect(low!, lessThan(2 * 60));
  });

  test("a long leg still climbs when the higher wind is worth it", () {
    const LatLng from = LatLng(42, -71);
    final LatLng to = LatLng(42 + 4, -71);
    final BestCruiseAltitudeResult result = BestCruiseAltitude.search(
      legs: [(from: from, to: to)],
      altitudesFt: [4000, 8000, 12000],
      minAltitudeFt: 1000,
      fromAltitudeFt: 2000,
      cruiseAt: (int altitude) => CruiseResult(ktas: 120, gph: 8),
      windAt: (LatLng point, int altitude) =>
          altitude >= 8000 ? (180.0, 50.0) : (0.0, 40.0),
    );
    expect(result.best!.altitudeFt, 8000);
  });

  test("a short leg stays at the lowest altitude that clears terrain", () {
    const LatLng from = LatLng(42, -71);
    final LatLng to = LatLng(42 + 1 / 60, -71);
    final BestCruiseAltitudeResult result = BestCruiseAltitude.search(
      legs: [(from: from, to: to)],
      altitudesFt: [4000, 8000, 12000],
      minAltitudeFt: 6000,
      fromAltitudeFt: 2000,
      cruiseAt: (int altitude) => CruiseResult(
        ktas: altitude >= 12000 ? 140 : 110,
        gph: 8,
      ),
      windAt: (LatLng point, int altitude) =>
          altitude >= 12000 ? (180.0, 60.0) : (0.0, 0.0),
    );
    expect(result.best!.altitudeFt, 8000);
  });

  RouteTrack northbound(double miles) {
    return BestCruiseAltitude.buildTrack([
      (from: const LatLng(0, 0), to: LatLng(miles / 60.0, 0)),
    ]);
  }

  List<double?> flat(RouteTrack track, {double atNm = -1, double elevation = 0}) {
    return [
      for (final ({double nm, LatLng at}) point in track.points)
        (atNm >= 0 && (point.nm - atNm).abs() <= 5) ? elevation : 0.0,
    ];
  }

  test("altitude changes wait 50 miles and follow the wind", () {
    final RouteTrack track = northbound(200);
    final RouteCruiseResult result = BestCruiseAltitude.choose(
      track: track,
      terrainFt: flat(track),
      altitudesFt: [4000, 8000],
      startAltitudeFt: 0,
      endAltitudeFt: 0,
      arriveAtEnd: false,
      climbTrueAirspeedKt: 80,
      climbRateConstantFpm: 1000,
      cruiseAt: (int altitude) => CruiseResult(ktas: 100, gph: 8),
      // Northbound. The higher tailwind is only on the last 40 miles, so the
      // climb waits until that part is what remains.
      windAt: (LatLng point, int altitude) {
        final double miles = point.latitude * 60;
        if (miles < 160) {
          return altitude <= 4000 ? (180.0, 40.0) : (0.0, 40.0);
        }
        return altitude >= 8000 ? (180.0, 40.0) : (0.0, 40.0);
      },
    );
    final List<CruiseStep> steps = result.profile!.steps;
    expect(steps.first.altitudeFt, 4000);
    expect(steps[1].altitudeFt, 8000);
    expect(steps[1].startNm, greaterThanOrEqualTo(50));
    for (int index = 1; index < steps.length; index++) {
      expect(steps[index].startNm - steps[index - 1].startNm, greaterThanOrEqualTo(50));
    }
  });

  test("a long route still picks the faster altitude", () {
    final RouteTrack track = BestCruiseAltitude.buildTrack([
      (from: const LatLng(0, 0), to: const LatLng(1600 / 60.0, 0)),
    ], spacingNm: 1);
    final Stopwatch watch = Stopwatch()..start();
    final RouteCruiseResult result = BestCruiseAltitude.choose(
      track: track,
      terrainFt: flat(track),
      altitudesFt: [4000, 8000],
      startAltitudeFt: 0,
      endAltitudeFt: 0,
      arriveAtEnd: true,
      climbTrueAirspeedKt: 90,
      climbRateConstantFpm: 500,
      cruiseAt: (int altitude) => CruiseResult(ktas: 120, gph: 8),
      windAt: (LatLng point, int altitude) =>
          altitude >= 8000 ? (180.0, 30.0) : (0.0, 30.0),
    );
    watch.stop();
    expect(result.profile!.steps.first.altitudeFt, 8000);
    expect(watch.elapsedMilliseconds, lessThan(1500));
  });

  test("a climb starts now when the higher altitude is faster for the whole route", () {
    final RouteTrack track = northbound(200);
    final RouteCruiseResult result = BestCruiseAltitude.choose(
      track: track,
      terrainFt: flat(track),
      altitudesFt: [4000, 8000],
      startAltitudeFt: 0,
      endAltitudeFt: 0,
      arriveAtEnd: false,
      climbTrueAirspeedKt: 70,
      climbRateConstantFpm: 80,
      cruiseAt: (int altitude) => CruiseResult(ktas: 100, gph: 8),
      // Tailwind only at 8,000 ft. The climb is slow enough that the first
      // 50 miles are spent climbing, and the tailwind is what pays for it.
      windAt: (LatLng point, int altitude) =>
          altitude >= 8000 ? (180.0, 40.0) : (0.0, 40.0),
    );
    final List<CruiseStep> steps = result.profile!.steps;
    expect(steps.single.altitudeFt, 8000);
    expect(steps.single.startNm, 0);
    final ProfileFlight flight = result.profile!.fly(
      track,
      (LatLng point, int altitude) => altitude >= 8000 ? (180.0, 40.0) : (0.0, 40.0),
    );
    expect(flight.altitudeAt(15), greaterThan(500));
    expect(flight.altitudeAt(15), lessThan(7000));
    expect(flight.altitudeAt(track.totalNm), greaterThan(7000));
  });

  test("a one mile leg climbs at the aircraft rate", () {
    const LatLng kbos = LatLng(42.3629444444444, -71.0063888888889);
    const LatLng bos = LatLng(42.35745, -70.9895483333333);
    final RouteTrack track = BestCruiseAltitude.buildTrack([
      (from: kbos, to: bos),
      (from: bos, to: const LatLng(40.0, -74.0)),
    ], spacingNm: 1);
    expect(track.legEndNm.first, lessThan(1.2));
    final List<double?> terrain = List<double?>.filled(track.points.length, 38.0);
    final RouteCruiseResult result = BestCruiseAltitude.choose(
      track: track,
      terrainFt: terrain,
      altitudesFt: [9000],
      startAltitudeFt: 19,
      endAltitudeFt: 19,
      arriveAtEnd: true,
      climbTrueAirspeedKt: 80,
      climbRateConstantFpm: 600,
      cruiseAt: (int altitude) => CruiseResult(ktas: 120, gph: 8),
      windAt: (LatLng point, int altitude) => (0.0, 0.0),
    );
    final ProfileFlight flight = result.profile!.fly(
      track,
      (LatLng point, int altitude) => (0.0, 0.0),
    );
    expect(result.profile!.steps.first.altitudeFt, 9000);
    // 600 ft/min at 80 kt is 450 ft per mile. The clearance floor is about
    // 1,038 ft, and the leg is shorter than a mile.
    final double atBos = flight.altitudeAt(track.legEndNm.first);
    expect(atBos, greaterThan(300));
    expect(atBos, lessThan(550));
    expect(flight.altitudeAt(40), greaterThan(8000));
  });

  test("east is an odd thousand and west is an even thousand", () {
    expect(BestCruiseAltitude.matchesCourse(5000, 90), isTrue);
    expect(BestCruiseAltitude.matchesCourse(9000, 0), isTrue);
    expect(BestCruiseAltitude.matchesCourse(4000, 90), isFalse);
    expect(BestCruiseAltitude.matchesCourse(8000, 179), isFalse);
    expect(BestCruiseAltitude.matchesCourse(4500, 90), isFalse);
    expect(BestCruiseAltitude.matchesCourse(4000, 180), isTrue);
    expect(BestCruiseAltitude.matchesCourse(8000, 270), isTrue);
    expect(BestCruiseAltitude.matchesCourse(9000, 270), isFalse);
    expect(BestCruiseAltitude.matchesCourse(5500, 180), isFalse);
  });

  test("an east course does not cruise at an even thousand", () {
    final RouteTrack track = northbound(80);
    final RouteCruiseResult result = BestCruiseAltitude.choose(
      track: track,
      terrainFt: flat(track),
      altitudesFt: [4000, 5000, 6000, 8000, 9000],
      startAltitudeFt: 0,
      endAltitudeFt: 0,
      arriveAtEnd: false,
      climbTrueAirspeedKt: 90,
      climbRateConstantFpm: 700,
      cruiseAt: (int altitude) => CruiseResult(ktas: 120, gph: 8),
      // 8,000 has the strongest tailwind. East still uses 9,000.
      windAt: (LatLng point, int altitude) {
        if (altitude == 8000) return (180.0, 50.0);
        if (altitude == 9000) return (180.0, 20.0);
        return (0.0, 0.0);
      },
    );
    expect(result.profile!.steps.first.altitudeFt, 9000);
  });

  test("a west course does not cruise at an odd thousand", () {
    final RouteTrack track = BestCruiseAltitude.buildTrack([
      (from: const LatLng(80 / 60.0, 0), to: const LatLng(0, 0)),
    ]);
    final RouteCruiseResult result = BestCruiseAltitude.choose(
      track: track,
      terrainFt: flat(track),
      altitudesFt: [4000, 5000, 6000, 8000, 9000],
      startAltitudeFt: 0,
      endAltitudeFt: 0,
      arriveAtEnd: false,
      climbTrueAirspeedKt: 90,
      climbRateConstantFpm: 700,
      cruiseAt: (int altitude) => CruiseResult(ktas: 120, gph: 8),
      windAt: (LatLng point, int altitude) {
        if (altitude == 9000) return (0.0, 50.0);
        if (altitude == 8000) return (0.0, 20.0);
        return (0.0, 0.0);
      },
    );
    expect(result.profile!.steps.first.altitudeFt, 8000);
  });

  test("east and west follow the course from the start to the end", () {
    // Ten miles west, then 80 miles east. The first leg is west. The course
    // from start to end is east, so 8,000 is not used.
    const double lat = 42;
    const double nmToDeg = 1 / (60 * 0.7431);
    const LatLng start = LatLng(lat, -71);
    final LatLng west = LatLng(lat, -71 - 10 * nmToDeg);
    final LatLng end = LatLng(lat, -71 - 10 * nmToDeg + 80 * nmToDeg);
    final RouteTrack track = BestCruiseAltitude.buildTrack([
      (from: start, to: west),
      (from: west, to: end),
    ]);
    final RouteCruiseResult result = BestCruiseAltitude.choose(
      track: track,
      terrainFt: flat(track),
      altitudesFt: [4000, 5000, 6000, 8000, 9000],
      startAltitudeFt: 0,
      endAltitudeFt: 0,
      arriveAtEnd: false,
      climbTrueAirspeedKt: 90,
      climbRateConstantFpm: 700,
      cruiseAt: (int altitude) => CruiseResult(ktas: 120, gph: 8),
      windAt: (LatLng point, int altitude) {
        if (altitude == 8000) return (270.0, 50.0);
        if (altitude == 9000) return (270.0, 20.0);
        return (0.0, 0.0);
      },
    );
    final List<CruiseStep> steps = result.profile!.steps;
    expect(steps.first.altitudeFt, 9000);
    expect(steps.every((CruiseStep step) => (step.altitudeFt ~/ 1000).isOdd), isTrue);
  });

  test("a descent can begin 20 miles after the last altitude", () {
    final RouteTrack track = northbound(180);
    final RouteCruiseResult result = BestCruiseAltitude.choose(
      track: track,
      terrainFt: flat(track),
      altitudesFt: [4000, 8000],
      startAltitudeFt: 0,
      endAltitudeFt: 0,
      arriveAtEnd: false,
      climbTrueAirspeedKt: 80,
      climbRateConstantFpm: 1000,
      cruiseAt: (int altitude) => CruiseResult(ktas: 100, gph: 8),
      // Northbound. 8,000 ft is faster until 140 miles, then 4,000 ft is.
      windAt: (LatLng point, int altitude) {
        final double miles = point.latitude * 60;
        if (miles < 140) {
          return altitude >= 8000 ? (180.0, 40.0) : (0.0, 40.0);
        }
        return altitude <= 4000 ? (180.0, 40.0) : (0.0, 40.0);
      },
    );
    final List<CruiseStep> steps = result.profile!.steps;
    expect(steps.first.altitudeFt, 8000);
    expect(steps.first.startNm, 0);
    final CruiseStep down = steps[1];
    expect(down.altitudeFt, 4000);
    expect(down.startNm, greaterThanOrEqualTo(20));
    expect(down.startNm, greaterThanOrEqualTo(100));
    expect(down.startNm, lessThanOrEqualTo(160));
  });

  test("the first 50 miles clears terrain that far ahead", () {
    final RouteTrack track = northbound(100);
    final RouteCruiseResult blocked = BestCruiseAltitude.choose(
      track: track,
      terrainFt: flat(track, atNm: 30, elevation: 5000),
      altitudesFt: [4000, 8000],
      startAltitudeFt: 0,
      endAltitudeFt: 0,
      arriveAtEnd: false,
      climbTrueAirspeedKt: 80,
      climbRateConstantFpm: 1000,
      cruiseAt: (int altitude) => CruiseResult(ktas: 100, gph: 8),
      windAt: (LatLng point, int altitude) =>
          altitude <= 4000 ? (180.0, 40.0) : (0.0, 40.0),
    );
    expect(blocked.profile!.steps.first.altitudeFt, 8000);

    final RouteCruiseResult later = BestCruiseAltitude.choose(
      track: track,
      terrainFt: flat(track, atNm: 70, elevation: 5000),
      altitudesFt: [4000, 8000],
      startAltitudeFt: 0,
      endAltitudeFt: 0,
      arriveAtEnd: false,
      climbTrueAirspeedKt: 80,
      climbRateConstantFpm: 1000,
      cruiseAt: (int altitude) => CruiseResult(ktas: 100, gph: 8),
      windAt: (LatLng point, int altitude) =>
          altitude <= 4000 ? (180.0, 40.0) : (0.0, 40.0),
    );
    expect(later.profile!.steps.first.altitudeFt, 4000);
    expect(later.profile!.stepAt(70).altitudeFt, 8000);
  });

  test("a route shorter than 50 miles is one altitude", () {
    final RouteTrack track = northbound(30);
    final RouteCruiseResult result = BestCruiseAltitude.choose(
      track: track,
      terrainFt: flat(track),
      altitudesFt: [4000, 8000],
      startAltitudeFt: 0,
      endAltitudeFt: 0,
      arriveAtEnd: false,
      climbTrueAirspeedKt: 80,
      climbRateConstantFpm: 1000,
      cruiseAt: (int altitude) => CruiseResult(ktas: 100, gph: 8),
      windAt: (LatLng point, int altitude) {
        final double miles = point.latitude * 60;
        if (miles < 10) {
          return altitude <= 4000 ? (180.0, 50.0) : (0.0, 40.0);
        }
        return altitude >= 8000 ? (180.0, 50.0) : (0.0, 40.0);
      },
    );
    expect(result.profile!.steps.length, 1);
  });

  test("the arrival descent uses climb speed for time and fuel", () {
    final RouteTrack track = northbound(100);
    ProfileFlight fly(double climbTas) {
      return CruiseProfile(
        steps: [
          CruiseStep(startNm: 0, altitudeFt: 8000, ktas: 120, gph: 8),
        ],
        climbTasKt: climbTas,
        climbRateFpm: 1000,
        topAltitudeFt: 12000,
        startAltitudeFt: 0,
        endAltitudeFt: 0,
        arriveAtEnd: true,
        totalNm: track.totalNm,
      ).fly(track, (LatLng point, int altitude) => (0.0, 0.0));
    }

    final ProfileFlight slow = fly(60);
    final ProfileFlight fast = fly(120);
    expect(slow.timeAt(track.totalNm), greaterThan(fast.timeAt(track.totalNm)));
    expect(slow.fuelAt(track.totalNm), greaterThan(fast.fuelAt(track.totalNm)));
    expect(slow.altitudeAt(track.totalNm), lessThan(500));
    expect(slow.altitudeAt(40), greaterThan(7000));
    expect(slow.timeAt(track.totalNm), greaterThan(track.totalNm / 120 * 3600));
  });

  test("a wind change does not climb back during the arrival descent", () {
    final RouteTrack track = northbound(100);
    final ProfileFlight flight = CruiseProfile(
      steps: [
        const CruiseStep(startNm: 0, altitudeFt: 6000, ktas: 120, gph: 8),
      ],
      climbTasKt: 90,
      climbRateFpm: 500,
      topAltitudeFt: 12000,
      startAltitudeFt: 6000,
      endAltitudeFt: 0,
      arriveAtEnd: true,
      totalNm: track.totalNm,
    ).fly(track, (LatLng point, int altitude) {
      final double miles = point.latitude * 60;
      // Tailwind before the turn, headwind after it.
      return miles < 85 ? (180.0, 40.0) : (0.0, 40.0);
    });
    expect(flight.altitudeAt(50), greaterThan(5500));
    expect(flight.altitudeAt(track.totalNm), lessThan(500));
    double lowest = flight.samples.first.altitudeFt;
    bool descending = false;
    for (final FlownSample sample in flight.samples) {
      if (!descending && sample.altitudeFt < 5500) {
        descending = true;
      }
      if (descending) {
        expect(sample.altitudeFt, lessThanOrEqualTo(lowest + 50));
      }
      if (sample.altitudeFt < lowest) {
        lowest = sample.altitudeFt;
      }
    }
    expect(descending, isTrue);
  });

  test("ground speed stays 1000 feet above the terrain", () {
    final RouteTrack track = northbound(100);
    final RouteCruiseResult result = BestCruiseAltitude.choose(
      track: track,
      terrainFt: flat(track, atNm: 90, elevation: 6000),
      altitudesFt: [4000, 8000, 12000],
      startAltitudeFt: 0,
      endAltitudeFt: 0,
      arriveAtEnd: true,
      climbTrueAirspeedKt: 80,
      climbRateConstantFpm: 1000,
      cruiseAt: (int altitude) => CruiseResult(ktas: 120, gph: 8),
      windAt: (LatLng point, int altitude) => (0.0, 0.0),
    );
    final List<int> winds = [];
    final ProfileFlight flight = result.profile!.fly(track, (LatLng point, int altitude) {
      final double miles = point.latitude * 60;
      if ((miles - 90).abs() <= 2) {
        winds.add(altitude);
      }
      return (0.0, 0.0);
    });
    expect(flight.altitudeAt(90), greaterThanOrEqualTo(7000));
    expect(winds, isNotEmpty);
    expect(winds.every((int altitude) => altitude >= 7000), isTrue);
    expect(flight.altitudeAt(track.totalNm), lessThan(500));
  });

  test("a peak between five-mile samples still raises the altitude", () {
    final RouteTrack track = BestCruiseAltitude.buildTrack([
      (from: const LatLng(0, 0), to: const LatLng(100 / 60.0, 0)),
    ], spacingNm: BestCruiseAltitude.terrainSpacingNm);
    final List<double?> terrain = [
      for (final ({double nm, LatLng at}) point in track.points)
        (point.nm - 12).abs() < 0.6 ? 8000.0 : 0.0,
    ];
    final RouteCruiseResult result = BestCruiseAltitude.choose(
      track: track,
      terrainFt: terrain,
      altitudesFt: [4000, 8000, 12000],
      startAltitudeFt: 0,
      endAltitudeFt: 0,
      arriveAtEnd: false,
      climbTrueAirspeedKt: 80,
      climbRateConstantFpm: 1000,
      cruiseAt: (int altitude) => CruiseResult(ktas: 120, gph: 8),
      windAt: (LatLng point, int altitude) => (0.0, 0.0),
    );
    expect(result.profile!.steps.first.altitudeFt, greaterThanOrEqualTo(9000));
    final ProfileFlight flight = result.profile!.fly(
      track,
      (LatLng point, int altitude) => (0.0, 0.0),
    );
    expect(flight.altitudeAt(12), greaterThanOrEqualTo(9000));
  });

  test("a typed altitude replaces one leg and leaves the legs after it", () {
    final CruiseProfile profile = CruiseProfile(
      steps: const [
        CruiseStep(startNm: 0, altitudeFt: 6000, ktas: 110, gph: 8),
        CruiseStep(startNm: 50, altitudeFt: 8000, ktas: 115, gph: 8),
        CruiseStep(startNm: 100, altitudeFt: 10000, ktas: 120, gph: 9),
      ],
      climbTasKt: 80,
      climbRateFpm: 1000,
      topAltitudeFt: 12000,
      startAltitudeFt: 6000,
      endAltitudeFt: 0,
      arriveAtEnd: false,
      totalNm: 180,
    );
    final CruiseProfile edited = profile.replaceSpan(
      fromNm: 20,
      toNm: 40,
      altitudeFt: 4500,
      ktas: 100,
      gph: 7,
    );
    expect(edited.stepAt(10).altitudeFt, 6000);
    expect(edited.stepAt(30).altitudeFt, 4500);
    expect(edited.stepAt(30).ktas, 100);
    expect(edited.stepAt(45).altitudeFt, 6000);
    expect(edited.stepAt(45).ktas, 110);
    expect(edited.stepAt(70).altitudeFt, 8000);
    expect(edited.stepAt(140).altitudeFt, 10000);
  });

  test("a fix in the arrival descent stays on the cruise altitude already reached", () {
    const LatLng kbos = LatLng(42.3629444444444, -71.0063888888889);
    const LatLng bos = LatLng(42.35745, -70.9895483333333);
    const LatLng cmk = LatLng(41.2800894444444, -73.5813263888889);
    const LatLng khpn = LatLng(41.0669530555556, -73.7075661111111);
    final RouteTrack track = BestCruiseAltitude.buildTrack([
      (from: kbos, to: bos),
      (from: bos, to: cmk),
      (from: cmk, to: khpn),
    ], spacingNm: 1);
    final CruiseProfile profile = CruiseProfile(
      steps: const [
        CruiseStep(startNm: 0, altitudeFt: 11000, ktas: 164, gph: 14),
        CruiseStep(startNm: 50, altitudeFt: 12000, ktas: 166, gph: 14),
      ],
      climbTasKt: 100,
      climbRateFpm: 1000,
      topAltitudeFt: 12000,
      startAltitudeFt: 19,
      endAltitudeFt: 439,
      arriveAtEnd: true,
      totalNm: track.totalNm,
    );
    final ProfileFlight flight = profile.fly(track, (LatLng point, int altitude) => (null, null));
    final double atBos = flight.fixNm[1];
    final double atCmk = flight.fixNm[2];
    expect(flight.altitudeAt(atBos), greaterThan(300));
    expect(flight.altitudeAt(atBos), lessThan(1500));
    expect(flight.reportedAltitudeAt(atBos), flight.altitudeAt(atBos));
    expect(flight.altitudeAt(atCmk), greaterThan(8000));
    expect(flight.altitudeAt(atCmk), lessThan(11000));
    expect(flight.reportedAltitudeAt(atCmk).round(), 12000);
    expect(flight.reportedAltitudeAt(flight.fixNm[flight.fixNm.length - 2]).round(), 12000);
  });
}
