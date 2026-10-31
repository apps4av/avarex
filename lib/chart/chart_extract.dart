import 'dart:io';
import 'dart:typed_data';
// Hide archive's own ZLibDecoder so ZLibDecoder resolves to dart:io's native,
// truly-streaming decoder.
import 'package:archive/archive_io.dart' hide ZLibDecoder;

// Sink that writes decoded bytes straight to a file as they arrive, so the
// decompressed content is never held whole in memory. It also tracks the number
// of bytes and the running CRC-32 so the result can be verified against the zip
// directory (dart:io's inflater does not check the zip entry CRC itself).
class _RandomAccessFileSink implements Sink<List<int>> {
  final RandomAccessFile _raf;
  int length = 0;
  int crc32 = 0;
  _RandomAccessFileSink(this._raf);

  @override
  void add(List<int> data) {
    if (data.isEmpty) {
      return;
    }
    _raf.writeFromSync(data);
    length += data.length;
    crc32 = getCrc32(data, crc32);
  }

  @override
  void close() {}
}

/// Thrown when an extracted entry does not match the size / CRC recorded in the
/// zip, i.e. the download was truncated or damaged.
class ChartExtractException implements Exception {
  final String message;
  ChartExtractException(this.message);
  @override
  String toString() => 'ChartExtractException: $message';
}

// SQLite / MBTiles side files that belong to the OLD copy of a database. If one
// is left next to a freshly replaced database, SQLite replays/rolls it back into
// the new file and corrupts it.
const List<String> _sqliteSideSuffixes = ['-wal', '-shm', '-journal'];

void _deleteStaleSqliteSideFiles(String outPath) {
  for (final String suffix in _sqliteSideSuffixes) {
    try {
      final File side = File('$outPath$suffix');
      if (side.existsSync()) {
        side.deleteSync();
      }
    }
    catch (_) {}
  }
}

/// Extract a single archive entry to [outPath] while streaming to disk.
///
/// The entry is first written to `[outPath].part`, verified (size and CRC-32 when
/// the zip provides them) and only then renamed over [outPath]. A cancelled,
/// failed, truncated or killed extraction therefore never leaves a half written
/// file (for example a half written `main.db`) in place of a good one.
///
/// The archive package's own writeContent/decompress (v4.x, dart:io backend)
/// buffers the entire decompressed file in memory: it feeds a
/// ChunkedConversionSink.withCallback that only writes to the output once the
/// stream closes, so it accumulates every decoded chunk first. For large files
/// inside chart zips this exhausts the isolate's Dart heap.
///
/// Here we inflate raw deflate data with dart:io's native ZLibDecoder and write
/// each decoded chunk immediately, keeping memory bounded to a small chunk
/// regardless of the uncompressed file size.
///
/// Throws [ChartExtractException] (or another exception) on failure; the
/// temporary file is removed in that case.
void extractFileStreaming(ArchiveFile file, String outPath) {
  const int chunkSize = 64 * 1024;
  final InputStream? raw = file.rawContent?.getStream(decompress: false);

  // Create parent directories (zip entries like "tiles/0/9/161/332.webp" nest
  // into folders that may not exist yet). The archive package's OutputFileStream
  // does this internally; RandomAccessFile does not.
  final String tmpPath = '$outPath.part';
  final File tmpFile = File(tmpPath)..createSync(recursive: true);

  // Fallback for anything we don't stream ourselves (e.g. bzip2) or missing raw
  // content: use the package extractor. These paths are not used by chart zips.
  if (raw == null ||
      (file.compression != CompressionType.deflate &&
          file.compression != CompressionType.none)) {
    try {
      final OutputFileStream outputStream = OutputFileStream(tmpPath);
      file.writeContent(outputStream);
      outputStream.closeSync();
      _commit(tmpFile, outPath);
    }
    catch (_) {
      _discard(tmpFile);
      rethrow;
    }
    return;
  }

  raw.reset();
  final RandomAccessFile out = tmpFile.openSync(mode: FileMode.write);
  final _RandomAccessFileSink sink = _RandomAccessFileSink(out);
  bool closed = false;
  try {
    if (file.compression == CompressionType.deflate) {
      final Sink<List<int>> inflateInput = ZLibDecoder(raw: true)
          .startChunkedConversion(sink);
      while (!raw.isEOS) {
        final int n = raw.length < chunkSize ? raw.length : chunkSize;
        final Uint8List chunk = raw.readBytes(n).toUint8List();
        if (chunk.isEmpty) {
          break;
        }
        inflateInput.add(chunk);
      }
      inflateInput.close();
    }
    else {
      // stored (uncompressed) - copy raw bytes straight through
      while (!raw.isEOS) {
        final int n = raw.length < chunkSize ? raw.length : chunkSize;
        final Uint8List chunk = raw.readBytes(n).toUint8List();
        if (chunk.isEmpty) {
          break;
        }
        sink.add(chunk);
      }
    }

    // Make sure the bytes are really on disk before the file replaces the old one.
    out.flushSync();
    out.closeSync();
    closed = true;

    if (file.size > 0 && sink.length != file.size) {
      throw ChartExtractException(
          '${file.name}: expected ${file.size} bytes, got ${sink.length}');
    }
    final int? expectedCrc = file.crc32;
    if (expectedCrc != null && sink.crc32 != expectedCrc) {
      throw ChartExtractException('${file.name}: CRC mismatch');
    }
    _commit(tmpFile, outPath);
  }
  catch (_) {
    if (!closed) {
      try {
        out.closeSync();
      } catch (_) {}
    }
    _discard(tmpFile);
    rethrow;
  }
}

void _commit(File tmpFile, String outPath) {
  _deleteStaleSqliteSideFiles(outPath);
  tmpFile.renameSync(outPath);
}

void _discard(File tmpFile) {
  try {
    if (tmpFile.existsSync()) {
      tmpFile.deleteSync();
    }
  }
  catch (_) {}
}
