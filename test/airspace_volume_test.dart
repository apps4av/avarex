import 'dart:io';
import 'dart:math' as math;

import 'package:avaremp/place/airspace_3d_view.dart';
import 'package:avaremp/place/airspace_volume.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

List<String> _tileSeamWalls(AirspaceScene scene, LatLng center) {
  final cosLat = math.cos(center.latitude * math.pi / 180).abs();
  final walls = <String>[];
  for (final shelf in scene.shelves) {
    for (final ring in shelf.rings) {
      for (var i = 0; i < ring.points.length; i++) {
        if (ring.hides(i)) {
          continue;
        }
        final a = ring.points[i];
        final b = ring.points[(i + 1) % ring.points.length];
        final de = (a.e - b.e).abs();
        final dn = (a.n - b.n).abs();
        if (math.sqrt(de * de + dn * dn) < 0.75) {
          continue;
        }
        final vertical = de <= 0.02 && dn > 0.75;
        final horizontal = dn <= 0.02 && de > 0.75;
        if (!vertical && !horizontal) {
          continue;
        }
        final lon = center.longitude + ((a.e + b.e) / 2) / (60 * cosLat);
        final lat = center.latitude + ((a.n + b.n) / 2) / 60;
        final yArg = lat * math.pi / 180;
        final x = (lon + 180) / 360 * 1024;
        final y = (1 - math.log(math.tan(yArg) + 1 / math.cos(yArg)) / math.pi) / 2 * 1024;
        final onTile = vertical ? (x - x.round()).abs() < 0.002 : (y - y.round()).abs() < 0.002;
        if (!onTile) {
          continue;
        }
        walls.add('${shelf.label} (${a.e.toStringAsFixed(2)},${a.n.toStringAsFixed(2)})->(${b.e.toStringAsFixed(2)},${b.n.toStringAsFixed(2)})');
      }
    }
  }
  return walls;
}

