import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:avaremp/weather/flybrief_notams.dart';

String feature({
  required String id,
  String category = 'danger',
  String text = 'TEST NOTAM',
  bool activeNow = false,
  bool perm = false,
  String? al = 'GND',
  String? ah = 'FL032',
  List<List<double>>? polygon, // [lon,lat] ring
}) {
  final props = {
    'id': id,
    'category': category,
    'text': text,
    'raw': 'RAW $id',
    'al': al,
    'ah': ah,
    'start': '2026-07-20T06:30:00+00:00',
    'end': '2026-10-20T10:00:00+00:00',
    'schedule': '0435-1836',
    'perm': perm,
    'active_now': activeNow,
    'hp': false,
    'radius_nm': 3,
  };
  final geom = polygon == null
      ? null
      : {'type': 'Polygon', 'coordinates': [polygon]};
  return jsonEncode({'type': 'Feature', 'geometry': geom, 'properties': props});
}

String collection(List<String> feats) =>
    '{"type":"FeatureCollection","features":[${feats.join(',')}]}';

void main() {
  group('country resolution', () {
    test('forPoint picks Germany for Frankfurt', () {
      final c = FlybriefNotams.forPoint(50.03, 8.55);
      expect(c?.iso2, 'DE');
    });

    test('forPoint picks France for Paris', () {
      final c = FlybriefNotams.forPoint(48.85, 2.35);
      expect(c?.iso2, 'FR');
    });

    test('forPoint returns null for the mid-Atlantic', () {
      expect(FlybriefNotams.forPoint(30.0, -40.0), isNull);
    });

    test('byIso is case-insensitive', () {
      expect(FlybriefNotams.byIso('se')?.path, 'Sweden');
    });
  });

  group('URL building', () {
    test('notam and obstacle URLs follow the FlyBrief scheme', () {
      final c = FlybriefNotams.byIso('DE')!;
      expect(FlybriefNotams.notamUrl(c).toString(),
          'https://flybrief.app/Airspace/EU/Germany/germany_notams.geojson');
      expect(FlybriefNotams.obstacleUrl(c).toString(),
          'https://flybrief.app/Airspace/EU/Germany/germany_obstacles.geojson');
    });
  });

  group('parse', () {
    test('parses features and computes polygon centroid', () {
      final body = collection([
        feature(id: 'D1/26', polygon: [
          [8.0, 50.0],
          [8.0, 51.0],
          [9.0, 51.0],
          [9.0, 50.0],
          [8.0, 50.0],
        ]),
      ]);
      final list = FlybriefNotams.parse(body);
      expect(list.length, 1);
      final n = list.first;
      expect(n.id, 'D1/26');
      expect(n.lat, isNotNull);
      expect(n.lon, isNotNull);
      // Centroid should be inside the box.
      expect(n.lat! > 50 && n.lat! < 51, isTrue);
      expect(n.lon! > 8 && n.lon! < 9, isTrue);
    });

    test('tolerates null geometry (non-precise NOTAM)', () {
      final body = collection([feature(id: 'D2/26', polygon: null)]);
      final list = FlybriefNotams.parse(body);
      expect(list.length, 1);
      expect(list.first.lat, isNull);
    });

    test('skips features without id and malformed json', () {
      expect(FlybriefNotams.parse('not json'), isEmpty);
      final body = collection(['{"type":"Feature","properties":{}}']);
      expect(FlybriefNotams.parse(body), isEmpty);
    });
  });

  group('nearby', () {
    List<FbNotam> sample() => FlybriefNotams.parse(collection([
          // near Frankfurt (~50.0, 8.5)
          feature(id: 'NEAR', polygon: [
            [8.4, 49.9],
            [8.4, 50.1],
            [8.6, 50.1],
            [8.6, 49.9],
            [8.4, 49.9],
          ]),
          // far (Berlin ~52.5, 13.4)
          feature(id: 'FAR', polygon: [
            [13.3, 52.4],
            [13.3, 52.6],
            [13.5, 52.6],
            [13.5, 52.4],
            [13.3, 52.4],
          ]),
          // no geometry -> always included
          feature(id: 'NOGEO', polygon: null),
          // near AND active -> should sort first
          feature(id: 'ACTIVE', activeNow: true, polygon: [
            [8.45, 49.95],
            [8.45, 50.05],
            [8.55, 50.05],
            [8.55, 49.95],
            [8.45, 49.95],
          ]),
        ]));

    test('filters out far NOTAMs within radius', () {
      final near = FlybriefNotams.nearby(sample(), 50.0, 8.5, radiusNm: 50);
      final ids = near.map((e) => e.id).toSet();
      expect(ids.contains('NEAR'), isTrue);
      expect(ids.contains('ACTIVE'), isTrue);
      expect(ids.contains('NOGEO'), isTrue); // no geometry always included
      expect(ids.contains('FAR'), isFalse); // Berlin is >100 nm away
    });

    test('active NOTAMs sort before inactive', () {
      final near = FlybriefNotams.nearby(sample(), 50.0, 8.5, radiusNm: 50);
      expect(near.first.activeNow, isTrue);
    });
  });

  group('formatting', () {
    test('toLine includes id, category, active flag, altitudes and text', () {
      final n = FlybriefNotams.parse(collection([
        feature(id: 'D9/26', category: 'danger', text: 'BLASTING', activeNow: true),
      ])).first;
      final line = n.toLine();
      expect(line, contains('NOTAM D9/26'));
      expect(line, contains('[DANGER]'));
      expect(line, contains('(ACTIVE)'));
      expect(line, contains('GND'));
      expect(line, contains('FL032'));
      expect(line, contains('BLASTING'));
    });

    test('permanent NOTAM shows PERM instead of a date range', () {
      final n = FlybriefNotams.parse(collection([
        feature(id: 'P1/26', perm: true),
      ])).first;
      expect(n.toLine(), contains('PERM'));
    });
  });

  group('distance', () {
    test('distanceNm Frankfurt to Paris is ~250-300 nm', () {
      final d = FlybriefNotams.distanceNm(50.03, 8.55, 48.85, 2.35);
      expect(d, greaterThan(230));
      expect(d, lessThan(320));
    });
  });
}
