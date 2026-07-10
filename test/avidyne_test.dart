import 'dart:typed_data';

import 'package:avaremp/avidyne/avidyne_crc32.dart';
import 'package:avaremp/avidyne/avidyne_stored_route.dart';
import 'package:flutter_test/flutter_test.dart';

// Mirror of the private WiFiCrChannel checksum so we can assert the algorithm
// independently. checksum = sum over i of (running + i + 1 + byte) & 0xFF.
int refChecksum(List<int> buffer, int len) {
  int checksum = 0;
  for (int i = 0; i < len; i++) {
    checksum = (checksum + i + 1 + buffer[i]) & 0xFF;
  }
  return checksum;
}

void main() {
  group('AvidyneCrc32', () {
    test('is deterministic and matches a manual table computation', () {
      final int a = AvidyneCrc32.compute([0x00]);
      // For a single 0x00 byte with init 0: value = table[0] = 0.
      expect(a, 0);

      // 0x01 -> value = table[0] ^ 0x01 = 0x00000001 (since table[0]=0)
      expect(AvidyneCrc32.compute([0x01]), 0x01);

      // Two 0x00 bytes: value stays 0.
      expect(AvidyneCrc32.compute([0x00, 0x00]), 0);

      // Non-trivial input should be a stable 32-bit value.
      final int c = AvidyneCrc32.compute(
          Uint8List.fromList('AVIDYNE'.codeUnits));
      expect(c, c & 0xFFFFFFFF);
      expect(AvidyneCrc32.compute(Uint8List.fromList('AVIDYNE'.codeUnits)), c);
    });
  });

  group('AvidyneStoredRoute file layout', () {
    Uint8List buildTwoPointFile() {
      final points = <AvidyneRoutePoint>[
        const AvidyneRoutePoint(
            id: 'KBOS',
            latitude: 42.36435,
            longitude: -71.00518,
            fixKind: AvidyneStoredRoute.fixAirport),
        const AvidyneRoutePoint(
            id: 'KHPN',
            latitude: 41.06696,
            longitude: -73.70757,
            fixKind: AvidyneStoredRoute.fixAirport),
      ];
      final Uint8List? file =
          AvidyneStoredRoute.buildRouteFileFromPoints('TEST', points);
      expect(file, isNotNull);
      return file!;
    }

    test('has the fixed 5013 byte length', () {
      final Uint8List file = buildTwoPointFile();
      // 16 (name) + 1 (count) + 128*39 (records) + 4 (crc)
      expect(file.length, 16 + 1 + 128 * 39 + 4);
    });

    test('encodes name, record count, origin and direct records', () {
      final Uint8List file = buildTwoPointFile();

      // Name field.
      final String name = String.fromCharCodes(
          file.sublist(0, 16).where((b) => b != 0));
      expect(name, 'TEST');

      // Record count.
      expect(file[16], 2);

      // First record: Origin (kind 1), fix kind Airport (3).
      final int rec0 = 17;
      expect(file[rec0], 1); // eOrigin
      expect(file[rec0 + 1], AvidyneStoredRoute.fixAirport);
      final String id0 = String.fromCharCodes(
          file.sublist(rec0 + 2, rec0 + 2 + 7).where((b) => b != 0));
      expect(id0, 'KBOS');
      final String lat0 = String.fromCharCodes(
          file.sublist(rec0 + 9, rec0 + 9 + 12).where((b) => b != 0)).trim();
      expect(lat0, '42.36435');

      // Second record: Direct (kind 3), fix kind Airport.
      final int rec1 = 17 + 39;
      expect(file[rec1], 3); // eDirect
      expect(file[rec1 + 1], AvidyneStoredRoute.fixAirport);
      final String id1 = String.fromCharCodes(
          file.sublist(rec1 + 2, rec1 + 2 + 7).where((b) => b != 0));
      expect(id1, 'KHPN');
    });

    test('padding records past the count are all zero', () {
      final Uint8List file = buildTwoPointFile();
      final int firstPad = 17 + 39 * 2;
      final int lastPad = 17 + 39 * 128;
      for (int i = firstPad; i < lastPad; i++) {
        expect(file[i], 0);
      }
    });

    test('trailing CRC32 matches the body', () {
      final Uint8List file = buildTwoPointFile();
      final int bodyEnd = file.length - 4;
      final int crc = AvidyneCrc32.compute(file.sublist(0, bodyEnd));
      expect(file[bodyEnd], (crc >> 24) & 0xFF);
      expect(file[bodyEnd + 1], (crc >> 16) & 0xFF);
      expect(file[bodyEnd + 2], (crc >> 8) & 0xFF);
      expect(file[bodyEnd + 3], crc & 0xFF);
    });

    test('rejects routes with fewer than two waypoints', () {
      final Uint8List? file = AvidyneStoredRoute.buildRouteFileFromPoints(
          'X', const [
        AvidyneRoutePoint(
            id: 'KBOS',
            latitude: 42.0,
            longitude: -71.0,
            fixKind: AvidyneStoredRoute.fixAirport),
      ]);
      expect(file, isNull);
    });
  });

  group('AvidyneStoredRoute parsing (download)', () {
    test('round-trips a built route back into name and points', () {
      final points = <AvidyneRoutePoint>[
        const AvidyneRoutePoint(
            id: 'KBOS',
            latitude: 42.36435,
            longitude: -71.00518,
            fixKind: AvidyneStoredRoute.fixAirport),
        const AvidyneRoutePoint(
            id: 'PVD',
            latitude: 41.72405,
            longitude: -71.42842,
            fixKind: AvidyneStoredRoute.fixVhfNavaid),
        const AvidyneRoutePoint(
            id: 'KHPN',
            latitude: 41.06696,
            longitude: -73.70757,
            fixKind: AvidyneStoredRoute.fixAirport),
      ];
      final Uint8List file =
          AvidyneStoredRoute.buildRouteFileFromPoints('RTOUR', points)!;

      final parsed = AvidyneStoredRoute.parseRouteFile(file);
      expect(parsed, isNotNull);
      expect(parsed!.name, 'RTOUR');
      expect(parsed.points.length, 3);

      expect(parsed.points[0].id, 'KBOS');
      expect(parsed.points[0].latitude, closeTo(42.36435, 1e-5));
      expect(parsed.points[0].longitude, closeTo(-71.00518, 1e-5));

      expect(parsed.points[1].id, 'PVD');
      expect(parsed.points[1].latitude, closeTo(41.72405, 1e-5));

      expect(parsed.points[2].id, 'KHPN');
      expect(parsed.points[2].longitude, closeTo(-73.70757, 1e-5));
    });

    test('rejects a file that is too short', () {
      expect(AvidyneStoredRoute.parseRouteFile(Uint8List(4)), isNull);
    });

    test('parses the real IFD Trainer download format (KSBA to LAX)', () {
      // Exact 196-byte payload captured from an Avidyne IFD Trainer download of
      // the route "KSBA KLAX LAX": a text header (";V001", timestamped id,
      // title, origin/dest idents, CRC), a 1-byte record count and three
      // 39-byte records at the tail.
      final Uint8List file = Uint8List.fromList(<int>[
        0x3b, 0x56, 0x30, 0x30, 0x31, 0x00, 0x52, 0x52, 0x52, 0x52, 0x52, 0x52,
        0x52, 0x52, 0x52, 0x52, 0x2d, 0x32, 0x30, 0x32, 0x36, 0x2d, 0x30, 0x37,
        0x2d, 0x30, 0x39, 0x2d, 0x32, 0x31, 0x2d, 0x33, 0x36, 0x2d, 0x34, 0x37,
        0x2d, 0x37, 0x30, 0x31, 0x34, 0x39, 0x39, 0x30, 0x36, 0x00, 0x4b, 0x53,
        0x42, 0x41, 0x20, 0x74, 0x6f, 0x20, 0x4c, 0x41, 0x58, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x4b, 0x53, 0x42, 0x41, 0x00, 0x00, 0x4c, 0x41, 0x58, 0x00,
        0x00, 0x00, 0xaf, 0x4c, 0x50, 0x6a, 0x03, 0x01, 0x03, 0x4b, 0x53, 0x42,
        0x41, 0x00, 0x00, 0x00, 0x33, 0x34, 0x2e, 0x34, 0x32, 0x36, 0x31, 0x39,
        0x20, 0x20, 0x00, 0x00, 0x2d, 0x31, 0x31, 0x39, 0x2e, 0x38, 0x34, 0x31,
        0x34, 0x39, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x03,
        0x4b, 0x4c, 0x41, 0x58, 0x00, 0x00, 0x00, 0x33, 0x33, 0x2e, 0x39, 0x34,
        0x32, 0x35, 0x30, 0x20, 0x20, 0x00, 0x00, 0x2d, 0x31, 0x31, 0x38, 0x2e,
        0x34, 0x30, 0x38, 0x30, 0x35, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x03, 0x01, 0x4c, 0x41, 0x58, 0x20, 0x00, 0x00, 0x00, 0x33, 0x33,
        0x2e, 0x39, 0x33, 0x33, 0x31, 0x35, 0x20, 0x20, 0x00, 0x00, 0x2d, 0x31,
        0x31, 0x38, 0x2e, 0x34, 0x33, 0x32, 0x30, 0x31, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
      ]);
      expect(file.length, 196);

      final parsed = AvidyneStoredRoute.parseRouteFile(file);
      expect(parsed, isNotNull);
      expect(parsed!.name, 'KSBA to LAX');
      expect(parsed.points.length, 3);

      expect(parsed.points[0].id, 'KSBA');
      expect(parsed.points[0].fixKind, AvidyneStoredRoute.fixAirport);
      expect(parsed.points[0].latitude, closeTo(34.42619, 1e-5));
      expect(parsed.points[0].longitude, closeTo(-119.84149, 1e-5));

      expect(parsed.points[1].id, 'KLAX');
      expect(parsed.points[1].fixKind, AvidyneStoredRoute.fixAirport);
      expect(parsed.points[1].latitude, closeTo(33.94250, 1e-5));
      expect(parsed.points[1].longitude, closeTo(-118.40805, 1e-5));

      expect(parsed.points[2].id, 'LAX');
      expect(parsed.points[2].fixKind, AvidyneStoredRoute.fixVhfNavaid);
      expect(parsed.points[2].latitude, closeTo(33.93315, 1e-5));
      expect(parsed.points[2].longitude, closeTo(-118.43201, 1e-5));
    });

    test('parses the CSV form the IFD may return on download', () {
      const String csv =
          "Origin,Airport,KBOS,42.364350,-71.005180,RW04R\r\n"
          "Direct,VhfNavaid,PVD,41.724050,-71.428420\r\n"
          "Direct,Fix,SSOXS,41.400000,-72.100000\r\n"
          "Airway,NoFix,V3,PVD\r\n" // not a coordinate leg -> skipped
          "DestArpt,Airport,KHPN,41.066960,-73.707570,RW16\r\n";
      final parsed = AvidyneStoredRoute.parseRouteFile(
          Uint8List.fromList(csv.codeUnits));
      expect(parsed, isNotNull);
      expect(parsed!.points.length, 4);
      expect(parsed.points[0].id, 'KBOS');
      expect(parsed.points[0].fixKind, AvidyneStoredRoute.fixAirport);
      expect(parsed.points[0].latitude, closeTo(42.36435, 1e-5));
      expect(parsed.points[1].id, 'PVD');
      expect(parsed.points[1].fixKind, AvidyneStoredRoute.fixVhfNavaid);
      expect(parsed.points[3].id, 'KHPN');
      expect(parsed.points[3].longitude, closeTo(-73.70757, 1e-5));
    });
  });

  group('AvidyneStoredRoute download decompression', () {
    // Build the small download header + payload + optional Fletcher checksum
    // that the WiFiCrChannel download protocol wraps a file in.
    List<int> fletcher(List<int> data) {
      int s1 = 0, s2 = 0;
      for (final b in data) {
        s1 = (s1 + b) % 255;
        s2 = (s1 + s2) % 255;
      }
      return [s2 & 0xFF, s1 & 0xFF];
    }

    test('passes through an uncompressed payload', () {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      final raw = <int>[
        0, // not RLE
        0, 0, 0, payload.length, // uncompressed size (big-endian)
        ...payload,
        0, 0, // trailing checksum (ignored when not RLE)
      ];
      final out = AvidyneStoredRoute.decompressDownload(Uint8List.fromList(raw));
      expect(out, isNotNull);
      expect(out, equals(payload));
    });

    test('expands an RLE compressed payload with a valid Fletcher checksum', () {
      // Decompressed target: AA AA AA AA BB CC  (4x0xAA then raw BB CC)
      // RLE tokens: [0x04,0xAA] (repeat 0xAA 4 times), [0x82,0xBB,0xCC] (2 raw).
      final compressed = <int>[0x04, 0xAA, 0x82, 0xBB, 0xCC];
      final expected = <int>[0xAA, 0xAA, 0xAA, 0xAA, 0xBB, 0xCC];
      final chk = fletcher(compressed);
      final raw = <int>[
        1, // RLE
        0, 0, 0, expected.length,
        ...compressed,
        ...chk,
      ];
      final out = AvidyneStoredRoute.decompressDownload(Uint8List.fromList(raw));
      expect(out, isNotNull);
      expect(out, equals(expected));
    });

    test('rejects an RLE payload with a bad checksum', () {
      final compressed = <int>[0x04, 0xAA];
      final raw = <int>[
        1,
        0, 0, 0, 4,
        ...compressed,
        0xFF, 0xFF, // wrong checksum
      ];
      expect(AvidyneStoredRoute.decompressDownload(Uint8List.fromList(raw)),
          isNull);
    });
  });

  group('WiFiCrChannel checksum reference', () {
    test('matches the documented running-sum algorithm', () {
      final buffer = Uint8List.fromList([0x00, 0x00, 0x0B, 0x00, 0x00]);
      final int cs = refChecksum(buffer, 5);
      // (0)+(1+0)+(2+0)+(3+11)+(4+0)+(5+0) style running sum
      int manual = 0;
      manual = (manual + 1 + 0) & 0xFF;
      manual = (manual + 2 + 0) & 0xFF;
      manual = (manual + 3 + 0x0B) & 0xFF;
      manual = (manual + 4 + 0) & 0xFF;
      manual = (manual + 5 + 0) & 0xFF;
      expect(cs, manual);
    });
  });
}