void main() {
  test('three-letter idents are shown with a K prefix', () {
    expect(airspaceIdent('MHT'), 'KMHT');
    expect(airspaceIdent('atl'), 'KATL');
    expect(airspaceIdent('KATL'), 'KATL');
    expect(airspaceIdent(''), '');
    expect(AirspaceShelf.altitudeRange(2000, 4000), '20-40');
    expect(AirspaceShelf.altitudeRange(2500, 4300), '25-43');
    expect(AirspaceShelf.altitudeRange(0, 12500), '00-125');
  });

  test('ownship is kept inside the view and dropped outside it', () {
    const center = LatLng(42.0, -71.0);
    final near = ownshipOffsetNm(center, const LatLng(42.1, -71.0));
    expect(near, isNotNull);
    expect(near!.n, closeTo(6, 0.01));
    expect(near.e, closeTo(0, 0.01));

    expect(ownshipOffsetNm(center, const LatLng(43.0, -71.0)), isNull);
    expect(ownshipOffsetNm(center, const LatLng(42.0, -70.0)), isNull);
    final edge = ownshipOffsetNm(center, const LatLng(42.0 + 25 / 60, -71.0));
    expect(edge, isNotNull);
    expect(edge!.n, closeTo(25, 0.01));
  });

  test('restricted and warning altitudes use the designator', () {
    expect(suaDesignator('R4101A'), 'R-4101A');
    expect(suaDesignator('W105A'), 'W-105A');
    expect(suaChartName('DEMO 3 MOA, VA'), 'DEMO 3');
    expect(suaChartName('EGLIN A WEST MOA, FL'), 'EGLIN A WEST');
    expect(parseSuaLimit('GND', 'FT', 'SFC')?.feet, 0);
    expect(parseSuaLimit('2500', 'FT', 'MSL')?.feet, 2500);
    expect(parseSuaLimit('500', 'FL', 'STD')?.feet, 50000);
    final unlimited = parseSuaLimit('UNL', 'OTHER', 'OTHER');
    expect(unlimited?.unlimited, isTrue);
    expect(AirspaceShelf.altitudeRange(0, 2500), '00-25');
    expect(AirspaceShelf.altitudeRange(0, 18000, unlimited: true), '00-UNL');
  });

  test('surface and flight-level altitudes', () {
    expect(parseAirspaceAltitude('0', 'SFC', 'FT'), 0);
    expect(parseAirspaceAltitude('2500', 'MSL', 'FT'), 2500);
    expect(parseAirspaceAltitude('180', null, 'FL'), 18000);
    expect(parseAirspaceAltitude(null, null, null), isNull);
  });

  test('clip keeps an interior square and cuts one that crosses the edge', () {
    final inside = clipPolygon(const [
      NmPoint(-2, -2),
      NmPoint(2, -2),
      NmPoint(2, 2),
      NmPoint(-2, 2),
    ], 10);
    expect(inside.length, 4);
    expect(polygonContains([inside], 0, 0), isTrue);

    final crossing = clipPolygon(const [
      NmPoint(-5, -5),
      NmPoint(20, -5),
      NmPoint(20, 5),
      NmPoint(-5, 5),
    ], 10);
    expect(crossing.every((p) => p.e <= 10 && p.e >= -10 && p.n <= 10 && p.n >= -10), isTrue);
    expect(polygonContains([crossing], 0, 0), isTrue);
    expect(polygonContains([crossing], 12, 0), isFalse);

    final buffered = clipPolygonRect(const [
      NmPoint(-5, 2),
      NmPoint(12, 2),
      NmPoint(12, 8),
      NmPoint(-5, 8),
    ], 0, 0, 10, 10);
    expect(buffered.every((p) => p.e >= 0 && p.e <= 10 && p.n >= 0 && p.n <= 10), isTrue);
    expect(buffered.any((p) => p.e == 0), isTrue);
    expect(buffered.any((p) => p.e == 10), isTrue);
  });

  test('simplify keeps a coarse circle', () {
    final ring = <NmPoint>[
      for (var i = 0; i < 200; i++)
        NmPoint(
          5 * math.cos(i * math.pi * 2 / 200),
          5 * math.sin(i * math.pi * 2 / 200),
        ),
    ];
    final simple = simplifyOpenRing(ring, 0.15);
    expect(simple.length, greaterThan(8));
    expect(simple.length, lessThan(80));
    expect(polygonContains([simple], 0, 0), isTrue);
  });

  final mbtiles = Platform.environment['AVAREX_NASR_MBTILES'];
  test('Atlanta Class B is read from the vector map', () {
    final scene = loadClassAirspace(mbtiles!, const LatLng(33.6407, -84.4277));
    expect(scene.message, isNull, reason: scene.message);
    expect(scene.shelves, isNotEmpty);
    final here = scene.shelvesAtCenter.map((s) => s.label).join(', ');
    expect(
      scene.shelvesAtCenter.any((s) => s.airspaceClass == 'B' && s.floorFt == 0 && s.ceilingFt == 12500),
      isTrue,
      reason: here,
    );
    expect(
      scene.shelves.every((s) => s.airspaceClass == 'B' || s.airspaceClass == 'C' || s.airspaceClass == 'D'),
      isTrue,
    );
  }, skip: mbtiles == null || mbtiles.isEmpty ? 'Set AVAREX_NASR_MBTILES to the nasr.mbtiles path' : false);

  test('Worcester Class D does not keep the tile-buffer column', () {
    final scene = loadClassAirspace(mbtiles!, const LatLng(42.2673, -71.8757));
    expect(scene.message, isNull, reason: scene.message);
    final visibleCuts = <double>[];
    final hiddenCuts = <double>[];
    for (final shelf in scene.shelves) {
      if (shelf.airspaceClass != 'D' || shelf.floorFt != 0 || shelf.ceilingFt != 3500) {
        continue;
      }
      for (final ring in shelf.rings) {
        for (var i = 0; i < ring.points.length; i++) {
          final a = ring.points[i];
          final b = ring.points[(i + 1) % ring.points.length];
          if ((a.e - b.e).abs() <= 3 || (a.n - b.n).abs() >= 0.08) {
            continue;
          }
          final north = (a.n + b.n) / 2;
          if (ring.hides(i)) {
            hiddenCuts.add(north);
          } else {
            visibleCuts.add(north);
          }
        }
      }
    }
    expect(visibleCuts, isEmpty, reason: 'visible chords at $visibleCuts');
  }, skip: mbtiles == null || mbtiles.isEmpty ? 'Set AVAREX_NASR_MBTILES to the nasr.mbtiles path' : false);

  test('tile seams stay hidden when the click point changes', () {
    const kpvd = LatLng(41.7240, -71.4283);
    const korh = LatLng(42.2673, -71.8757);
    final southOfKorh = LatLng(korh.latitude - 18 / 60.0, korh.longitude);
    for (final center in [kpvd, korh, southOfKorh]) {
      final scene = loadClassAirspace(mbtiles!, center);
      expect(scene.message, isNull, reason: scene.message);
      final walls = _tileSeamWalls(scene, center);
      expect(walls, isEmpty, reason: '${center.latitude},${center.longitude}: ${walls.join("; ")}');
    }
    final providence = loadClassAirspace(mbtiles!, kpvd);
    final lowShelves = providence.shelves.where((s) => s.airspaceClass == 'C' && s.floorFt == 1300 && s.ceilingFt == 4100);
    expect(lowShelves.length, 1);
    expect(lowShelves.first.area, greaterThan(50));
    expect(lowShelves.first.rings.any((ring) => ring.points.length <= 4), isFalse);
  }, skip: mbtiles == null || mbtiles.isEmpty ? 'Set AVAREX_NASR_MBTILES to the nasr.mbtiles path' : false);

  test('Camp Edwards restricted area and a nearby warning area are included', () {
    final edwards = loadClassAirspace(mbtiles!, const LatLng(41.68, -70.55));
    expect(edwards.message, isNull, reason: edwards.message);
    final restricted = edwards.shelves.where((shelf) => shelf.airspaceClass == 'RESTRICTED').toList();
    expect(restricted, isNotEmpty);
    expect(restricted.map((shelf) => shelf.label), contains('R-4101A 00-25'));
    expect(edwards.airports.any((mark) => mark.ident == 'R-4101A'), isFalse);
    expect(edwards.shelves.where((shelf) => shelf.airspaceClass == 'WARNING'), isEmpty);

    final narragansett = loadClassAirspace(mbtiles, const LatLng(41.10, -71.20));
    expect(narragansett.message, isNull, reason: narragansett.message);
    final warning = narragansett.shelves.where((shelf) => shelf.airspaceClass == 'WARNING').toList();
    expect(warning.map((shelf) => shelf.label), contains('W-105A 00-500'));
  }, skip: mbtiles == null || mbtiles.isEmpty ? 'Set AVAREX_NASR_MBTILES to the nasr.mbtiles path' : false);

  test('Washington prohibited area and a MOA are included', () {
    final scene = loadClassAirspace(mbtiles!, const LatLng(38.8977, -77.0365));
    expect(scene.message, isNull, reason: scene.message);
    final labels = scene.shelves.map((shelf) => shelf.label).toList();
    expect(labels, contains('P-56A 00-180'));
    expect(labels, contains('DEMO 1 5-50'));
    expect(scene.shelves.any((shelf) => shelf.airspaceClass == 'PROHIBITED' && shelf.ident == 'P-56A'), isTrue);
    expect(scene.shelves.any((shelf) => shelf.airspaceClass == 'MOA' && shelf.ident == 'DEMO 1'), isTrue);
    expect(scene.airports.any((mark) => mark.ident == 'P-56A' || mark.ident == 'DEMO 1'), isFalse);
  }, skip: mbtiles == null || mbtiles.isEmpty ? 'Set AVAREX_NASR_MBTILES to the nasr.mbtiles path' : false);

  test('R-5203 is clipped at 10,000 ft so it does not cover KROC', () {
    final scene = loadClassAirspace(mbtiles!, const LatLng(43.1189, -77.6724));
    expect(scene.message, isNull, reason: scene.message);
    expect(scene.maxAltitudeFt, lessThanOrEqualTo(airspaceDisplayCapFt));
    final restricted = scene.shelves.where((shelf) => shelf.ident == 'R-5203').toList();
    expect(restricted, isNotEmpty);
    expect(restricted.first.ceilingFt, greaterThan(airspaceDisplayCapFt));
    expect(restricted.first.label, 'R-5203 00-500');
    expect(scene.shelves.any((shelf) => shelf.ident == 'KROC' && shelf.ceilingFt == 4600), isTrue);
    expect(scene.airports.any((mark) => mark.ident == 'KROC'), isTrue);
    expect(scene.airports.any((mark) => mark.ident == 'R-5203'), isFalse);
  }, skip: mbtiles == null || mbtiles.isEmpty ? 'Set AVAREX_NASR_MBTILES to the nasr.mbtiles path' : false);

  test('Manchester Class C labels use hundreds of feet', () {
    final scene = loadClassAirspace(mbtiles!, const LatLng(42.9328, -71.4357));
    expect(scene.message, isNull, reason: scene.message);
    final lines = scene.shelves.where((shelf) => shelf.ident == 'KMHT').map((shelf) => shelf.label).toList();
    expect(lines, contains('25-43'));
    expect(lines, contains('00-43'));
    expect(lines.any((text) => text.contains('KMHT')), isFalse);
    final airport = scene.airports.singleWhere((mark) => mark.ident == 'KMHT');
    expect(airport.airspaceClass, 'C');
    expect(airport.e.abs(), lessThan(3));
    expect(airport.n.abs(), lessThan(3));
    expect(scene.airports.every((mark) => mark.airspaceClass == 'B' || mark.airspaceClass == 'C' || mark.airspaceClass == 'D'), isTrue);
  }, skip: mbtiles == null || mbtiles.isEmpty ? 'Set AVAREX_NASR_MBTILES to the nasr.mbtiles path' : false);

  test('Providence Class C does not draw the tile-edge wedge', () {
    final scene = loadClassAirspace(mbtiles!, const LatLng(41.7240, -71.4283));
    expect(scene.message, isNull, reason: scene.message);
    final wedges = <String>[];
    var shelfArea = 0.0;
    for (final shelf in scene.shelves) {
      if (shelf.airspaceClass != 'C' || shelf.floorFt != 1300 || shelf.ceilingFt != 4100) {
        continue;
      }
      shelfArea += shelf.area;
      for (final ring in shelf.rings) {
        for (var i = 0; i < ring.points.length; i++) {
          if (ring.hides(i)) {
            continue;
          }
          final a = ring.points[i];
          final b = ring.points[(i + 1) % ring.points.length];
          final de = (a.e - b.e).abs();
          final dn = (a.n - b.n).abs();
          if (dn > 4 && de < 0.15) {
            wedges.add('(${a.e.toStringAsFixed(2)},${a.n.toStringAsFixed(2)})->(${b.e.toStringAsFixed(2)},${b.n.toStringAsFixed(2)})');
          }
        }
      }
    }
    expect(shelfArea, greaterThan(20));
    expect(wedges, isEmpty, reason: wedges.join('; '));
  }, skip: mbtiles == null || mbtiles.isEmpty ? 'Set AVAREX_NASR_MBTILES to the nasr.mbtiles path' : false);

  Position _fix(double lat, double lon) {
    return Position(
      latitude: lat,
      longitude: lon,
      timestamp: DateTime.utc(2026),
      accuracy: 0,
      altitude: 300,
      altitudeAccuracy: 0,
      heading: 90,
      headingAccuracy: 0,
      speed: 40,
      speedAccuracy: 0,
    );
  }

  testWidgets('ownship paints inside the area and is dropped outside it', (tester) async {
    const center = LatLng(42.0, -71.0);
    final scene = AirspaceScene(
      radiusNm: airspaceViewRadiusNm,
      shelves: [
        AirspaceShelf(
          airspaceClass: 'D',
          name: 'TEST',
          ident: 'KTEST',
          sector: '',
          floorFt: 0,
          ceilingFt: 2500,
          rings: [
            const AirspaceRing(
              [NmPoint(-2, -2), NmPoint(2, -2), NmPoint(0, 2)],
              [false, false, false],
            ),
          ],
          containsCenter: true,
          area: 8,
        ),
      ],
    );
    Airspace3DView.debugSetScene(center, scene);
    addTearDown(() => Airspace3DView.debugSetScene(center, null));

    final gps = ValueNotifier<Position>(_fix(42.05, -71.0));
    addTearDown(gps.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Airspace3DView(center: center, ownship: gps)),
    ));
    expect(find.textContaining('Drag to rotate'), findsOneWidget);
    expect(tester.takeException(), isNull);

    gps.value = _fix(44.0, -71.0);
    await tester.pump();
    expect(tester.takeException(), isNull);

    gps.value = _fix(0, 0);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a shelf above 10,000 ft paints an open crown', (tester) async {
    const center = LatLng(43.1189, -77.6724);
    final scene = AirspaceScene(
      radiusNm: airspaceViewRadiusNm,
      shelves: [
        AirspaceShelf(
          airspaceClass: 'C',
          name: 'ROCHESTER',
          ident: 'KROC',
          sector: '',
          floorFt: 0,
          ceilingFt: 4600,
          rings: [
            const AirspaceRing(
              [NmPoint(-4, -4), NmPoint(4, -4), NmPoint(4, 4), NmPoint(-4, 4)],
              [false, false, false, false],
            ),
          ],
          containsCenter: true,
          area: 64,
          label: 'KROC 00-46',
          showLabel: true,
        ),
        AirspaceShelf(
          airspaceClass: 'RESTRICTED',
          name: 'R-5203',
          ident: 'R-5203',
          sector: '',
          floorFt: 0,
          ceilingFt: 50000,
          rings: [
            const AirspaceRing(
              [NmPoint(-12, -12), NmPoint(12, -12), NmPoint(12, 12), NmPoint(-12, 12)],
              [false, false, false, false],
            ),
          ],
          containsCenter: true,
          area: 576,
          label: 'R-5203 00-500',
          showLabel: true,
        ),
      ],
    );
    expect(scene.maxAltitudeFt, airspaceDisplayCapFt);
    Airspace3DView.debugSetScene(center, scene);
    addTearDown(() => Airspace3DView.debugSetScene(center, null));

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Airspace3DView(center: center)),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('3D view draws Atlanta shelves and accepts a drag', (tester) async {
    const center = LatLng(33.6407, -84.4277);
    final scene = loadClassAirspace(mbtiles!, center);
    Airspace3DView.debugSetScene(center, scene);
    addTearDown(() => Airspace3DView.debugSetScene(center, null));

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Airspace3DView(center: center)),
    ));

    expect(scene.shelves.any((shelf) => shelf.ident == 'KATL' && shelf.label.contains('00-125')), isTrue);
    expect(scene.airports.any((mark) => mark.ident == 'KATL'), isTrue);
    expect(find.textContaining('KATL'), findsNothing);
    expect(find.textContaining('Drag to rotate'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(Airspace3DView), const Offset(80, -30));
    await tester.pump();
    expect(tester.takeException(), isNull);
  }, skip: mbtiles == null || mbtiles.isEmpty);
}
