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
    final RouteTrack track = northbound(100);
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
      // Northbound. Before 50 nm, 4,000 ft has the tailwind. After that, 8,000 ft does.
      windAt: (LatLng point, int altitude) {
        final double miles = point.latitude * 60;
        if (miles < 50) {
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
}
