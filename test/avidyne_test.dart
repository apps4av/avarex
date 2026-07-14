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

    test('encodes an airway as a single airway leg (name + exit fix)', () {
      final points = <AvidyneRoutePoint>[
        const AvidyneRoutePoint(
            id: 'KBOS',
            latitude: 42.36294,
            longitude: -71.00639,
            fixKind: AvidyneStoredRoute.fixAirport),
        const AvidyneRoutePoint(
            id: 'BOS',
            latitude: 42.35745,
            longitude: -70.98955,
            fixKind: AvidyneStoredRoute.fixVhfNavaid),
        const AvidyneRoutePoint.airway(id: 'V1', exitFix: 'HFD'),
      ];
      final Uint8List file =
          AvidyneStoredRoute.buildRouteFileFromPoints('KBOS BOS V1 HFD', points)!;

      // Three records: Origin KBOS, Direct BOS, Airway V1.
      expect(file[16], 3);

      final int rec2 = 17 + 39 * 2;
      expect(file[rec2], 4); // eAirway
      expect(file[rec2 + 1], 0); // fix kind unused
      // 7-byte name field is unused (zeroed) for airways.
      for (int i = rec2 + 2; i < rec2 + 9; i++) {
        expect(file[i], 0);
      }
      // Airway name in Ref1 (12 bytes starting at +9).
      final String airway = String.fromCharCodes(
          file.sublist(rec2 + 9, rec2 + 9 + 12).where((b) => b != 0));
      expect(airway, 'V1');
      // Exit fix in Ref2 (12 bytes starting at +21).
      final String exit = String.fromCharCodes(
          file.sublist(rec2 + 21, rec2 + 21 + 12).where((b) => b != 0));
      expect(exit, 'HFD');
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

    test('parses a download containing an airway leg (KBOS BOS V1 HFD)', () {
      // Exact 196-byte payload captured from an IFD Trainer download of the
      // route "KBOS BOS V1 HFD". The tail holds three records: Origin KBOS,
      // Direct BOS and an eAirway record (V1 leaving at HFD).
      final Uint8List file = Uint8List.fromList(<int>[
        0x3b, 0x56, 0x30, 0x30, 0x31, 0x00, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55, 0x55,
        0x2d, 0x32, 0x30, 0x32, 0x36, 0x2d, 0x30, 0x37, 0x2d, 0x31, 0x30, 0x2d, 0x30, 0x39, 0x2d, 0x34,
        0x31, 0x2d, 0x32, 0x38, 0x2d, 0x32, 0x31, 0x36, 0x30, 0x32, 0x34, 0x30, 0x32, 0x00, 0x31, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x4b, 0x42,
        0x4f, 0x53, 0x00, 0x00, 0x48, 0x46, 0x44, 0x00, 0x00, 0x00, 0x88, 0xf6, 0x50, 0x6a, 0x03, 0x01,
        0x03, 0x4b, 0x42, 0x4f, 0x53, 0x00, 0x00, 0x00, 0x34, 0x32, 0x2e, 0x33, 0x36, 0x32, 0x39, 0x34,
        0x20, 0x20, 0x00, 0x00, 0x2d, 0x37, 0x31, 0x2e, 0x30, 0x30, 0x36, 0x33, 0x39, 0x20, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x01, 0x42, 0x4f, 0x53, 0x20, 0x00, 0x00, 0x00, 0x34,
        0x32, 0x2e, 0x33, 0x35, 0x37, 0x34, 0x35, 0x20, 0x20, 0x00, 0x00, 0x2d, 0x37, 0x30, 0x2e, 0x39,
        0x38, 0x39, 0x35, 0x35, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x56, 0x31, 0x20, 0x20, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x48, 0x46, 0x44, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
      ]);
      expect(file.length, 196);

      final parsed = AvidyneStoredRoute.parseRouteFile(file);
      expect(parsed, isNotNull);
      expect(parsed!.points.length, 3);

      expect(parsed.points[0].id, 'KBOS');
      expect(parsed.points[0].isAirway, isFalse);
      expect(parsed.points[0].latitude, closeTo(42.36294, 1e-5));

      expect(parsed.points[1].id, 'BOS');
      expect(parsed.points[1].isAirway, isFalse);
      expect(parsed.points[1].latitude, closeTo(42.35745, 1e-5));

      expect(parsed.points[2].isAirway, isTrue);
      expect(parsed.points[2].id, 'V1');
      expect(parsed.points[2].exitFix, 'HFD');
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

    test('tolerates a leading byte before the RLE header (real IFD firmware)',
        () {
      // Some shipping IFD firmwares (seen on 10.3.1.2) prepend one extra byte
      // before the compression header, so the file content starts one byte
      // later than the documented packet offset. decompressDownload should skip
      // it and validate the RLE payload by its Fletcher checksum.
      final compressed = <int>[0x04, 0xAA, 0x82, 0xBB, 0xCC];
      final expected = <int>[0xAA, 0xAA, 0xAA, 0xAA, 0xBB, 0xCC];
      final chk = fletcher(compressed);
      final raw = <int>[
        0x00, // stray leading byte prepended by the IFD
        1, // RLE
        0, 0, 0, expected.length,
        ...compressed,
        ...chk,
      ];
      final out = AvidyneStoredRoute.decompressDownload(Uint8List.fromList(raw));
      expect(out, isNotNull);
      expect(out, equals(expected));
    });
  });

  group('AvidyneStoredRoute fixed-format parsing (real IFD download)', () {
    // Literal-only RLE encoding: valid RLE_Uncompress2 input that round-trips
    // any file (each <=127 byte chunk becomes a 0x80|len raw run).
    List<int> rleLiteral(List<int> data) {
      final out = <int>[];
      int i = 0;
      while (i < data.length) {
        final int chunk = (data.length - i).clamp(0, 127);
        out.add(0x80 | chunk);
        out.addAll(data.sublist(i, i + chunk));
        i += chunk;
      }
      return out;
    }

    List<int> fletcher(List<int> data) {
      int s1 = 0, s2 = 0;
      for (final b in data) {
        s1 = (s1 + b) % 255;
        s2 = (s1 + s2) % 255;
      }
      return [s2 & 0xFF, s1 & 0xFF];
    }

    // Wrap a plain file the way a download-data stream does: compression header
    // + literal-RLE payload + Fletcher, optionally with the stray leading byte
    // real firmware prepends.
    Uint8List wrapDownload(Uint8List file, {bool stray = false}) {
      final compressed = rleLiteral(file);
      return Uint8List.fromList(<int>[
        if (stray) 0x00,
        1,
        (file.length >> 24) & 0xFF,
        (file.length >> 16) & 0xFF,
        (file.length >> 8) & 0xFF,
        file.length & 0xFF,
        ...compressed,
        ...fletcher(compressed),
      ]);
    }

    test('decompresses and parses a real fixed-layout route (KMMU..V188..KAVP)',
        () {
      // Our own upload builder produces the exact fixed StoredRoute layout the
      // IFD returns (name[16], count, 128 x 39B records) plus a 4 byte CRC. The
      // real download is the same file without that CRC.
      final points = <AvidyneRoutePoint>[
        const AvidyneRoutePoint(
            id: 'KMMU',
            latitude: 40.79993,
            longitude: -74.41489,
            fixKind: AvidyneStoredRoute.fixAirport),
        const AvidyneRoutePoint(
            id: 'SAX',
            latitude: 41.06754,
            longitude: -74.53831,
            fixKind: AvidyneStoredRoute.fixVhfNavaid),
        const AvidyneRoutePoint.airway(id: 'V188', exitFix: 'LVZ'),
        const AvidyneRoutePoint(
            id: 'KAVP',
            latitude: 41.33847,
            longitude: -75.72333,
            fixKind: AvidyneStoredRoute.fixAirport),
      ];
      final upload =
          AvidyneStoredRoute.buildRouteFileFromPoints('KMMU-KAVP', points)!;
      // Drop the trailing 4 byte CRC to mirror the download file.
      final file = Uint8List.sublistView(upload, 0, upload.length - 4);

      // Straight fixed-format parse works.
      final parsed = AvidyneStoredRoute.parseRouteFile(file);
      expect(parsed, isNotNull);
      expect(parsed!.name, 'KMMU-KAVP');
      expect(parsed.points.length, 4);
      expect(parsed.points[0].id, 'KMMU');
      expect(parsed.points[0].isAirway, isFalse);
      expect(parsed.points[2].isAirway, isTrue);
      expect(parsed.points[2].id, 'V188');
      expect(parsed.points[2].exitFix, 'LVZ');
      expect(parsed.points[3].id, 'KAVP');

      // End-to-end through the download wrapper with the real firmware's stray
      // leading byte: decompress then parse must yield the same route.
      final wrapped = wrapDownload(file, stray: true);
      final decompressed = AvidyneStoredRoute.decompressDownload(wrapped);
      expect(decompressed, isNotNull);
      final parsed2 = AvidyneStoredRoute.parseRouteFile(decompressed!);
      expect(parsed2, isNotNull);
      expect(parsed2!.points.length, 4);
      expect(parsed2.points[2].id, 'V188');
      expect(parsed2.points[2].exitFix, 'LVZ');
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
