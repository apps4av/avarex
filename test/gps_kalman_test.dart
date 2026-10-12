import 'package:avaremp/io/gps_kalman.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

Position _fix({
  required double lat,
  required double lon,
  required double alt,
  required double heading,
  required double speed,
  required DateTime t,
}) {
  return Position(
    latitude: lat,
    longitude: lon,
    timestamp: t,
    accuracy: 5,
    altitude: alt,
    altitudeAccuracy: 5,
    heading: heading,
    headingAccuracy: 5,
    speed: speed,
    speedAccuracy: 1,
  );
}

void main() {
  const double lat0 = 40.0;
  const double lon0 = -75.0;
  const double mPerDegLat = 111320.0;

  group('GpsKalman', () {
    test('follows a northbound track', () {
      final GpsKalman k = GpsKalman();
      final DateTime t0 = DateTime.utc(2026, 1, 1);
      Position last = _fix(
        lat: lat0,
        lon: lon0,
        alt: 1000,
        heading: 0,
        speed: 50,
        t: t0,
      );
      k.update(last);

      for (int i = 1; i <= 8; i++) {
        final DateTime t = t0.add(Duration(seconds: i));
        last = _fix(
          lat: lat0 + (50.0 * i) / mPerDegLat,
          lon: lon0,
          alt: 1000,
          heading: 0,
          speed: 50,
          t: t,
        );
        k.update(last);
      }

      final Position out = k.output(last, now: last.timestamp);
      expect(out.latitude, closeTo(last.latitude, 0.002));
      expect(out.speed, closeTo(50, 5));
      expect(out.heading, closeTo(0, 8));
      expect(out.altitude, closeTo(1000, 20));
    });

    test('holds heading and speed near zero when at rest', () {
      final GpsKalman k = GpsKalman();
      final DateTime t0 = DateTime.utc(2026, 1, 1);
      Position last = _fix(
        lat: lat0,
        lon: lon0,
        alt: 200,
        heading: 270,
        speed: 40,
        t: t0,
      );
      k.update(last);
      last = _fix(
        lat: lat0,
        lon: lon0 - 40 / (mPerDegLat * 0.766),
        alt: 200,
        heading: 270,
        speed: 40,
        t: t0.add(const Duration(seconds: 1)),
      );
      k.update(last);

      for (int i = 2; i <= 10; i++) {
        last = _fix(
          lat: lat0,
          lon: lon0 - 40 / (mPerDegLat * 0.766),
          alt: 200,
          heading: 0,
          speed: 0,
          t: t0.add(Duration(seconds: i)),
        );
        k.update(last);
      }

      final Position out = k.output(last, now: last.timestamp);
      expect(out.heading, closeTo(270, 15));
      expect(out.speed, lessThan(GpsKalman.restSpeedMs));
    });

    test('coasts heading, speed, and position until the GPS-lost warning', () {
      final GpsKalman k = GpsKalman();
      final DateTime t0 = DateTime.utc(2026, 1, 1);
      Position last = _fix(
        lat: lat0,
        lon: lon0,
        alt: 1500,
        heading: 0,
        speed: 50,
        t: t0,
      );
      k.update(last);
      last = _fix(
        lat: lat0 + 50 / mPerDegLat,
        lon: lon0,
        alt: 1500,
        heading: 0,
        speed: 50,
        t: t0.add(const Duration(seconds: 1)),
      );
      k.update(last);

      final DateTime lostAt = last.timestamp;
      expect(GpsKalman.predictLimit, const Duration(seconds: 60));
      final Position coast = k.output(
        last,
        now: lostAt.add(const Duration(seconds: 50)),
      );
      final double expectedLat = last.latitude + (50 * 50) / mPerDegLat;
      expect(coast.latitude, closeTo(expectedLat, 0.005));
      expect(coast.heading, closeTo(0, 10));
      expect(coast.speed, closeTo(50, 8));
      expect(coast.altitude, closeTo(1500, 40));
    });

    test('stops predicting when the GPS-lost warning window ends', () {
      final GpsKalman k = GpsKalman();
      final DateTime t0 = DateTime.utc(2026, 1, 1);
      Position last = _fix(
        lat: lat0,
        lon: lon0,
        alt: 800,
        heading: 90,
        speed: 60,
        t: t0,
      );
      k.update(last);
      last = _fix(
        lat: lat0,
        lon: lon0 + 60 / (mPerDegLat * 0.766),
        alt: 800,
        heading: 90,
        speed: 60,
        t: t0.add(const Duration(seconds: 1)),
      );
      k.update(last);

      final DateTime lostAt = last.timestamp;
      final Position atLimit = k.output(
        last,
        now: lostAt.add(GpsKalman.predictLimit),
      );
      final Position afterLimit = k.output(
        last,
        now: lostAt.add(GpsKalman.predictLimit + const Duration(seconds: 15)),
      );
      expect(afterLimit.latitude, closeTo(atLimit.latitude, 1e-8));
      expect(afterLimit.longitude, closeTo(atLimit.longitude, 1e-8));
      expect(afterLimit.altitude, closeTo(atLimit.altitude, 1e-6));
      expect(afterLimit.heading, closeTo(atLimit.heading, 1e-6));
      expect(afterLimit.speed, closeTo(atLimit.speed, 1e-6));
    });

    test('apply ignores a repeated stack sample and only coasts', () {
      final GpsKalman k = GpsKalman();
      final DateTime t0 = DateTime.utc(2026, 1, 1);
      final Position moving = _fix(
        lat: lat0,
        lon: lon0,
        alt: 600,
        heading: 0,
        speed: 40,
        t: t0,
      );
      k.apply(moving, now: t0);
      final Position next = _fix(
        lat: lat0 + 40 / mPerDegLat,
        lon: lon0,
        alt: 600,
        heading: 0,
        speed: 40,
        t: t0.add(const Duration(seconds: 1)),
      );
      k.apply(next, now: next.timestamp);

      // Same object/timestamp as the last stack pop (GPS lost).
      final Position coast = k.apply(
        next,
        now: next.timestamp.add(const Duration(seconds: 10)),
      );
      expect(coast.latitude, greaterThan(next.latitude));
      expect(coast.speed, closeTo(40, 10));
    });

    test('reacquires after the coast window and follows a new fix', () {
      final GpsKalman k = GpsKalman();
      final DateTime t0 = DateTime.utc(2026, 1, 1);
      Position last = _fix(
        lat: lat0,
        lon: lon0,
        alt: 400,
        heading: 180,
        speed: 30,
        t: t0,
      );
      k.update(last);

      final DateTime later = t0.add(GpsKalman.predictLimit + const Duration(seconds: 10));
      last = _fix(
        lat: 41.0,
        lon: -74.0,
        alt: 900,
        heading: 45,
        speed: 55,
        t: later,
      );
      k.update(last);
      final Position out = k.output(last, now: later);
      expect(out.latitude, closeTo(41.0, 0.01));
      expect(out.longitude, closeTo(-74.0, 0.01));
      expect(out.heading, closeTo(45, 15));
      expect(out.speed, closeTo(55, 10));
    });

    test('does not initialize on a 0,0 unlock sample', () {
      final GpsKalman k = GpsKalman();
      k.update(_fix(
        lat: 0,
        lon: 0,
        alt: 0,
        heading: 0,
        speed: 0,
        t: DateTime.utc(2026, 1, 1),
      ));
      expect(k.initialized, isFalse);
    });
  });
}
