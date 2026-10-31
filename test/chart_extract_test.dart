import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:avaremp/chart/chart_extract.dart';
import 'package:flutter_test/flutter_test.dart';

Archive _decode(List<int> zip) => ZipDecoder().decodeBytes(zip);

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('chart_extract_test');
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  List<int> makeZip(Uint8List data) {
    final Archive a = Archive()..add(ArchiveFile('main.db', data.length, data));
    return ZipEncoder().encode(a);
  }

  test('extracts, replaces old file and removes stale sqlite side files', () {
    final Uint8List data = Uint8List.fromList(List.generate(300000, (i) => i % 251));
    final String out = '${dir.path}/main.db';
    File(out).writeAsStringSync('old');
    File('$out-wal').writeAsStringSync('stale');
    File('$out-journal').writeAsStringSync('stale');

    extractFileStreaming(_decode(makeZip(data)).first, out);

    expect(File(out).readAsBytesSync(), data);
    expect(File('$out-wal').existsSync(), isFalse);
    expect(File('$out-journal').existsSync(), isFalse);
    expect(File('$out.part').existsSync(), isFalse);
  });

  test('damaged entry keeps the old file and leaves no partial file', () {
    final Uint8List data = Uint8List.fromList(List.generate(300000, (i) => i % 251));
    final String out = '${dir.path}/main.db';
    File(out).writeAsStringSync('old');

    final ArchiveFile f = _decode(makeZip(data)).first;
    f.crc32 = (f.crc32! ^ 0xdeadbeef) & 0xffffffff; // simulate corruption

    expect(() => extractFileStreaming(f, out), throwsA(isA<ChartExtractException>()));
    expect(File(out).readAsStringSync(), 'old');
    expect(File('$out.part').existsSync(), isFalse);
  });
}
