import 'dart:io';
import 'dart:math' as math;

import 'package:avaremp/place/airspace_3d_view.dart';
import 'package:avaremp/place/airspace_volume.dart';
import 'package:avaremp/weather/tfr.dart';
import 'package:avaremp/utils/mbtiles_layer.dart';
import 'package:mbtiles/mbtiles.dart';
import 'package:vector_tile/vector_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
        final y =
            (1 - math.log(math.tan(yArg) + 1 / math.cos(yArg)) / math.pi) /
                2 *
                1024;
        final onTile = vertical
            ? (x - x.round()).abs() < 0.002
            : (y - y.round()).abs() < 0.002;
        if (!onTile) {
          continue;
        }
        walls.add(
            '${shelf.label} (${a.e.toStringAsFixed(2)},${a.n.toStringAsFixed(2)})->(${b.e.toStringAsFixed(2)},${b.n.toStringAsFixed(2)})');
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
    expect(AirspaceShelf.altitudeRange(0, 12500), 'SF-125');
    expect(AirspaceShelf.altitudeRange(500, 5000), '05-50');
  });

  test('vector map labels use hundreds of feet and the airport at the center',
      () {
    expect(
      vectorAirspaceLabel({
        'CLASS': 'C',
        'IDENT': 'MHT',
        'LOWER_VAL': '2500',
        'LOWER_CODE': 'MSL',
        'LOWER_UOM': 'FT',
        'UPPER_VAL': '4300',
        'UPPER_CODE': 'MSL',
        'UPPER_UOM': 'FT',
      }, sua: false),
      '25-43',
    );
    expect(
      vectorAirspaceLabel({
        'CLASS': 'C',
        'IDENT': 'MHT',
        'LOWER_VAL': '0',
        'LOWER_CODE': 'SFC',
        'LOWER_UOM': 'FT',
        'UPPER_VAL': '4300',
        'UPPER_CODE': 'MSL',
        'UPPER_UOM': 'FT',
      }, sua: false, airportAtCenter: true),
      'KMHT\nSF-43',
    );
    expect(
      vectorAirspaceLabel({
        'CLASS': 'B',
        'IDENT': 'BOS',
        'SECTOR': 'AREA C',
        'LOWER_VAL': '3000',
        'LOWER_CODE': 'MSL',
        'LOWER_UOM': 'FT',
        'UPPER_VAL': '7000',
        'UPPER_CODE': 'MSL',
        'UPPER_UOM': 'FT',
      }, sua: false),
      '30-70',
    );
    expect(
      vectorAirspaceLabel({
        'TYPE': 'RESTRICTED',
        'DESIGNATOR': 'R4101A',
        'LOWER_LIMIT': 'GND',
        'LOWER_UOM': 'FT',
        'LOWER_REF': 'SFC',
        'UPPER_LIMIT': '2500',
        'UPPER_UOM': 'FT',
        'UPPER_REF': 'MSL',
      }, sua: true),
      'R-4101A SF-25',
    );
    expect(vectorAirspaceLabel({'CLASS': 'C', 'EXCLUSION': '1'}, sua: false),
        isNull);
    expect(MBTilesLayerManager.debugThemeLayerCount(), 18);
    final spread = airspaceLabelGrid([
      [
        [200, 200],
        [3800, 200],
        [3800, 3800],
        [200, 3800],
      ],
    ], 4096);
    expect(spread.length, greaterThan(4));
    expect(
        spread.every((point) =>
            point[0] > 150 &&
            point[0] < 3950 &&
            point[1] > 150 &&
            point[1] < 3950),
        isTrue);
  });

  test('airport diagrams sit on the runway ends inside 25 NM', () {
    const center = LatLng(42.0, -71.0);
    final diagrams = airportDiagramsInView(
      [
        {
          'LocationID': 'MHT',
          'DLID': '1',
          'ARPLatitude': 42.0,
          'ARPLongitude': -71.0,
          'Type': 'AIRPORT',
        },
        {
          'LocationID': 'FAR',
          'DLID': '2',
          'ARPLatitude': 43.0,
          'ARPLongitude': -71.0,
          'Type': 'AIRPORT',
        },
        {
          'LocationID': 'H1',
          'DLID': '3',
          'ARPLatitude': 42.01,
          'ARPLongitude': -71.0,
          'Type': 'HELIPORT',
        },
      ],
      [
        {
          'DLID': '1',
          'LEIdent': '35',
          'HEIdent': '17',
          'LELatitude': 42.0 + 0.5 / 60,
          'HELatitude': 42.0 - 0.5 / 60,
          'LELongitude': -71.0,
          'HELongitude': -71.0,
          'Length': '6076',
          'Width': '150',
          'Surface': 'ASPH-G',
        },
        {
          'DLID': '2',
          'LEIdent': '18',
          'HEIdent': '36',
          'LELatitude': 43.0,
          'HELatitude': 43.01,
          'LELongitude': -71.0,
          'HELongitude': -71.0,
          'Length': '5000',
          'Width': '100',
          'Surface': 'CONC',
        },
      ],
      center: center,
    );
    expect(diagrams, hasLength(1));
    expect(diagrams.single.ident, 'MHT');
    expect(diagrams.single.at.e, closeTo(0, 0.02));
    expect(diagrams.single.at.n, closeTo(0, 0.02));
    final runway = diagrams.single.runways.single;
    expect(runway.low.n, closeTo(0.5, 0.02));
    expect(runway.high.n, closeTo(-0.5, 0.02));
    expect(runway.low.e.abs(), lessThan(0.02));
    expect(runway.widthFt, 150);
    expect(runway.surface, 'ASPH-G');
    expect(runway.lowIdent, '35');
    expect(runway.highIdent, '17');
  });

  test('a single runway without ends is placed from its length and heading', () {
    const center = LatLng(42.0, -71.0);
    final diagrams = airportDiagramsInView(
      [
        {
          'LocationID': '1B9',
          'DLID': '9',
          'ARPLatitude': 42.0,
          'ARPLongitude': -71.0,
        },
      ],
      [
        {
          'DLID': '9',
          'LEIdent': '36',
          'HEIdent': '18',
          'LELatitude': 0,
          'HELatitude': 0,
          'LELongitude': 0,
          'HELongitude': 0,
          'Length': '6076',
          'Width': '',
          'Surface': 'TURF',
          'LEHeadingT': '360',
        },
      ],
      center: center,
    );
    expect(diagrams, hasLength(1));
    final runway = diagrams.single.runways.single;
    expect(runway.low.n, closeTo(-0.5, 0.02));
    expect(runway.high.n, closeTo(0.5, 0.02));
    expect(runway.low.e.abs(), lessThan(0.02));
    expect(runway.widthFt, 50);
    expect(runway.surface, 'TURF');

    final fromIdent = airportDiagramsInView(
      [
        {
          'LocationID': '1B9',
          'DLID': '9',
          'ARPLatitude': 42.0,
          'ARPLongitude': -71.0,
        },
      ],
      [
        {
          'DLID': '9',
          'LEIdent': '09',
          'HEIdent': '27',
          'LELatitude': '0',
          'HELatitude': '0',
          'LELongitude': '0',
          'HELongitude': '0',
          'Length': '6076',
        },
      ],
      center: center,
    );
    final east = fromIdent.single.runways.single;
    expect(east.low.e, closeTo(-0.5, 0.02));
    expect(east.high.e, closeTo(0.5, 0.02));
    expect(east.low.n.abs(), lessThan(0.02));
  });

  test('several runways with no ends are left off the diagram', () {
    const center = LatLng(42.0, -71.0);
    final diagrams = airportDiagramsInView(
      [
        {
          'LocationID': 'PVT',
          'DLID': '4',
          'ARPLatitude': 42.0,
          'ARPLongitude': -71.0,
          'Type': 'AIRPORT',
        },
      ],
      [
        {
          'DLID': '4',
          'LEIdent': '18',
          'HEIdent': '36',
          'LELatitude': 0,
          'HELatitude': 0,
          'LELongitude': 0,
          'HELongitude': 0,
          'Length': '3000',
        },
        {
          'DLID': '4',
          'LEIdent': '09',
          'HEIdent': '27',
          'LELatitude': 0,
          'HELatitude': 0,
          'LELongitude': 0,
          'HELongitude': 0,
          'Length': '2500',
        },
      ],
      center: center,
    );
    expect(diagrams, isEmpty);
    final scene = AirspaceScene(
      radiusNm: airspaceViewRadiusNm,
      shelves: const [],
      diagrams: [
        AirspaceDiagram(
          ident: 'MHT',
          at: const NmPoint(1, 2),
          runways: [
            AirspaceRunway(
              low: const NmPoint(1, 1),
              high: const NmPoint(1, 3),
              widthFt: 150,
              surface: 'ASPH',
              lowIdent: '17',
              highIdent: '35',
            ),
          ],
        ),
      ],
    );
    final next = scene.copyWith(
      obstacles: [AirspaceObstacle(e: 0, n: 0, heightFt: 500)],
    );
    expect(next.diagrams, same(scene.diagrams));
    expect(next.obstacles, hasLength(1));
  });

  test('obstacles inside 25 NM keep their MSL height in hundreds of feet', () {
    const center = LatLng(42.9328, -71.4357);
    final obstacles = obstaclesInView([
      {'ARPLatitude': 43.17591, 'ARPLongitude': -71.20756, 'Height': 1548},
      {'ARPLatitude': 42.9328, 'ARPLongitude': -71.4357, 'Height': 2049},
      {'ARPLatitude': 44.0, 'ARPLongitude': -71.4357, 'Height': 900},
      {'ARPLatitude': 42.95, 'ARPLongitude': -71.45, 'Height': 0},
    ], center);
    expect(obstacles.length, 2);
    expect(obstacles.first.label, '15');
    expect(obstacles.first.heightFt, 1548);
    expect(obstacles.first.e, closeTo(10.02, 0.05));
    expect(obstacles.first.n, closeTo(14.59, 0.05));
    expect(obstacles.last.label, '20');
    expect(
      AirspaceScene(
        radiusNm: airspaceViewRadiusNm,
        shelves: const [],
        obstacles: [AirspaceObstacle(e: 0, n: 0, heightFt: 6500)],
      ).maxAltitudeFt,
      6500,
    );
    expect(
      AirspaceScene(
        radiusNm: airspaceViewRadiusNm,
        shelves: const [],
        obstacles: [AirspaceObstacle(e: 0, n: 0, heightFt: 18000)],
      ).maxAltitudeFt,
      airspaceDisplayCapFt,
    );
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
    expect(AirspaceShelf.altitudeRange(0, 2500), 'SF-25');
    expect(AirspaceShelf.altitudeRange(0, 18000, unlimited: true), 'SF-UNL');
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
    expect(
        crossing
            .every((p) => p.e <= 10 && p.e >= -10 && p.n <= 10 && p.n >= -10),
        isTrue);
    expect(polygonContains([crossing], 0, 0), isTrue);
    expect(polygonContains([crossing], 12, 0), isFalse);

    final buffered = clipPolygonRect(const [
      NmPoint(-5, 2),
      NmPoint(12, 2),
      NmPoint(12, 8),
      NmPoint(-5, 8),
    ], 0, 0, 10, 10);
    expect(
        buffered.every((p) => p.e >= 0 && p.e <= 10 && p.n >= 0 && p.n <= 10),
        isTrue);
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
  final mainDb = Platform.environment['AVAREX_MAIN_DB'];

  test('New York airport names sit on JFK, Newark, and LaGuardia', () {
    final db = MbTiles(mbtilesPath: mbtiles!);
    try {
      const jfk = ChartAirport('KJFK', 40.6413, -73.7781);
      const ewr = ChartAirport('KEWR', 40.6895, -74.1745);
      const lga = ChartAirport('KLGA', 40.7769, -73.8740);
      final labels = AirspaceLabelSource(db).labels(
        north: 41.0,
        south: 40.5,
        west: -74.4,
        east: -73.5,
        centerLat: 40.70,
        centerLon: -73.94,
        tileZoom: 10,
        airports: const [jfk, ewr, lga],
        placeNamesAtAirports: true,
      );
      AirspaceMapLabel named(String ident) =>
          labels.firstWhere((label) => label.text.startsWith(ident));
      expect(
          _km(named('KJFK').point, jfk.latitude, jfk.longitude), lessThan(1));
      expect(
          _km(named('KEWR').point, ewr.latitude, ewr.longitude), lessThan(1));
      expect(
          _km(named('KLGA').point, lga.latitude, lga.longitude), lessThan(1));
      expect(
          labels.any((label) =>
              label.text.startsWith('KJFK') &&
              _km(label.point, ewr.latitude, ewr.longitude) < 5),
          isFalse);
    } finally {
      db.dispose();
    }
  },
      skip: mbtiles == null || mbtiles.isEmpty
          ? 'Set AVAREX_NASR_MBTILES to the nasr.mbtiles path'
          : false);

  test('zoomed-out labels stay on the airspace instead of the camera', () {
    final db = MbTiles(mbtilesPath: mbtiles!);
    try {
      const lat = 42.3656;
      const lon = -71.0096;
      final source = AirspaceLabelSource(db);
      final wide = source.labels(
        north: lat + 4,
        south: lat - 4,
        west: lon - 5,
        east: lon + 5,
        centerLat: lat,
        centerLon: lon,
        tileZoom: 6,
      );
      final named = wide.where((label) => label.text.contains('KBOS'));
      expect(named, isNotEmpty);
      for (final label in named) {
        expect(_km(label.point, lat, lon), lessThan(50));
      }
      expect(
          wide.any((label) =>
              label.text.contains('20-70') ||
              label.text.contains('30-70') ||
              label.text.contains('KORH')),
          isFalse);
      expect(wide.length, lessThan(41));

      const farLon = lon - 3;
      final elsewhere = source.labels(
        north: lat + 0.5,
        south: lat - 0.5,
        west: farLon - 0.5,
        east: farLon + 0.5,
        centerLat: lat,
        centerLon: farLon,
        tileZoom: 6,
      );
      expect(
          elsewhere.any((label) =>
              _km(label.point, lat, farLon) < 30 &&
              label.text.contains('KBOS')),
          isFalse);
    } finally {
      db.dispose();
    }
  },
      skip: mbtiles == null || mbtiles.isEmpty
          ? 'Set AVAREX_NASR_MBTILES to the nasr.mbtiles path'
          : false);

  test('KBOS labels stay visible when the airport is on a tile edge', () {
    final db = MbTiles(mbtilesPath: mbtiles!);
    try {
      const lat = 42.3656;
      const lon = -71.0096;
      final source = AirspaceLabelSource(db);
      final onAirport = source.labels(
        north: lat + 0.08,
        south: lat - 0.08,
        west: lon - 0.08,
        east: lon + 0.08,
        centerLat: lat,
        centerLon: lon,
        tileZoom: 9,
      );
      expect(onAirport.any((label) => label.text.contains('KBOS')), isTrue);
      expect(onAirport.any((label) => label.text.contains('SF-70')), isTrue);

      final zoomedIn = source.labels(
        north: lat + 0.008,
        south: lat - 0.008,
        west: lon - 0.008,
        east: lon + 0.008,
        centerLat: lat,
        centerLon: lon,
        tileZoom: 10,
      );
      expect(zoomedIn.any((label) => label.text.contains('SF-70')), isTrue);
      expect(
          zoomedIn.any((label) =>
              label.text.contains('20-70') || label.text.contains('30-70')),
          isFalse);
    } finally {
      db.dispose();
    }
  },
      skip: mbtiles == null || mbtiles.isEmpty
          ? 'Set AVAREX_NASR_MBTILES to the nasr.mbtiles path'
          : false);

  test('Manchester vector tiles label each sector and the airport center', () {
    final db = MbTiles(mbtilesPath: mbtiles!);
    try {
      const z = 10;
      const x = 308;
      const y = 376;
      final bytes = db.getTile(z: z, x: x, y: (1 << z) - 1 - y);
      expect(bytes, isNotNull);
      final tile =
          VectorTile.fromBytes(bytes: annotateVectorAirspaceLabels(bytes!));
      final labels = <String>[];
      for (final layer in tile.layers) {
        if (layer.name != 'class_airspace_labels') {
          continue;
        }
        for (final feature in layer.features) {
          final label = feature.decodeProperties()['LABEL']?.stringValue;
          if (label != null && label.isNotEmpty) {
            labels.add(label);
          }
        }
      }
      expect(labels.where((label) => label == '25-43').length, greaterThan(1));
      expect(labels, contains('20-43'));
      expect(
          labels.where((label) => label.startsWith('KMHT')), ['KMHT\nSF-43']);
      expect(labels.any((label) => label.contains('MANCHESTER')), isFalse);
    } finally {
      db.dispose();
    }
  },
      skip: mbtiles == null || mbtiles.isEmpty
          ? 'Set AVAREX_NASR_MBTILES to the nasr.mbtiles path'
          : false);

  test('Manchester obstacles are read from the main database', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final obstacles =
        await loadObstacles(mainDb!, const LatLng(42.9328, -71.4357));
    expect(obstacles, isNotEmpty);
    expect(
        obstacles.every(
            (obstacle) => obstacle.e.abs() <= 25 && obstacle.n.abs() <= 25),
        isTrue);
    expect(
        obstacles.every((obstacle) =>
            obstacle.label ==
            AirspaceShelf.altitudeHundreds(obstacle.heightFt)),
        isTrue);
    final tallest =
        obstacles.reduce((a, b) => a.heightFt >= b.heightFt ? a : b);
    expect(tallest.heightFt, 1548);
    expect(tallest.label, '15');
    expect(tallest.n, greaterThan(0));
    expect(tallest.e, greaterThan(0));
  },
      skip: mainDb == null || mainDb.isEmpty
          ? 'Set AVAREX_MAIN_DB to the main.db path'
          : false);
  test('Atlanta Class B is read from the vector map', () {
    final scene = loadClassAirspace(mbtiles!, const LatLng(33.6407, -84.4277));
    expect(scene.message, isNull, reason: scene.message);
    expect(scene.shelves, isNotEmpty);
    final here = scene.shelvesAtCenter.map((s) => s.label).join(', ');
    expect(
      scene.shelvesAtCenter.any((s) =>
          s.airspaceClass == 'B' && s.floorFt == 0 && s.ceilingFt == 12500),
      isTrue,
      reason: here,
    );
    expect(
      scene.shelves.every((s) =>
          s.airspaceClass == 'B' ||
          s.airspaceClass == 'C' ||
          s.airspaceClass == 'D'),
      isTrue,
    );
  },
      skip: mbtiles == null || mbtiles.isEmpty
          ? 'Set AVAREX_NASR_MBTILES to the nasr.mbtiles path'
          : false);

  test('Worcester Class D does not keep the tile-buffer column', () {
    final scene = loadClassAirspace(mbtiles!, const LatLng(42.2673, -71.8757));
    expect(scene.message, isNull, reason: scene.message);
    final visibleCuts = <double>[];
    final hiddenCuts = <double>[];
    for (final shelf in scene.shelves) {
      if (shelf.airspaceClass != 'D' ||
          shelf.floorFt != 0 ||
          shelf.ceilingFt != 3500) {
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
  },
      skip: mbtiles == null || mbtiles.isEmpty
          ? 'Set AVAREX_NASR_MBTILES to the nasr.mbtiles path'
          : false);

  test('tile seams stay hidden when the click point changes', () {
    const kpvd = LatLng(41.7240, -71.4283);
    const korh = LatLng(42.2673, -71.8757);
    final southOfKorh = LatLng(korh.latitude - 18 / 60.0, korh.longitude);
    for (final center in [kpvd, korh, southOfKorh]) {
      final scene = loadClassAirspace(mbtiles!, center);
      expect(scene.message, isNull, reason: scene.message);
      final walls = _tileSeamWalls(scene, center);
      expect(walls, isEmpty,
          reason:
              '${center.latitude},${center.longitude}: ${walls.join("; ")}');
    }
    final providence = loadClassAirspace(mbtiles!, kpvd);
    final lowShelves = providence.shelves.where((s) =>
        s.airspaceClass == 'C' && s.floorFt == 1300 && s.ceilingFt == 4100);
    expect(lowShelves.length, 1);
    expect(lowShelves.first.area, greaterThan(50));
    expect(
        lowShelves.first.rings.any((ring) => ring.points.length <= 4), isFalse);
  },
      skip: mbtiles == null || mbtiles.isEmpty
          ? 'Set AVAREX_NASR_MBTILES to the nasr.mbtiles path'
          : false);

  test('Camp Edwards restricted area and a nearby warning area are included',
      () {
    final edwards = loadClassAirspace(mbtiles!, const LatLng(41.68, -70.55));
    expect(edwards.message, isNull, reason: edwards.message);
    final restricted = edwards.shelves
        .where((shelf) => shelf.airspaceClass == 'RESTRICTED')
        .toList();
    expect(restricted, isNotEmpty);
    expect(restricted.map((shelf) => shelf.label), contains('R-4101A SF-25'));
    expect(edwards.airports.any((mark) => mark.ident == 'R-4101A'), isFalse);
    expect(edwards.shelves.where((shelf) => shelf.airspaceClass == 'WARNING'),
        isEmpty);

    final narragansett =
        loadClassAirspace(mbtiles, const LatLng(41.10, -71.20));
    expect(narragansett.message, isNull, reason: narragansett.message);
    final warning = narragansett.shelves
        .where((shelf) => shelf.airspaceClass == 'WARNING')
        .toList();
    expect(warning.map((shelf) => shelf.label), contains('W-105A SF-500'));
  },
      skip: mbtiles == null || mbtiles.isEmpty
          ? 'Set AVAREX_NASR_MBTILES to the nasr.mbtiles path'
          : false);

  test('Washington prohibited area and a MOA are included', () {
    final scene = loadClassAirspace(mbtiles!, const LatLng(38.8977, -77.0365));
    expect(scene.message, isNull, reason: scene.message);
    final labels = scene.shelves.map((shelf) => shelf.label).toList();
    expect(labels, contains('P-56A SF-180'));
    expect(labels, contains('DEMO 1 05-50'));
    expect(
        scene.shelves.any((shelf) =>
            shelf.airspaceClass == 'PROHIBITED' && shelf.ident == 'P-56A'),
        isTrue);
    expect(
        scene.shelves.any(
            (shelf) => shelf.airspaceClass == 'MOA' && shelf.ident == 'DEMO 1'),
        isTrue);
    expect(
        scene.airports
            .any((mark) => mark.ident == 'P-56A' || mark.ident == 'DEMO 1'),
        isFalse);
  },
      skip: mbtiles == null || mbtiles.isEmpty
          ? 'Set AVAREX_NASR_MBTILES to the nasr.mbtiles path'
          : false);

  test('R-5203 is clipped at 10,000 ft so it does not cover KROC', () {
    final scene = loadClassAirspace(mbtiles!, const LatLng(43.1189, -77.6724));
    expect(scene.message, isNull, reason: scene.message);
    expect(scene.maxAltitudeFt, lessThanOrEqualTo(airspaceDisplayCapFt));
    final restricted =
        scene.shelves.where((shelf) => shelf.ident == 'R-5203').toList();
    expect(restricted, isNotEmpty);
    expect(restricted.first.ceilingFt, greaterThan(airspaceDisplayCapFt));
    expect(restricted.first.label, 'R-5203 SF-500');
    expect(
        scene.shelves
            .any((shelf) => shelf.ident == 'KROC' && shelf.ceilingFt == 4600),
        isTrue);
    expect(scene.airports.any((mark) => mark.ident == 'KROC'), isTrue);
    expect(scene.airports.any((mark) => mark.ident == 'R-5203'), isFalse);
  },
      skip: mbtiles == null || mbtiles.isEmpty
          ? 'Set AVAREX_NASR_MBTILES to the nasr.mbtiles path'
          : false);

  test('Manchester Class C labels use hundreds of feet', () {
    final scene = loadClassAirspace(mbtiles!, const LatLng(42.9328, -71.4357));
    expect(scene.message, isNull, reason: scene.message);
    final lines = scene.shelves
        .where((shelf) => shelf.ident == 'KMHT')
        .map((shelf) => shelf.label)
        .toList();
    expect(lines, contains('25-43'));
    expect(lines, contains('SF-43'));
    expect(lines.any((text) => text.contains('KMHT')), isFalse);
    final airport = scene.airports.singleWhere((mark) => mark.ident == 'KMHT');
    expect(airport.airspaceClass, 'C');
    expect(airport.e.abs(), lessThan(3));
    expect(airport.n.abs(), lessThan(3));
    expect(
        scene.airports.every((mark) =>
            mark.airspaceClass == 'B' ||
            mark.airspaceClass == 'C' ||
            mark.airspaceClass == 'D'),
        isTrue);
  },
      skip: mbtiles == null || mbtiles.isEmpty
          ? 'Set AVAREX_NASR_MBTILES to the nasr.mbtiles path'
          : false);

  test('Providence Class C does not draw the tile-edge wedge', () {
    final scene = loadClassAirspace(mbtiles!, const LatLng(41.7240, -71.4283));
    expect(scene.message, isNull, reason: scene.message);
    final wedges = <String>[];
    var shelfArea = 0.0;
    for (final shelf in scene.shelves) {
      if (shelf.airspaceClass != 'C' ||
          shelf.floorFt != 1300 ||
          shelf.ceilingFt != 4100) {
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
            wedges.add(
                '(${a.e.toStringAsFixed(2)},${a.n.toStringAsFixed(2)})->(${b.e.toStringAsFixed(2)},${b.n.toStringAsFixed(2)})');
          }
        }
      }
    }
    expect(shelfArea, greaterThan(20));
    expect(wedges, isEmpty, reason: wedges.join('; '));
  },
      skip: mbtiles == null || mbtiles.isEmpty
          ? 'Set AVAREX_NASR_MBTILES to the nasr.mbtiles path'
          : false);

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

  test('TFR altitudes and the glide ring', () {
    expect(parseTfrLevel('SFC')?.feet, 0);
    expect(parseTfrLevel('SFC')?.agl, isTrue);
    expect(parseTfrLevel('050')?.feet, 5000);
    expect(parseTfrLevel('050')?.agl, isFalse);
    expect(parseTfrLevel('3000')?.feet, 3000);
    expect(parseTfrLevel('400 AGL')?.feet, 400);
    expect(parseTfrLevel('400 AGL')?.agl, isTrue);
    expect(parseTfrLevel('17999 MSL')?.feet, 17999);
    expect(parseTfrLevel('17999 MSL')?.agl, isFalse);
    expect(parseTfrLevel('0 AGL')?.agl, isTrue);
    expect(parseTfrLevel('0 MSL')?.agl, isFalse);
    expect(parseTfrLevel('UNL')?.unlimited, isTrue);
    expect(parseTfrLevel('Check NOTAMs'), isNull);
    expect(formatTfrLimit('400', 'HEI', 'FT'), '400 AGL');
    expect(formatTfrLimit('17999', 'ALT', 'FT'), '17999 MSL');
    expect(formatTfrLimit('0', 'HEI', 'FT'), '0 AGL');
    expect(formatTfrLimit('0', 'ALT', 'FT'), '0 MSL');
    expect(tfrLevelFeet(1000, agl: true, groundFt: 7664), 8664);
    expect(tfrLevelFeet(0, agl: true, groundFt: 7664), 7664);
    expect(tfrLevelFeet(1000, agl: false, groundFt: 7664), 1000);
    expect(tfrAboveScale(parseTfrLevel('15000 MSL'), 10000), isTrue);
    expect(tfrAboveScale(parseTfrLevel('17999 MSL'), 10000), isTrue);
    expect(tfrAboveScale(parseTfrLevel('1000 AGL'), 4000), isFalse);
    expect(tfrAboveScale(parseTfrLevel('0'), 4000), isFalse);
    expect(airspaceScaleAltitude(4000, [null, 6200, 9100]), 9100);
    expect(airspaceScaleAltitude(9500, [7014, 6800]), 9500);
    expect(glideRingHasReach(const [LatLng(1, 1), LatLng(1, 1)]), isFalse);
    expect(
        glideRingHasReach(
            const [LatLng(42, -71), LatLng(42.1, -71), LatLng(42, -71)]),
        isTrue);
  });

  test('surface airspace sits on terrain instead of sea level', () {
    expect(airspaceAboveGround(0, 7014), 7014);
    expect(airspaceAboveGround(8000, 7014), 8000);
    expect(airspaceAboveGround(5000, null), 5000);
    final inside = clipRingToRing(
      const [
        NmPoint(-0.5, -0.5),
        NmPoint(0.5, -0.5),
        NmPoint(0.5, 0.5),
        NmPoint(-0.5, 0.5)
      ],
      const [NmPoint(-2, -2), NmPoint(2, -2), NmPoint(2, 2), NmPoint(-2, 2)],
    );
    expect(inside.length, 4);
    final cut = clipRingToRing(
      const [NmPoint(-2, -2), NmPoint(2, -2), NmPoint(2, 2), NmPoint(-2, 2)],
      const [NmPoint(-1, -1), NmPoint(1, -1), NmPoint(1, 1), NmPoint(-1, 1)],
    );
    expect(cut.length, 4);
    for (final point in cut) {
      expect(point.e.abs(), lessThanOrEqualTo(1.01));
      expect(point.n.abs(), lessThanOrEqualTo(1.01));
    }
  });

  test('plan path is cut to the 25 NM square', () {
    final through = clipPathToView(const [NmPoint(-40, -40), NmPoint(40, 40)]);
    expect(through, hasLength(1));
    expect(through.single.first.e, closeTo(-25, 0.01));
    expect(through.single.first.n, closeTo(-25, 0.01));
    expect(through.single.last.e, closeTo(25, 0.01));
    expect(through.single.last.n, closeTo(25, 0.01));

    final around = clipPathToView(const [
      NmPoint(-40, 0),
      NmPoint(40, 0),
      NmPoint(40, 10),
      NmPoint(-40, 10),
    ]);
    expect(around, hasLength(2));
    expect(around.first.first.e, closeTo(-25, 0.01));
    expect(around.first.last.e, closeTo(25, 0.01));
    expect(around.last.first.n, closeTo(10, 0.01));
    expect(around.last.last.e, closeTo(-25, 0.01));

    expect(clipPathToView(const [NmPoint(30, 30), NmPoint(40, 40)]), isEmpty);
  });

  testWidgets('obstacles paint as part of the view', (tester) async {
    const center = LatLng(42.9328, -71.4357);
    final scene = AirspaceScene(
      radiusNm: airspaceViewRadiusNm,
      shelves: const [],
      obstacles: [
        AirspaceObstacle(e: 10, n: 14, heightFt: 1548),
        AirspaceObstacle(e: -2, n: 1, heightFt: 2049),
      ],
    );
    Airspace3DView.debugSetScene(center, scene);
    addTearDown(() => Airspace3DView.debugSetScene(center, null));

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Airspace3DView(center: center)),
    ));
    expect(find.textContaining('Drag to rotate'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('SUA'), findsOneWidget);
    expect(find.text('Terrain'), findsOneWidget);
    expect(find.text('Wind'), findsOneWidget);
    expect(find.text('Obstacles'), findsOneWidget);
    expect(find.textContaining('No Class B'), findsNothing);
    await tester.tap(find.text('Obstacles'));
    await tester.pump();
    await tester.tap(find.text('Obstacles'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('airport diagrams paint when the view has no shelves', (tester) async {
    const center = LatLng(42.0, -71.0);
    final scene = AirspaceScene(
      radiusNm: airspaceViewRadiusNm,
      shelves: const [],
      diagrams: [
        AirspaceDiagram(
          ident: 'ASH',
          at: const NmPoint(2, -1),
          runways: [
            AirspaceRunway(
              low: const NmPoint(2, -1.6),
              high: const NmPoint(2, -0.4),
              widthFt: 75,
              surface: 'ASPH',
              lowIdent: '14',
              highIdent: '32',
            ),
            AirspaceRunway(
              low: const NmPoint(1.4, -1),
              high: const NmPoint(2.6, -1),
              widthFt: 75,
              surface: 'TURF',
              lowIdent: '05',
              highIdent: '23',
            ),
          ],
        ),
      ],
    );
    Airspace3DView.debugSetScene(center, scene);
    addTearDown(() => Airspace3DView.debugSetScene(center, null));

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Airspace3DView(center: center)),
    ));
    expect(find.textContaining('Drag to rotate'), findsOneWidget);
    expect(find.textContaining('No Class B'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ownship paints inside the area and is dropped outside it',
      (tester) async {
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
          label: 'KROC SF-46',
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
              [
                NmPoint(-12, -12),
                NmPoint(12, -12),
                NmPoint(12, 12),
                NmPoint(-12, 12)
              ],
              [false, false, false, false],
            ),
          ],
          containsCenter: true,
          area: 576,
          label: 'R-5203 SF-500',
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

  testWidgets('3D view draws Atlanta shelves and accepts a drag',
      (tester) async {
    const center = LatLng(33.6407, -84.4277);
    final scene = loadClassAirspace(mbtiles!, center);
    Airspace3DView.debugSetScene(center, scene);
    addTearDown(() => Airspace3DView.debugSetScene(center, null));

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Airspace3DView(center: center)),
    ));

    expect(
        scene.shelves.any(
            (shelf) => shelf.ident == 'KATL' && shelf.label.contains('SF-125')),
        isTrue);
    expect(scene.airports.any((mark) => mark.ident == 'KATL'), isTrue);
    expect(find.textContaining('KATL'), findsNothing);
    expect(find.textContaining('Drag to rotate'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(Airspace3DView), const Offset(80, -30));
    await tester.pump();
    expect(tester.takeException(), isNull);
  }, skip: mbtiles == null || mbtiles.isEmpty);
}

double _km(LatLng point, double latitude, double longitude) {
  const radius = 6371.0;
  final dLat = (point.latitude - latitude) * math.pi / 180;
  final dLon = (point.longitude - longitude) * math.pi / 180;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(latitude * math.pi / 180) *
          math.cos(point.latitude * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}
