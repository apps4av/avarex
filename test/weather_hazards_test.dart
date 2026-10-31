import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:avaremp/place/airspace_3d_view.dart';
import 'package:avaremp/place/airspace_volume.dart';
import 'package:avaremp/weather/dafs_cache.dart';
import 'package:avaremp/weather/grib2.dart';
import 'package:avaremp/weather/hdf5_lite.dart';
import 'package:avaremp/weather/lightning_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// A GRIB2 message with one field, simple packing, on a Lambert grid like NOAA's 3 km one.
/// [values] are row-major from the south west corner. NaN becomes "no value" through a bitmap.
Uint8List _grib({
  required int ni,
  required int nj,
  required List<double> values,
  double firstLat = 33.0,
  double firstLon = -100.5,
  int category = 19,
  int number = 37,
  int levelMeters = 3048,
  int forecastHours = 1,
  int decimal = 0,
  int gridTemplate = 30,
  int packingTemplate = 0,
}) {
  final out = BytesBuilder();
  void u8(List<int> into, int v) => into.add(v & 0xff);
  List<int> be(int v, int n) =>
      [for (var i = n - 1; i >= 0; i--) (v >> (8 * i)) & 0xff];
  // Signed fields in GRIB use a sign bit, not two's complement.
  int sm(int v, int n) => v < 0 ? ((-v) | (1 << (n * 8 - 1))) : v;

  final hasMissing = values.any((v) => v.isNaN);
  final present = values.where((v) => !v.isNaN).toList();
  final scale = math.pow(10, decimal).toDouble();
  final scaled = [for (final v in present) (v * scale).round()];
  final minimum = scaled.isEmpty ? 0 : scaled.reduce(math.min);
  final range = scaled.isEmpty ? 0 : scaled.reduce(math.max) - minimum;
  final bits = range == 0 ? 0 : (range.bitLength);

  final s1 = <int>[
    ...be(21, 4), 1, ...be(7, 2), ...be(0, 2), 2, 0, 1,
    ...be(2026, 2), 10, 31, 14, 0, 0, 0, 1,
  ];
  final s3 = <int>[
    ...be(81, 4), 3, 0, ...be(ni * nj, 4), 0, 0, ...be(gridTemplate, 2),
    6, 0, ...be(0, 4), 0, ...be(0, 4), 0, ...be(0, 4),
    ...be(ni, 4), ...be(nj, 4),
    ...be(sm((firstLat * 1e6).round(), 4), 4),
    ...be((((firstLon + 360) % 360) * 1e6).round(), 4),
    0x30,
    ...be(sm((38.5 * 1e6).round(), 4), 4),
    ...be((262.5 * 1e6).round(), 4),
    ...be(3000000, 4), ...be(3000000, 4),
    0, 64,
    ...be(sm((38.5 * 1e6).round(), 4), 4),
    ...be(sm((38.5 * 1e6).round(), 4), 4),
    ...be(sm(-90 * 1000000, 4), 4), ...be(0, 4),
  ];
  final s4 = <int>[
    ...be(34, 4), 4, ...be(0, 2), ...be(0, 2), category, number,
    2, 0, 0, ...be(0, 2), 0, 1, ...be(forecastHours, 4),
    102, 0, ...be(levelMeters, 4), 255, 0, ...be(0, 4),
  ];
  final s5 = <int>[
    ...be(21, 4), 5, ...be(present.length, 4), ...be(packingTemplate, 2),
    ...(Uint8List(4)..buffer.asByteData().setFloat32(0, minimum.toDouble())),
    ...be(0, 2), ...be(sm(decimal, 2), 2), bits, 0,
  ];
  final bitmap = <int>[];
  if (hasMissing) {
    for (var i = 0; i < values.length; i += 8) {
      var byte = 0;
      for (var b = 0; b < 8 && i + b < values.length; b++) {
        if (!values[i + b].isNaN) {
          byte |= 0x80 >> b;
        }
      }
      bitmap.add(byte);
    }
  }
  final s6 = <int>[...be(6 + bitmap.length, 4), 6, hasMissing ? 0 : 255, ...bitmap];
  final packed = <int>[];
  var acc = 0;
  var accBits = 0;
  for (final v in scaled) {
    acc = (acc << bits) | (v - minimum);
    accBits += bits;
    while (accBits >= 8) {
      packed.add((acc >> (accBits - 8)) & 0xff);
      accBits -= 8;
    }
    acc &= (1 << accBits) - 1;
  }
  if (accBits > 0) {
    packed.add((acc << (8 - accBits)) & 0xff);
  }
  final s7 = <int>[...be(5 + packed.length, 4), 7, ...packed];

  final body = [...s1, ...s3, ...s4, ...s5, ...s6, ...s7];
  final total = 16 + body.length + 4;
  u8(<int>[], 0);
  out.add([0x47, 0x52, 0x49, 0x42, 0, 0, 0, 2, ...be(total, 8)]);
  out.add(body);
  out.add([0x37, 0x37, 0x37, 0x37]);
  return out.toBytes();
}

