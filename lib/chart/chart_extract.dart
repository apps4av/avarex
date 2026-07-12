import 'dart:io';
import 'dart:typed_data';
// Hide archive's own ZLibDecoder so ZLibDecoder resolves to dart:io's native,
// truly-streaming decoder.
import 'package:archive/archive_io.dart' hide ZLibDecoder;

// Sink that writes decoded bytes straight to a file as they arrive, so the
// decompressed content is never held whole in memory.
class _RandomAccessFileSink implements Sink<List<int>> {
  final RandomAccessFile _raf;
  _RandomAccessFileSink(this._raf);

  @override
  void add(List<int> data) {
    if (data.isEmpty) {
      return;
    }
    _raf.writeFromSync(data);
  }

  @override
  void close() {}
}

/// Extract a single archive entry to [outPath] while streaming to disk.
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
void extractFileStreaming(ArchiveFile file, String outPath) {
  const int chunkSize = 64 * 1024;
  final InputStream? raw = file.rawContent?.getStream(decompress: false);

  // Fallback for anything we don't stream ourselves (e.g. bzip2) or missing raw
  // content: use the package extractor. These paths are not used by chart zips.
  if (raw == null ||
      (file.compression != CompressionType.deflate &&
          file.compression != CompressionType.none)) {
    final OutputFileStream outputStream = OutputFileStream(outPath);
    file.writeContent(outputStream);
    outputStream.closeSync();
    return;
  }

  raw.reset();
  // Create parent directories (zip entries like "tiles/0/9/161/332.webp" nest
  // into folders that may not exist yet). The archive package's OutputFileStream
  // does this internally; RandomAccessFile does not.
  final File outFile = File(outPath)..createSync(recursive: true);
  final RandomAccessFile out = outFile.openSync(mode: FileMode.write);
  try {
    if (file.compression == CompressionType.deflate) {
      final Sink<List<int>> inflateInput = ZLibDecoder(raw: true)
          .startChunkedConversion(_RandomAccessFileSink(out));
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
        out.writeFromSync(chunk);
      }
    }
  }
  finally {
    out.closeSync();
  }
}
