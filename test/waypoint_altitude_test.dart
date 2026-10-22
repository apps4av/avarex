import 'package:avaremp/plan/waypoint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("round-trips waypoint and airway-fix altitudes", () {
    final Map<String, Object?> map = {"LocationID": "KBOS"};
    Waypoint.writeAltitudeFields(map, altitudeFt: 6500, fixAltitudeFt: {1: 4500, 3: 8500});

    final saved = Waypoint.readAltitudeFields(Map<String, dynamic>.from(map));

    expect(saved.altitudeFt, 6500);
    expect(saved.fixAltitudeFt[1], 4500);
    expect(saved.fixAltitudeFt[3], 8500);
    expect(saved.fixAltitudeFt.containsKey(0), isFalse);
    expect(saved.fixAltitudeFt.containsKey(2), isFalse);
  });

  test("airport field elevation is the start and end altitude", () {
    expect(Waypoint.airportFieldElevationFt("AIRPORT", 19.2), 19);
    expect(Waypoint.airportFieldElevationFt("HELIPORT", -11.6), -12);
    expect(Waypoint.airportFieldElevationFt("VOR", 400), isNull);
    expect(Waypoint.airportFieldElevationFt("AIRPORT", null), isNull);
    expect(Waypoint.airportFieldElevationFt("AIRPORT", 90000), isNull);
  });

  test("a below-sea-level field elevation round-trips", () {
    final Map<String, Object?> map = {"LocationID": "EHAM"};
    Waypoint.writeAltitudeFields(map, altitudeFt: -11);
    final saved = Waypoint.readAltitudeFields(Map<String, dynamic>.from(map));
    expect(saved.altitudeFt, -11);
  });

  test("missing altitude fields stay on the plan altitude", () {
    final saved = Waypoint.readAltitudeFields({"LocationID": "KBOS"});
    expect(saved.altitudeFt, isNull);
    expect(saved.fixAltitudeFt, isEmpty);
    expect(saved.ktas, isNull);
    expect(saved.gph, isNull);
    expect(saved.fixKtas, isEmpty);
    expect(saved.fixGph, isEmpty);
  });

  test("effective altitude prefers a fix override", () {
    final map = <String, Object?>{};
    Waypoint.writeAltitudeFields(map, altitudeFt: 6000, fixAltitudeFt: {2: 9000});
    final saved = Waypoint.readAltitudeFields(Map<String, dynamic>.from(map));
    expect(saved.altitudeFt ?? 3000, 6000);
    expect(saved.fixAltitudeFt[2] ?? saved.altitudeFt ?? 3000, 9000);
    expect(saved.fixAltitudeFt[0] ?? saved.altitudeFt ?? 3000, 6000);
  });

  test("round-trips the cruise speed chosen for a leg", () {
    final Map<String, Object?> map = {"LocationID": "KBOS"};
    Waypoint.writeAltitudeFields(
      map,
      altitudeFt: 8000,
      ktas: 122,
      gph: 8.4,
      fixAltitudeFt: {1: 10000},
      fixKtas: {1: 128},
      fixGph: {1: 7.6},
    );
    final saved = Waypoint.readAltitudeFields(Map<String, dynamic>.from(map));
    expect(saved.ktas, 122);
    expect(saved.gph, 8.4);
    expect(saved.fixAltitudeFt[1], 10000);
    expect(saved.fixKtas[1], 128);
    expect(saved.fixGph[1], 7.6);
    expect(saved.fixKtas.containsKey(0), isFalse);
  });
}
