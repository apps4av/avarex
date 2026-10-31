import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:avaremp/place/airspace_3d_view.dart';
import 'package:avaremp/place/airspace_volume.dart';
import 'package:avaremp/weather/nexrad_level2.dart';
import 'package:avaremp/weather/nexrad_sites.dart';
import 'package:avaremp/weather/nexrad_volume_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// One Level II message 31 radial with a reflectivity block.
Uint8List _radial({
  required double azimuth,
  required double elevation,
  required int status,
  required int elevationNumber,
  required Uint8List ref,
  required double lat,
  required double lon,
  double scale = 2,
  double offset = 66,
}) {
  const volSize = 40;
  final refSize = 28 + ref.length;
  const pointers = 2;
  const volAt = 32 + pointers * 4;
  final refAt = volAt + volSize;
  var dataLen = refAt + refSize;
  if (dataLen.isOdd) {
    dataLen++;
  }
  final out = Uint8List(12 + 16 + dataLen);
  final d = ByteData.sublistView(out);
  d.setUint16(12, (16 + dataLen) ~/ 2);
  out[15] = 31;
  final b = 28;
  out.setRange(b, b + 4, ascii.encode('KTST'));
  d.setFloat32(b + 12, azimuth);
  out[b + 21] = status;
  out[b + 22] = elevationNumber;
  d.setFloat32(b + 24, elevation);
  d.setUint16(b + 30, pointers);
  d.setUint32(b + 32, volAt);
  d.setUint32(b + 36, refAt);
  out[b + volAt] = 0x52;
  out.setRange(b + volAt + 1, b + volAt + 4, ascii.encode('VOL'));
  d.setFloat32(b + volAt + 8, lat);
  d.setFloat32(b + volAt + 12, lon);
  d.setInt16(b + volAt + 16, 0);
  d.setUint16(b + volAt + 18, 0);
  out[b + refAt] = 0x44;
  out.setRange(b + refAt + 1, b + refAt + 4, ascii.encode('REF'));
  d.setUint16(b + refAt + 8, ref.length);
  d.setUint16(b + refAt + 10, 2000);
  d.setUint16(b + refAt + 12, 1000);
  out[b + refAt + 19] = 8;
  d.setFloat32(b + refAt + 20, scale);
  d.setFloat32(b + refAt + 24, offset);
  out.setRange(b + refAt + 28, b + refAt + 28 + ref.length, ref);
  return out;
}

/// A volume with one 0.5 degree sweep. Gates 38 to 43 (40 to 45 km) hold 32 dBZ all the way round.
Uint8List _volume({
  double lat = 35.3333,
  double lon = -97.2778,
  DateTime? at,
}) {
  final time = at ?? DateTime.utc(2026, 10, 31, 12, 0);
  final ref = Uint8List(100);
  for (var gate = 38; gate <= 43; gate++) {
    ref[gate] = 130;
  }
  final radials = BytesBuilder();
  for (var i = 0; i < 360; i++) {
    radials.add(_radial(
      azimuth: i.toDouble(),
      elevation: 0.5,
      status: i == 0 ? 3 : (i == 359 ? 2 : 1),
      elevationNumber: 1,
      ref: ref,
      lat: lat,
      lon: lon,
    ));
  }
  final compressed = Uint8List.fromList(BZip2Encoder().encode(radials.toBytes()));
  final file = BytesBuilder();
  final header = Uint8List(24);
  header.setRange(0, 12, ascii.encode('AR2V0006.001'));
  final h = ByteData.sublistView(header);
  final midnight = DateTime.utc(time.year, time.month, time.day);
  h.setUint32(12, midnight.millisecondsSinceEpoch ~/ 86400000 + 1);
  h.setUint32(16, time.difference(midnight).inMilliseconds);
  header.setRange(20, 24, ascii.encode('KTST'));
  file.add(header);
  final size = ByteData(4)..setInt32(0, compressed.length);
  file.add(size.buffer.asUint8List());
  file.add(compressed);
  return file.toBytes();
}

String _two(int v) => v.toString().padLeft(2, '0');