String _idxLine(int n, int offset, String parameter, String level) =>
    '$n:$offset:d=2026103114:$parameter:$level:1 hour fcst:';

String _meters(double m) {
  final text = m.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// An index like the one NOMADS serves for the icing file: ICPRB, SIPD, then the severity.
String _iceIndex() {
  final lines = <String>[];
  var n = 1;
  for (final name in ['ICPRB', 'SIPD', 'var discipline=0 master_table=2 parmcat=19 parm=37']) {
    for (var k = 1; k <= 60; k++) {
      lines.add(_idxLine(n, n * 1000, name, '${_meters(152.4 * k)} m above mean sea level'));
      n++;
    }
  }
  return lines.join('\n');
}

/// The turbulence file starts with a column maximum, then EDPARM at many heights.
String _turbIndex() {
  final lines = <String>[_idxLine(1, 0, 'MXEDPRM', 'entire atmosphere')];
  var n = 2;
  final heights = [30, ...[for (var k = 1; k <= 50; k++) (k * 304.8).truncate()]];
  for (final name in ['EDPARM', 'CATEDR']) {
    for (final m in heights) {
      lines.add(_idxLine(n, n * 1000, name, '$m m above mean sea level'));
      n++;
    }
  }
  return lines.join('\n');
}

String _glmKey(DateTime t, {String satellite = 'G19'}) {
  String two(int v) => v.toString().padLeft(2, '0');
  final doy = t.difference(DateTime.utc(t.year)).inDays + 1;
  final stamp = '${t.year}${doy.toString().padLeft(3, '0')}${two(t.hour)}${two(t.minute)}${two(t.second)}';
  return 'GLM-L2-LCFA/${t.year}/${doy.toString().padLeft(3, '0')}/${two(t.hour)}/'
      'OR_GLM-L2-LCFA_${satellite}_s${stamp}0_e${stamp}2_c${stamp}3.nc';
}

String _listing(Iterable<String> keys) =>
    '<ListBucketResult>${keys.map((k) => '<Contents><Key>$k</Key></Contents>').join()}</ListBucketResult>';

void main() {
  group('GRIB2', () {
    test('reads a real NOAA icing message', () {
      final messages = readGrib2(File('test/data/ice_fl280.grib2').readAsBytesSync());
      expect(messages, hasLength(1));
      final m = messages.single;
      expect(m.discipline, 0);
      expect(m.category, 19);
      expect(m.number, 37);
      expect(m.levelType, 102);
      expect(m.level, closeTo(8534.4, 0.1));
      expect(m.forecastHours, 1);
      expect(m.validTime, DateTime.utc(2026, 10, 31, 15));
      expect(m.grid.ni, 1799);
      expect(m.grid.nj, 1059);
      expect(m.values, hasLength(1799 * 1059));
      var sum = 0.0;
      var lightOrWorse = 0;
      for (final v in m.values) {
        sum += v;
        if (v >= 2) {
          lightOrWorse++;
        }
      }
      // Totals and spot values taken from the same file read with pygrib.
      expect(sum, 12530);
      expect(lightOrWorse, 1997);
      expect(m.sample(24.652095864630464, -88.86016619918604, nearest: true), 4);
      expect(m.sample(23.68755498775815, -123.29948304249886, nearest: true), 3);
      expect(m.sample(27.718916895795815, -91.83872677991647, nearest: true), 3);
      expect(m.sample(24.944667818294768, -117.92319009348626, nearest: true), 0);
      expect(m.sample(60, -100).isNaN, isTrue);
      expect(m.sample(35, -20).isNaN, isTrue);
    });

    test('simple packing, decimal scale, and a bitmap', () {
      final values = <double>[
        for (var j = 0; j < 40; j++)
          for (var i = 0; i < 50; i++)
            i == 3 && j == 4 ? double.nan : (i + j * 50) / 1000.0,
      ];
      final message = readGrib2(_grib(ni: 50, nj: 40, values: values, decimal: 3,
          category: 19, number: 30, levelMeters: 914)).single;
      expect(message.number, 30);
      expect(message.level, 914);
      expect(message.values[4 * 50 + 3].isNaN, isTrue);
      expect(message.values[0], 0);
      expect(message.values[1999], closeTo(1.999, 1e-6));
      expect(message.values[123], closeTo(0.123, 1e-6));
    });

    test('maps places to grid cells', () {
      final values = [for (var i = 0; i < 50 * 40; i++) i.toDouble() % 7];
      final message = readGrib2(_grib(ni: 50, nj: 40, values: values)).single;
      // The first point is where the header says it is.
      final first = message.grid.index(33.0, -100.5);
      expect(first.$1, closeTo(0, 1e-6));
      expect(first.$2, closeTo(0, 1e-6));
      // A place 30 km east and 15 km north lands 10 columns and 5 rows over.
      final east = message.grid.index(33.0, -100.5);
      expect(east.$1, 0);
      final far = message.grid.index(33.25, -100.2);
      expect(far.$1, greaterThan(5));
      expect(far.$2, greaterThan(5));
    });

    test('refuses what it cannot read', () {
      expect(() => readGrib2(_grib(ni: 4, nj: 4, values: List.filled(16, 1), gridTemplate: 0)),
          throwsFormatException);
      expect(() => readGrib2(_grib(ni: 4, nj: 4, values: List.filled(16, 1), packingTemplate: 40)),
          throwsFormatException);
      final good = _grib(ni: 4, nj: 4, values: List.filled(16, 1));
      expect(() => readGrib2(Uint8List.sublistView(good, 0, good.length - 30)),
          throwsFormatException);
    });
  });

  group('NetCDF4 reader and lightning', () {
    late Uint8List sample;
    setUpAll(() {
      sample = File('test/data/glm_flashes.nc').readAsBytesSync();
    });

    test('reads chunked, shuffled, compressed variables', () {
      final file = Hdf5Lite(sample);
      final lat = file.vector('flash_lat')!;
      final lon = file.vector('flash_lon')!;
      // 2100 values: more than one 2048 value chunk. Values written with h5py.
      expect(lat, hasLength(2100));
      expect(lon, hasLength(2100));
      expect(lat[0], closeTo(35.171, 1e-4));
      expect(lat[1], closeTo(35.474, 1e-4));
      expect(lat[2], closeTo(36.603, 1e-4));
      expect(lon[0], closeTo(-97.245, 1e-4));
      expect(lat[2099], closeTo(35.642, 1e-4));
      expect(lon[2099], closeTo(-96.913, 1e-4));
      expect(lat.reduce((a, b) => a + b), closeTo(75580.23, 0.5));
      expect(file.vector('other_3')!.toList(), [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
      expect(file.vector('empty_lat'), isEmpty);
      expect(file.vector('no_such_variable'), isNull);
    });

    test('rejects files that are not HDF5', () {
      expect(() => Hdf5Lite(Uint8List(100)), throwsFormatException);
      expect(() => Hdf5Lite(Uint8List(10)), throwsFormatException);
    });

    test('keeps flashes inside the radius', () {
      final all = decodeGlmFlashes(sample, 36, -97, radiusNm: 500);
      expect(all, hasLength(4200));
      final near = decodeGlmFlashes(sample, 36, -97, radiusNm: 30);
      expect(near.length, lessThan(all.length));
      expect(near, isNotEmpty);
      for (var i = 0; i < near.length; i += 2) {
        final north = (near[i] - 36) * 60;
        final east = (near[i + 1] + 97) * 60 * math.cos(36 * math.pi / 180);
        expect(math.sqrt(north * north + east * east), lessThanOrEqualTo(30.001));
      }
      expect(() => decodeGlmFlashes(Uint8List(50), 36, -97), throwsFormatException);
    });

    test('reads file times, and picks the satellite by longitude', () {
      const key =
          'GLM-L2-LCFA/2026/304/15/OR_GLM-L2-LCFA_G19_s20263041500200_e20263041500400_c20263041500419.nc';
      expect(glmKeyTime(key), DateTime.utc(2026, 10, 31, 15, 0, 20));
      expect(glmKeyTime('nope'), isNull);
      expect(satelliteFor(-80).name, 'GOES-19');
      expect(satelliteFor(-118).name, 'GOES-18');
      final since = DateTime.utc(2026, 10, 31, 15, 0, 10);
      final keys = glmKeys(_listing([
        key,
        'GLM-L2-LCFA/2026/304/15/OR_GLM-L2-LCFA_G19_s20263041500000_e20263041500200_c20263041500218.nc',
      ]), since);
      expect(keys, [key]);
    });

    group('cache', () {
      final cache = LightningCache.instance;
      tearDown(() => cache.debugSet());

      test('builds the last ten minutes from the newest files', () async {
        final now = DateTime.now().toUtc();
        final fresh = [
          for (final minutes in [1, 3, 8])
            _glmKey(now.subtract(Duration(minutes: minutes)))
        ];
        final old = _glmKey(now.subtract(const Duration(minutes: 15)));
        final fetched = <String>[];
        cache.getter = (uri) async {
          if (uri.queryParameters.containsKey('list-type')) {
            final prefix = uri.queryParameters['prefix']!;
            return http.Response(
                _listing([...fresh, old].where((k) => k.startsWith(prefix))), 200);
          }
          fetched.add(uri.path.substring(1));
          return http.Response.bytes(sample, 200);
        };
        await cache.refresh(36, -97);
        expect(cache.message, isNull);
        expect(cache.hasPicture, isTrue);
        expect(cache.expired, isFalse);
        expect(cache.progress, isNull);
        expect(fetched.toSet(), fresh.toSet());
        final perFile = decodeGlmFlashes(sample, 36, -97).length ~/ 2;
        expect(perFile, greaterThan(100));
        expect(cache.flashes, hasLength(perFile * 3));
        expect(cache.satellite, 'GOES-19');
        // Flashes carry the time of their file, oldest first.
        expect(cache.flashes.first.time.isBefore(cache.flashes.last.time), isTrue);
        expect(cache.needsRegrid(36.1, -97.1), isFalse);
        expect(cache.needsRegrid(37, -97), isTrue);
      });

      test('a quiet sky is still a build', () async {
        cache.getter = (uri) async => http.Response(_listing(const []), 200);
        await cache.refresh(36, -97);
        expect(cache.hasPicture, isTrue);
        expect(cache.flashes, isEmpty);
        expect(cache.message, isNull);
      });

      test('says so when there is no connection', () async {
        cache.getter = (uri) async => throw http.ClientException('offline');
        await cache.refresh(36, -97);
        expect(cache.hasPicture, isFalse);
        expect(cache.message, contains('Lightning unavailable'));
        cache.getter = (uri) async => http.Response('', 503);
        await cache.refresh(36, -97);
        expect(cache.message, contains('Lightning unavailable'));
      });

      test('files that cannot be read are a failed download', () async {
        final now = DateTime.now().toUtc();
        final key = _glmKey(now.subtract(const Duration(minutes: 2)));
        cache.getter = (uri) async {
          if (uri.queryParameters.containsKey('list-type')) {
            return http.Response(
                _listing([key].where((k) => k.startsWith(uri.queryParameters['prefix']!))), 200);
          }
          return http.Response.bytes(Uint8List(2000), 200);
        };
        await cache.refresh(36, -97);
        expect(cache.hasPicture, isFalse);
        expect(cache.message, contains('failed'));
      });

      test('a build expires after ten minutes', () {
        cache.debugSet(builtAt: DateTime.now().subtract(const Duration(minutes: 11)));
        expect(cache.expired, isTrue);
        cache.debugSet(builtAt: DateTime.now().subtract(const Duration(minutes: 4)));
        expect(cache.expired, isFalse);
        expect(cache.lifeLeft!.inMinutes, inInclusiveRange(5, 6));
      });
    });
  });

  group('icing and turbulence', () {
    test('reads the index file and gives each message its byte range', () {
      final index = parseDafsIndex(_turbIndex());
      // The column maximum has no height, so it is never picked.
      expect(index.first.meters.isNaN, isTrue);
      expect(index[1].start, 2000);
      expect(index[1].end, 3000);
      expect(index.last.end, isNull);
      expect(parseDafsIndex('garbage\n\n'), isEmpty);
    });

    test('picks icing every 1000 ft and turbulence at its own heights', () {
      final ice = pickLevels(parseDafsIndex(_iceIndex()), Hazard.icing);
      expect(ice, hasLength(30));
      expect(ice.map((l) => l.feet), [for (var k = 1; k <= 30; k++) k * 1000]);
      expect(ice.every((l) => l.parameter.contains('parm=37')), isTrue);
      final turb = pickLevels(parseDafsIndex(_turbIndex()), Hazard.turbulence);
      expect(turb.map((l) => l.feet), DafsCache.turbulenceFeet);
      expect(turb.every((l) => l.parameter == 'EDPARM'), isTrue);
      // 304 m is the 1000 ft message, 914 m the 3000 ft one.
      expect(turb.first.meters, 304);
      expect(turb[1].meters, 914);
    });

    test('forecast files are named like the NOAA ones', () {
      expect(forecastUrl(DateTime.utc(2026, 10, 31, 4), 'ifi', 1),
          'https://nomads.ncep.noaa.gov/pub/data/nccf/com/dafs/prod/dafs.20261031/dafs.t04z.ifi.3km.conus.f001.grib2');
      expect(forecastUrl(DateTime.utc(2026, 1, 2, 23), 'gtg', 12),
          endsWith('dafs.20260102/dafs.t23z.gtg.3km.conus.f012.grib2'));
    });

    test('cuts a level out of the grid around a place', () {
      // A block of moderate icing and one of EDR 0.35 around the middle of the grid.
      final ni = 140;
      final nj = 140;
      final ice = [
        for (var j = 0; j < nj; j++)
          for (var i = 0; i < ni; i++) (i >= 60 && i < 80 && j >= 60 && j < 80) ? 3.0 : 0.0
      ];
      final message = readGrib2(_grib(ni: ni, nj: nj, values: ice)).single;
      final at = message.grid; // block center
      // Find the lat/lon of cell (70, 70) by searching the first point outward.
      final cell = at.index(33.0, -100.5);
      expect(cell.$1, closeTo(0, 1e-6));
      // 70 cells of 3 km is 210 km, about 113 NM, north east of the first point.
      // Use a center so the block sits at the middle of the 120 NM grid.
      double lat = 33.0, lon = -100.5;
      for (var step = 0; step < 200; step++) {
        final here = at.index(lat, lon);
        lat += (70 - here.$2) * 3 / 111.2;
        lon += (70 - here.$1) * 3 / (111.2 * math.cos(lat * math.pi / 180));
      }
      final cut = cutLevel(_grib(ni: ni, nj: nj, values: ice), lat, lon, categories: true);
      expect(cut, hasLength(60 * 60));
      // The block is 20 cells of 3 km, about 32 NM across: about 16 of the 2 NM cells.
      expect(cut[30 * 60 + 30], 3);
      expect(cut[0], 0);
      final count = cut.where((v) => v == 3).length;
      expect(count, inInclusiveRange(200, 300));

      final edr = [for (var i = 0; i < ni * nj; i++) 0.35];
      final turb = cutLevel(
          _grib(ni: ni, nj: nj, values: edr, decimal: 2, number: 30), lat, lon,
          categories: false);
      expect(turb[30 * 60 + 30], 35);
      // No value under the bitmap means calm, not a hole.
      final holes = [for (var i = 0; i < ni * nj; i++) i % 2 == 0 ? double.nan : 0.4];
      final masked = cutLevel(
          _grib(ni: ni, nj: nj, values: holes, decimal: 2, number: 30), lat, lon,
          categories: false);
      expect(masked.every((v) => v == 0 || v == 40), isTrue);
    });

    test('puts the levels on the 1000 ft grid', () {
      Uint8List flat(int v) => Uint8List(3600)..fillRange(0, 3600, v);
      final turb = buildHazardGrid(
        hazard: Hazard.turbulence,
        slices: {1000: flat(10), 3000: flat(30), 6000: flat(60)},
        validTime: DateTime.utc(2026, 10, 31, 15),
        centerLat: 36,
        centerLon: -97,
      );
      expect(turb.levels, 30);
      expect(turb.cols, 60);
      int at(int level) => turb.values[level * 3600 + 1830];
      expect(at(0), 10); // 1000 ft
      expect(at(1), 20); // 2000 ft, between 1000 and 3000
      expect(at(2), 30);
      expect(at(3), 40); // 4000 ft
      expect(at(4), 50);
      expect(at(5), 60);
      expect(at(6), 60); // above the last level: nothing to blend toward
      expect(turb.firstLevelFt, 1000);

      final ice = buildHazardGrid(
        hazard: Hazard.icing,
        slices: {1000: flat(2), 3000: flat(4)},
        validTime: DateTime.utc(2026, 10, 31, 15),
        centerLat: 36,
        centerLon: -97,
      );
      // Severity codes are never blended: a level that was not downloaded is clear.
      expect(ice.values[0 * 3600 + 5], 2);
      expect(ice.values[1 * 3600 + 5], 0);
      expect(ice.values[2 * 3600 + 5], 4);
      expect(ice.topFt(2), 3000 + 500);
      expect(ice.topFt(5), 0);
    });

    group('cache', () {
      Uint8List fieldAround(double lat, double lon, {required bool ice}) {
        // A grid centered near the requested place: everything is 3 (ice) or EDR 0.30.
        final value = ice ? 3.0 : 0.30;
        return _grib(
          ni: 160,
          nj: 160,
          values: List.filled(160 * 160, value),
          decimal: ice ? 0 : 2,
          number: ice ? 37 : 30,
          firstLat: lat - 1.5,
          firstLon: lon - 1.9,
        );
      }

      for (final hazard in Hazard.values) {
        final isIce = hazard == Hazard.icing;
        final cache = isIce ? DafsCache.icing : DafsCache.turbulence;
        test('${hazard.name}: downloads only the levels it shows, newest cycle first', () async {
          final requests = <String>[];
          final ranges = <String>[];
          final body = fieldAround(36, -97, ice: isIce);
          cache.getter = (uri, {String? range}) async {
            requests.add(uri.path.split('/').last);
            if (uri.path.endsWith('.idx')) {
              // The newest cycle has not been published yet.
              if (requests.length == 1) {
                return http.Response('', 404);
              }
              return http.Response(isIce ? _iceIndex() : _turbIndex(), 200);
            }
            ranges.add(range!);
            return http.Response.bytes(body, 206);
          };
          await cache.refresh(36, -97);
          expect(cache.message, isNull, reason: cache.message);
          expect(cache.hasPicture, isTrue);
          expect(cache.progress, isNull);
          expect(cache.expired, isFalse);
          final expected = isIce ? 30 : DafsCache.turbulenceFeet.length;
          expect(ranges, hasLength(expected));
          expect(ranges.every((r) => r.startsWith('bytes=')), isTrue);
          // Two index requests: the first cycle was missing.
          expect(requests.where((r) => r.endsWith('.idx')), hasLength(2));
          final grid = cache.grid!;
          expect(grid.hazard, hazard);
          final now = DateTime.now().toUtc();
          expect(grid.validTime.difference(now).inMinutes.abs(), lessThan(90));
          final probe = grid.values[10 * 3600 + 30 * 60 + 30];
          expect(probe, isIce ? 3 : 30);
          expect(cache.needsRegrid(36.1, -97.1), isFalse);
          expect(cache.needsRegrid(37.5, -97), isTrue);
          expect(DafsCache.buildLife, const Duration(minutes: 60));
        });

        test('${hazard.name}: says so when no forecast can be found', () async {
          cache.debugSet();
          cache.getter = (uri, {String? range}) async => http.Response('', 404);
          await cache.refresh(36, -97);
          expect(cache.hasPicture, isFalse);
          expect(cache.message, contains('forecast found'));
          cache.getter = (uri, {String? range}) async => throw http.ClientException('offline');
          await cache.refresh(36, -97);
          expect(cache.message, contains('check the connection'));
        });
      }

      test('a place outside the continental US says so', () async {
        final cache = DafsCache.turbulence;
        cache.debugSet();
        final body = fieldAround(36, -97, ice: false);
        cache.getter = (uri, {String? range}) async => uri.path.endsWith('.idx')
            ? http.Response(_turbIndex(), 200)
            : http.Response.bytes(body, 206);
        await cache.refresh(64.8, -147.7);
        expect(cache.hasPicture, isFalse);
        expect(cache.message, contains('continental US'));
        expect(cutLevel(body, 64.8, -147.7, categories: false), isEmpty);
      });

      test('a download that fails part way is no picture', () async {
        final cache = DafsCache.icing;
        cache.debugSet();
        cache.getter = (uri, {String? range}) async {
          if (uri.path.endsWith('.idx')) {
            return http.Response(_iceIndex(), 200);
          }
          return http.Response('', 500);
        };
        await cache.refresh(36, -97);
        expect(cache.hasPicture, isFalse);
        expect(cache.message, contains('failed'));
      });

      test('a build expires after an hour', () {
        final cache = DafsCache.turbulence;
        cache.debugSet(builtAt: DateTime.now().subtract(const Duration(minutes: 59)));
        expect(cache.expired, isFalse);
        cache.debugSet(builtAt: DateTime.now().subtract(const Duration(minutes: 61)));
        expect(cache.expired, isTrue);
        cache.debugSet();
      });
    });
  });

  group('3D Weather layers', () {
    HazardGrid hazardGrid(Hazard hazard, int value) {
      Uint8List slab(int v) => Uint8List(3600)..fillRange(0, 3600, v);
      return buildHazardGrid(
        hazard: hazard,
        slices: {
          for (var k = 1; k <= 30; k++) k * 1000: slab(k >= 3 && k <= 8 ? value : 0)
        },
        validTime: DateTime.utc(2026, 10, 31, 15),
        centerLat: 35.4,
        centerLon: -97.3,
      );
    }

    Future<void> open(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1500, 800);
      addTearDown(tester.view.reset);
      Future<http.Response> offline(Uri uri) async => throw http.ClientException('offline');
      LightningCache.instance.getter = offline;
      DafsCache.icing.getter = (uri, {String? range}) => offline(uri);
      DafsCache.turbulence.getter = (uri, {String? range}) => offline(uri);
      addTearDown(() {
        LightningCache.instance.debugSet();
        DafsCache.icing.debugSet();
        DafsCache.turbulence.debugSet();
      });
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Airspace3DView(
                weather: true, center: LatLng(35.4, -97.3), showTerrain: true)),
      ));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('winds aloft show at first, and the Wind button hides and shows them',
        (tester) async {
      await open(tester);
      expect(find.text('Hide Wind'), findsOneWidget);
      expect(find.text('Winds aloft'), findsWidgets);
      await tester.tap(find.text('Hide Wind'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Show Wind'), findsOneWidget);
      expect(find.text('Winds aloft'), findsNothing);
      await tester.tap(find.text('Show Wind'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Hide Wind'), findsOneWidget);
      expect(find.text('Winds aloft'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('every layer has a build button, and none is loaded until pressed',
        (tester) async {
      await open(tester);
      for (final name in ['NEXRAD', 'Lightning', 'Icing', 'Turbulence']) {
        expect(find.text('Build $name'), findsOneWidget);
      }
      expect(find.text('dBZ 20+'), findsOneWidget);
      expect(find.text('Ice Light+'), findsOneWidget);
      expect(find.text('Turb Light+'), findsOneWidget);
      expect(find.text('Winds aloft'), findsOneWidget);
      expect(find.text('Position only: no height'), findsNothing);
      expect(find.text('NOAA IFI'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('lightning shows its key, when it was built, and the flash count',
        (tester) async {
      await open(tester);
      final now = DateTime.now();
      LightningCache.instance.debugSet(
        flashes: [
          LightningFlash(35.4, -97.3, now.subtract(const Duration(minutes: 1))),
          LightningFlash(35.5, -97.2, now.subtract(const Duration(minutes: 4))),
          LightningFlash(35.3, -97.4, now.subtract(const Duration(minutes: 9))),
        ],
        builtAt: now.subtract(const Duration(minutes: 3)),
        lat: 35.4,
        lon: -97.3,
      );
      await tester.tap(find.text('Build Lightning'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Hide Lightning'), findsOneWidget);
      expect(find.text('Lightning'), findsOneWidget);
      expect(find.textContaining('3 flashes, last 10 min'), findsOneWidget);
      expect(find.text('Position only: no height'), findsOneWidget);
      expect(find.textContaining('rebuild in 7 min'), findsOneWidget);
      await tester.drag(find.byType(CustomPaint).first, const Offset(60, 20));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Hide Lightning'));
      await tester.pump();
      expect(find.text('Position only: no height'), findsNothing);
      expect(find.text('Build Lightning'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('icing and turbulence have keys that follow the setting, and draw',
        (tester) async {
      await open(tester);
      final built = DateTime.now().subtract(const Duration(minutes: 5));
      DafsCache.icing.debugSet(grid: hazardGrid(Hazard.icing, 3), builtAt: built);
      DafsCache.turbulence
          .debugSet(grid: hazardGrid(Hazard.turbulence, 40), builtAt: built);
      await tester.tap(find.text('Build Icing'));
      await tester.pump();
      await tester.tap(find.text('Build Turbulence'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Hide Icing'), findsOneWidget);
      expect(find.text('Hide Turbulence'), findsOneWidget);
      expect(find.text('NOAA IFI  valid 1500Z'), findsOneWidget);
      expect(find.text('NOAA GTG  valid 1500Z'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Moderate'), findsOneWidget);
      expect(find.text('Heavy'), findsOneWidget);
      expect(find.text('Trace'), findsNothing);
      expect(find.text('Light 0.15'), findsOneWidget);
      expect(find.text('Severe 0.50'), findsOneWidget);
      expect(find.textContaining('rebuild in 55 min'), findsNWidgets(2));

      // Raising the icing setting drops the weaker keys.
      await tester.tap(find.text('Ice Light+'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Moderate+').last, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Ice Moderate+'), findsOneWidget);
      expect(find.text('Light'), findsNothing);
      expect(find.text('Moderate'), findsOneWidget);

      await tester.tap(find.text('Turb Light+'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.textContaining('Severe+'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Turb Severe+'), findsOneWidget);
      expect(find.text('Light 0.15'), findsNothing);

      await tester.drag(find.byType(CustomPaint).first, const Offset(60, 20));
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Put the settings back for the other tests.
      await tester.tap(find.text('Ice Moderate+'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Light+').last, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Turb Severe+'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.textContaining('Light+').last, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Ice Light+'), findsOneWidget);
      expect(find.text('Turb Light+'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('an hour old forecast hides until rebuilt, radar and lightning after ten minutes',
        (tester) async {
      await open(tester);
      DafsCache.icing.debugSet(
          grid: hazardGrid(Hazard.icing, 3),
          builtAt: DateTime.now().subtract(const Duration(minutes: 50)));
      LightningCache.instance.debugSet(
          flashes: [LightningFlash(35.4, -97.3, DateTime.now())],
          builtAt: DateTime.now().subtract(const Duration(minutes: 5)),
          lat: 35.4,
          lon: -97.3);
      await tester.tap(find.text('Build Icing'));
      await tester.pump();
      await tester.tap(find.text('Build Lightning'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Hide Icing'), findsOneWidget);
      expect(find.text('Hide Lightning'), findsOneWidget);

      // Real time does not move in a test, so age the builds instead.
      DafsCache.icing.debugSet(
          grid: hazardGrid(Hazard.icing, 3),
          builtAt: DateTime.now().subtract(const Duration(minutes: 55)));
      LightningCache.instance.debugSet(
          flashes: [LightningFlash(35.4, -97.3, DateTime.now())],
          builtAt: DateTime.now().subtract(const Duration(minutes: 11)),
          lat: 35.4,
          lon: -97.3);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(seconds: 10));
      }
      // The forecast still has five minutes. Lightning is gone.
      expect(find.text('Hide Icing'), findsOneWidget);
      expect(find.text('Hide Lightning'), findsNothing);
      expect(find.text('Rebuild Lightning'), findsOneWidget);
      expect(find.textContaining('Lightning is 10 min old'), findsOneWidget);
      expect(find.text('Position only: no height'), findsNothing);

      DafsCache.icing.debugSet(
          grid: hazardGrid(Hazard.icing, 3),
          builtAt: DateTime.now().subtract(const Duration(minutes: 61)));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 10));
      }
      expect(find.text('Hide Icing'), findsNothing);
      expect(find.text('Rebuild Icing'), findsOneWidget);
      expect(find.textContaining('Icing is 60 min old'), findsOneWidget);
      expect(find.text('NOAA IFI  valid 1500Z'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a layer that cannot load says why next to the buttons', (tester) async {
      await open(tester);
      await tester.tap(find.text('Build Lightning'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('Lightning unavailable'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the plain 3D view has none of them', (tester) async {
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
      for (final name in ['Lightning', 'Icing', 'Turbulence', 'NEXRAD']) {
        expect(find.text('Build $name'), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
    });
  });
}
