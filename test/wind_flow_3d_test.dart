import 'dart:math' as math;

import 'package:avaremp/weather/wind_flow_3d.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

WindFlowField _uniform(WindVector wind, {double radiusNm = 25}) {
  return WindFlowField(
    cols: 2,
    rows: 2,
    radiusNm: radiusNm,
    altitudesFt: const [0, 12000],
    eastKt: List.filled(8, wind.eastKt),
    northKt: List.filled(8, wind.northKt),
  );
}

void main() {
  test('wind vector points downwind', () {
    final fromWest = windVectorFrom(270, 20);
    expect(fromWest.eastKt, closeTo(20, 0.01));
    expect(fromWest.northKt, closeTo(0, 0.01));

    final fromNorth = windVectorFrom(360, 15);
    expect(fromNorth.eastKt, closeTo(0, 0.01));
    expect(fromNorth.northKt, closeTo(-15, 0.01));

    expect(windVectorFrom(90, 0), WindVector.zero);
  });

  test('nearby wind outweighs a distant one', () {
    final blended = blendWindVectors([
      (wind: const WindVector(10, 0), distanceNm: 1),
      (wind: const WindVector(0, 10), distanceNm: 100),
    ]);
    expect(blended.eastKt, greaterThan(9));
    expect(blended.northKt, lessThan(1));
    expect(blendWindVectors(const []), WindVector.zero);
  });

  test('speed colors run from blue to red', () {
    expect(windSpeedColor(0), const Color(0xFF1E88E5));
    expect(windSpeedColor(60), const Color(0xFFE53935));
    expect(windSpeedColor(90), const Color(0xFFE53935));
    final mid = windSpeedColor(30);
    expect(mid, isNot(windSpeedColor(0)));
    expect(mid.g, greaterThan(mid.b));
  });

  test('volume levels stay inside the 3D scale', () {
    final levels = windFlowAltitudes(10000);
    expect(levels.length, 4);
    expect(levels.first, greaterThan(500));
    expect(levels.last, lessThan(10000));
    for (var i = 1; i < levels.length; i++) {
      expect(levels[i], greaterThan(levels[i - 1]));
    }
  });

  test('prepared field interpolates east, north, and altitude', () {
    final field = prepareWindFlowField(
      radiusNm: 25,
      maxAltitudeFt: 10000,
      cols: 2,
      rows: 2,
      sample: (east, north, altitude) => WindVector(east, altitude / 1000),
    );
    final midAlt = (field.altitudesFt.first + field.altitudesFt.last) / 2;
    final at = field.sample(0, 0, midAlt);
    expect(at.eastKt, closeTo(0, 0.05));
    expect(at.northKt, closeTo(midAlt / 1000, 0.05));
    expect(field.sample(25, -25, field.altitudesFt.first).eastKt,
        closeTo(25, 0.01));
  });

  test('a streak points downwind and a particle moves that way', () {
    final field = _uniform(const WindVector(20, 0));
    final particle = WindFlowParticle(
      eastNm: 0,
      northNm: 1,
      altitudeFt: 4000,
      ageSeconds: 2,
      maxAgeSeconds: 8,
    );
    final streak = windFlowStreak(particle, field);
    expect(streak, isNotNull);
    expect(streak!.headEast, closeTo(0, 0.01));
    expect(streak.tailEast, lessThan(streak.headEast));
    expect(streak.tailNorth, closeTo(streak.headNorth, 0.01));
    expect(streak.altitudeFt, 4000);
    expect(streak.speedKt, closeTo(20, 0.01));

    advanceWindFlow(
      particles: [particle],
      field: field,
      random: math.Random(1),
      dtSeconds: 0.05,
      radiusNm: 25,
      maxAltitudeFt: 10000,
    );
    expect(particle.eastNm,
        closeTo(20 * windFlowVisualNmPerKnotSecond * 0.05, 0.0001));
    expect(particle.northNm, closeTo(1, 0.0001));
  });

  test('a particle that leaves the box is placed back inside', () {
    final field = _uniform(const WindVector(20, 0));
    final particle = WindFlowParticle(
      eastNm: 24.95,
      northNm: 0,
      altitudeFt: 4000,
      ageSeconds: 1,
      maxAgeSeconds: 20,
    );
    advanceWindFlow(
      particles: [particle],
      field: field,
      random: math.Random(1),
      dtSeconds: 0.05,
      radiusNm: 25,
      maxAltitudeFt: 10000,
    );
    expect(particle.eastNm.abs(), lessThanOrEqualTo(25));
    expect(particle.northNm.abs(), lessThanOrEqualTo(25));
    expect(particle.eastNm, lessThan(24));
  });

  test('a streak under the terrain is dropped and one that meets a hill is cut',
      () {
    final under = windStreakAboveGround(
      headEast: 0,
      headNorth: 0,
      tailEast: -1,
      tailNorth: 0,
      altitudeFt: 2000,
      groundFt: (east, north) => 5000,
    );
    expect(under, isNull);

    final clear = windStreakAboveGround(
      headEast: 0,
      headNorth: 0,
      tailEast: -1,
      tailNorth: 0,
      altitudeFt: 4000,
      groundFt: (east, north) => 1000,
    );
    expect(clear, isNotNull);
    expect(clear!.east, closeTo(-1, 0.01));

    // Ground rises toward the west. The head is above it and the tail is not.
    final cut = windStreakAboveGround(
      headEast: 0,
      headNorth: 0,
      tailEast: -2,
      tailNorth: 0,
      altitudeFt: 2000,
      groundFt: (east, north) => 1500 - east * 1000,
    );
    expect(cut, isNotNull);
    expect(cut!.east, lessThan(0));
    expect(cut.east, greaterThan(-1));
    expect(cut.north, closeTo(0, 0.01));
  });

  test('nearest winds station to Boston is BOS', () {
    final near = WindsCache.stationsNear(const LatLng(42.36, -71.06));
    expect(near, isNotEmpty);
    expect(near.first.id, 'BOS');
  });
}