void main() {
  group('Level II decoder', () {
    test('reads reflectivity, site, and time', () {
      final volume = decodeNexradLevel2(_volume())!;
      expect(volume.siteId, 'KTST');
      expect(volume.latitude, closeTo(35.3333, 0.001));
      expect(volume.longitude, closeTo(-97.2778, 0.001));
      expect(volume.time, DateTime.utc(2026, 10, 31, 12, 0));
      expect(volume.sweeps, hasLength(1));
      final sweep = volume.sweeps.single;
      expect(sweep.elevationDeg, closeTo(0.5, 0.001));
      expect(sweep.radials, 360);
      // gate 40 -> 2000 + 40 * 1000 = 42 km, raw 130 -> (130 - 66) / 2
      expect(sweep.sample(90, 42500), closeTo(32, 0.01));
      expect(sweep.sample(271.3, 42500), closeTo(32, 0.01));
      expect(sweep.sample(90, 10000), NexradSweep.noEcho);
      expect(sweep.sample(90, 500000).isNaN, isTrue);
      expect(sweep.sample(90, 100).isNaN, isTrue);
    });

    test('rejects things that are not Level II', () {
      expect(decodeNexradLevel2(Uint8List(10)), isNull);
      expect(decodeNexradLevel2(Uint8List.fromList(ascii.encode('<html>nope</html> and more padding bytes'))), isNull);
    });

    test('keeps the later of two cuts at the same tilt', () {
      final ref = Uint8List(100);
      final early = Uint8List(100)..[40] = 130;
      ref[40] = 90;
      final buffer = BytesBuilder();
      for (var cut = 0; cut < 2; cut++) {
        for (var i = 0; i < 360; i++) {
          buffer.add(_radial(
            azimuth: i.toDouble(),
            elevation: 0.5,
            status: i == 0 ? 0 : 1,
            elevationNumber: cut + 1,
            ref: cut == 0 ? early : ref,
            lat: 35,
            lon: -97,
          ));
        }
      }
      final compressed =
          Uint8List.fromList(BZip2Encoder().encode(buffer.toBytes()));
      final file = BytesBuilder();
      final header = Uint8List(24);
      header.setRange(0, 12, ascii.encode('AR2V0006.001'));
      ByteData.sublistView(header).setUint32(12, 20000);
      header.setRange(20, 24, ascii.encode('KTST'));
      file.add(header);
      file.add((ByteData(4)..setInt32(0, compressed.length)).buffer.asUint8List());
      file.add(compressed);
      final volume = decodeNexradLevel2(file.toBytes())!;
      expect(volume.sweeps, hasLength(1));
      expect(volume.sweeps.single.sample(0, 42500), closeTo(12, 0.01));
    });
  });

  group('voxelizing', () {
    test('puts the echo at the beam height and nowhere else', () {
      final volume = decodeNexradLevel2(_volume(lat: 40, lon: -100))!;
      // 42.5 km east of the radar is about 22.9 NM.
      const eastNm = 42.5 / 1.852;
      final grid = voxelizeNexrad(
        [volume],
        centerLat: 40,
        centerLon: -100 + eastNm / (60 * 0.76604444),
        radiusNm: 30,
      )!;
      expect(grid.cols, 60);
      final col = 30;
      final row = 30;
      // 0.5 degrees at 42 km: about 470 m, or 1540 ft, so the 1000 to 2000 ft slab.
      expect(grid.dbz[grid.index(1, row, col)], 32);
      expect(grid.dbz[grid.index(0, row, col)], 32);
      // The beam is almost 1 degree below this height.
      expect(grid.dbz[grid.index(8, row, col)], 0);
      // Next to the radar there are no gates in this sweep, so nothing is drawn.
      expect(grid.dbz[grid.index(1, row, 0)], 0);
      expect(grid.echoTopFt, greaterThanOrEqualTo(2000));
      expect(grid.echoTopFt, lessThanOrEqualTo(5000));
      expect(grid.label, 'KTST');
    });

    test('a second radar fills a hole the first cannot see', () {
      final near = decodeNexradLevel2(_volume(lat: 40, lon: -100))!;
      // Same echo ring, but this radar sits 60 NM further east, so the ring
      // reaches the middle of the grid from the other side.
      final far = decodeNexradLevel2(_volume(lat: 40, lon: -98.6))!;
      final centerLon = -100 + 22.9 / (60 * 0.76604444);
      final one = voxelizeNexrad([near],
          centerLat: 40, centerLon: centerLon, radiusNm: 30)!;
      final two = voxelizeNexrad([near, far],
          centerLat: 40, centerLon: centerLon, radiusNm: 30)!;
      int count(NexradGrid g) => g.dbz.where((v) => v > 0).length;
      expect(count(two), greaterThan(count(one)));
    });
  });

  group('sites and listings', () {
    test('nearest radar to Boston is KBOX', () {
      final near = nexradSitesNear(42.36, -71.06, count: 2);
      expect(near.first.site.id, 'KBOX');
      expect(near.first.distanceNm, lessThan(40));
      expect(near.length, 2);
      expect(nexradSitesNear(0, 0), isEmpty);
    });

    test('volume keys skip metadata and other radars, oldest first', () {
      const xml = '''<?xml version="1.0"?>
<ListBucketResult>
 <Contents><Key>2026/10/31/KBOX/KBOX20261031_120000_V06</Key></Contents>
 <Contents><Key>2026/10/31/KBOX/KBOX20261031_121000_V06</Key></Contents>
 <Contents><Key>2026/10/31/KBOX/KBOX20261031_121000_V06_MDM</Key></Contents>
 <Contents><Key>2026/10/31/KBOX/KBOX20261031_122000_V06.gz</Key></Contents>
</ListBucketResult>''';
      expect(volumeKeys(xml, 'KBOX'), [
        '2026/10/31/KBOX/KBOX20261031_120000_V06',
        '2026/10/31/KBOX/KBOX20261031_121000_V06',
      ]);
      expect(volumeKeys(xml, 'KOKX'), isEmpty);
      expect(volumeKeys('<ListBucketResult/>', 'KBOX'), isEmpty);
      expect(volumeKeyTime('2026/10/31/KBOX/KBOX20261031_121000_V06'),
          DateTime.utc(2026, 10, 31, 12, 10));
      expect(volumeKeyTime('nonsense'), isNull);
    });
  });

  group('volume cache', () {
    final cache = NexradVolumeCache.instance;
    final original = cache.getter;
    tearDown(() {
      cache.getter = original;
      cache.debugSet();
    });

    test('downloads the newest volume and builds a grid', () async {
      final now = DateTime.now().toUtc();
      final stamp =
          '${now.year}${_two(now.month)}${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}00';
      final key =
          '${now.year}/${_two(now.month)}/${_two(now.day)}/KTLX/KTLX${stamp}_V06';
      final file = _volume(lat: 35.3333, lon: -97.2778, at: now);
      final requested = <String>[];
      cache.debugSet();
      cache.getter = (uri) async {
        requested.add(uri.toString());
        if (uri.queryParameters.containsKey('list-type')) {
          final prefix = uri.queryParameters['prefix']!;
          return http.Response(
              prefix.contains('/KTLX/')
                  ? '<ListBucketResult><Contents><Key>$key</Key></Contents></ListBucketResult>'
                  : '<ListBucketResult/>',
              200);
        }
        expect(uri.path, '/$key');
        return http.Response.bytes(file, 200);
      };

      await cache.refresh(35.4, -97.3);
      expect(cache.message, isNull);
      final grid = cache.grid!;
      expect(grid.label, 'KTST');
      expect(grid.centerLat, 35.4);
      expect(grid.dbz.any((v) => v > 0), isTrue);
      final downloads = requested.where((u) => !u.contains('list-type'));
      expect(downloads, hasLength(1));

      // Same volume and same place: nothing more is downloaded.
      await cache.refresh(35.41, -97.3);
      expect(requested.where((u) => !u.contains('list-type')), hasLength(1));
      expect(identical(cache.grid, grid), isTrue);

      // Offline keeps the picture that is already there, and the build time.
      final built = cache.builtAt!;
      expect(cache.expired, isFalse);
      expect(cache.lifeLeft!, lessThanOrEqualTo(NexradVolumeCache.buildLife));
      cache.getter = (uri) async => throw http.ClientException('offline');
      await cache.refresh(35.41, -97.3);
      expect(identical(cache.grid, grid), isTrue);
      expect(cache.builtAt, built);
      expect(cache.message, isNotNull);
      expect(cache.loading, isFalse);
    });

    test('loads the last half hour as frames and only fetches what is new',
        () async {
      final now = DateTime.now().toUtc();
      String keyAt(int minutesAgo) {
        final t = now.subtract(Duration(minutes: minutesAgo));
        return '${t.year}/${_two(t.month)}/${_two(t.day)}/KTLX/KTLX${t.year}${_two(t.month)}${_two(t.day)}_${_two(t.hour)}${_two(t.minute)}${_two(t.second)}_V06';
      }

      // 50 min ago is never in the loop. 32 is in it until the 1 minute volume arrives.
      final listed = <int>[50, 32, 26, 21, 15, 9, 3];
      final files = <String, Uint8List>{};
      for (final ago in [50, 32, 26, 21, 15, 9, 3, 1]) {
        files[keyAt(ago)] = _volume(
            lat: 35.3333,
            lon: -97.2778,
            at: now.subtract(Duration(minutes: ago)));
      }
      final downloads = <String>[];
      cache.debugSet();
      cache.getter = (uri) async {
        if (uri.queryParameters.containsKey('list-type')) {
          final prefix = uri.queryParameters['prefix']!;
          if (!prefix.contains('/KTLX/')) {
            return http.Response('<ListBucketResult/>', 200);
          }
          final body = listed
              .map((ago) => '<Contents><Key>${keyAt(ago)}</Key></Contents>')
              .join();
          return http.Response('<ListBucketResult>$body</ListBucketResult>', 200);
        }
        downloads.add(uri.path.substring(1));
        return http.Response.bytes(files[uri.path.substring(1)]!, 200);
      };

      await cache.refresh(35.4, -97.3);
      expect(cache.frames, hasLength(6));
      expect(downloads, hasLength(6));
      // Newest was fetched first, and the frames are in time order.
      expect(downloads.first, keyAt(3));
      for (var i = 1; i < cache.frames.length; i++) {
        expect(cache.frames[i].time.isAfter(cache.frames[i - 1].time), isTrue);
      }
      expect(identical(cache.grid, cache.frames.last), isTrue);

      // A new volume arrives: one download, and the oldest drops out of the half hour.
      listed.add(1);
      await cache.refresh(35.4, -97.3);
      expect(downloads, hasLength(7));
      expect(downloads.last, keyAt(1));
      expect(cache.frames, hasLength(6));
      expect(cache.frames.last.time.difference(cache.frames.first.time),
          lessThanOrEqualTo(NexradVolumeCache.loopLength));
    });

    test('a build expires after ten minutes', () {
      final now = DateTime.now();
      cache.debugSet(builtAt: now.subtract(const Duration(minutes: 4)));
      expect(cache.expired, isFalse);
      expect(cache.lifeLeft!.inMinutes, inInclusiveRange(5, 6));
      cache.debugSet(builtAt: now.subtract(const Duration(minutes: 11)));
      expect(cache.expired, isTrue);
      expect(cache.lifeLeft, Duration.zero);
      cache.debugSet();
      expect(cache.expired, isFalse);
      expect(cache.lifeLeft, isNull);
    });

    test('says so when no radar is in range', () async {
      cache.debugSet();
      cache.getter = (uri) async => throw StateError('no network needed');
      await cache.refresh(0, 0);
      expect(cache.grid, isNull);
      expect(cache.message, contains('No NEXRAD radar'));
    });

    test('a radar with no recent volume is skipped', () async {
      cache.debugSet();
      cache.getter = (uri) async => http.Response(
          '<ListBucketResult><Contents><Key>2020/01/01/KTLX/KTLX20200101_000000_V06</Key></Contents></ListBucketResult>',
          200);
      await cache.refresh(35.4, -97.3);
      expect(cache.grid, isNull);
      expect(cache.message, contains('No recent radar'));
    });
  });

  group('3D Weather view', () {
    Future<void> open(WidgetTester tester, NexradGrid? grid) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1000, 800);
      addTearDown(tester.view.reset);
      final cache = NexradVolumeCache.instance;
      final original = cache.getter;
      cache.getter = (uri) async => throw http.ClientException('offline');
      addTearDown(() {
        cache.getter = original;
        cache.debugSet();
      });
      cache.debugSet(grid: grid);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Airspace3DView(
                weather: true, center: LatLng(35.4, -97.3), showTerrain: true)),
      ));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('shows winds and the wind legend at once, radar waits for the button',
        (tester) async {
      await open(tester, null);
      expect(find.text('Winds aloft'), findsOneWidget);
      expect(find.text('60+ kt'), findsOneWidget);
      expect(find.text('Build NEXRAD'), findsOneWidget);
      expect(find.text('dBZ 20+'), findsOneWidget);
      // Radar is not built, so no radar legend and nothing was requested.
      expect(find.text('10'), findsNothing);
      expect(NexradVolumeCache.instance.loading, isFalse);
      // None of the airspace chips.
      for (final chip in ['B', 'C', 'D', 'SUA', 'TFR', 'Plan', 'Obstacles', 'Terrain']) {
        expect(find.text(chip), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Build NEXRAD shows the radar legend and plays the loop',
        (tester) async {
      final volume = decodeNexradLevel2(_volume(lat: 35.3333, lon: -97.2778))!;
      final grid = voxelizeNexrad([volume],
          centerLat: 35.4, centerLon: -97.3)!;
      await open(tester, grid);
      await tester.tap(find.text('Build NEXRAD'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Hide NEXRAD'), findsOneWidget);
      expect(find.text('70 dBZ'), findsOneWidget);
      expect(find.text('Winds aloft'), findsOneWidget);

      // Two frames: the loop plays, and pause stops it on the shown frame.
      final older = NexradGrid(
        label: grid.label,
        time: grid.time.subtract(const Duration(minutes: 10)),
        centerLat: grid.centerLat,
        centerLon: grid.centerLon,
        radiusNm: grid.radiusNm,
        cellNm: grid.cellNm,
        levelFt: grid.levelFt,
        cols: grid.cols,
        levels: grid.levels,
        dbz: grid.dbz,
        echoTopFt: grid.echoTopFt,
      );
      NexradVolumeCache.instance.debugSet(frames: [older, grid]);
      await tester.pump();
      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.textContaining('-10 min'), findsNothing);
      // It rests on the newest frame a few steps, then wraps to the oldest.
      await tester.pump(const Duration(milliseconds: 2700));
      expect(find.textContaining('-10 min'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.textContaining('-10 min'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      await tester.drag(find.byType(CustomPaint).first, const Offset(60, 20));
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Hide NEXRAD'));
      await tester.pump();
      expect(find.text('Build NEXRAD'), findsOneWidget);
      expect(find.text('70 dBZ'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('radar is a snapshot: it shows when it was built and never updates itself',
        (tester) async {
      final volume = decodeNexradLevel2(_volume(lat: 35.3333, lon: -97.2778))!;
      final grid = voxelizeNexrad([volume], centerLat: 35.4, centerLon: -97.3)!;
      await open(tester, grid);
      var requests = 0;
      NexradVolumeCache.instance.getter = (uri) async {
        requests++;
        throw http.ClientException('offline');
      };
      NexradVolumeCache.instance.debugSet(
          grid: grid, builtAt: DateTime.now().subtract(const Duration(minutes: 2)));
      await tester.tap(find.text('Build NEXRAD'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Built '), findsOneWidget);
      expect(find.textContaining('rebuild in 8 min'), findsOneWidget);
      expect(requests, 1);

      // Minutes pass with the radar on: no further requests.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 10));
      }
      expect(requests, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('after ten minutes the radar hides until it is rebuilt',
        (tester) async {
      final volume = decodeNexradLevel2(_volume(lat: 35.3333, lon: -97.2778))!;
      final grid = voxelizeNexrad([volume], centerLat: 35.4, centerLon: -97.3)!;
      await open(tester, grid);
      NexradVolumeCache.instance.debugSet(
          grid: grid, builtAt: DateTime.now().subtract(const Duration(minutes: 9)));
      await tester.tap(find.text('Build NEXRAD'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Hide NEXRAD'), findsOneWidget);

      // Real time does not move in the test, so age the build instead.
      NexradVolumeCache.instance.debugSet(
          grid: grid, builtAt: DateTime.now().subtract(const Duration(minutes: 11)));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 10));
      }
      expect(find.text('Hide NEXRAD'), findsNothing);
      expect(find.text('Rebuild NEXRAD'), findsOneWidget);
      expect(find.textContaining('10 min old'), findsOneWidget);
      expect(find.text('70 dBZ'), findsNothing);

      // Rebuilding brings it back with a fresh timestamp.
      NexradVolumeCache.instance.getter = (uri) async => throw http.ClientException('offline');
      await tester.tap(find.text('Rebuild NEXRAD'));
      await tester.pump();
      expect(find.text('Hide NEXRAD'), findsOneWidget);
      expect(find.textContaining('10 min old'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('dBZ setting changes the weakest echo shown', (tester) async {
      await open(tester, null);
      await tester.tap(find.text('dBZ 20+'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('heavy rain'), findsOneWidget);
      await tester.tap(find.textContaining('heavy rain'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('dBZ 40+'), findsOneWidget);
      await tester.tap(find.text('dBZ 40+'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.textContaining('light rain'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('dBZ 20+'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the plain 3D view has no wind or radar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1800, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const center = LatLng(35.4, -97.3);
      Airspace3DView.debugSetScene(center,
          const AirspaceScene(radiusNm: airspaceViewRadiusNm, shelves: []));
      addTearDown(() => Airspace3DView.debugSetScene(center, null));
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Airspace3DView(center: center, followAircraft: true)),
      ));
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Airspace3DView(center: center)),
      ));
      await tester.pump();
      expect(find.text('Wind'), findsNothing);
      expect(find.text('Radar'), findsNothing);
      expect(find.text('Winds aloft'), findsNothing);
      expect(find.text('Build NEXRAD'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
