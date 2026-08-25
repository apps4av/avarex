import 'dart:async';
import 'package:universal_io/io.dart';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:archive/archive_io.dart';

import 'ofm_manifest.dart';
import 'ofm_paths.dart';
import 'ofm_publication.dart';
import 'ofmx_importer.dart';

class OfmDownloadManager {
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
  }

  Future<int?> contentLength(Uri uri, {http.Client? client}) async {
    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient.head(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return int.tryParse(response.headers['content-length'] ?? '');
    } finally {
      if (client == null) httpClient.close();
    }
  }

  Future<OfmInstalledProduct> downloadPdf({
    required String dataDir,
    required String region,
    required String publicationCode,
    required String cycle,
    required OfmPublicationProduct product,
    required void Function(double progress) onProgress,
    http.Client? client,
  }) async {
    if (product.type != OfmProductType.chartPdf) {
      throw const OfmDownloadException('Selected product is not an OFM PDF chart.');
    }
    _cancelled = false;
    final basename = path.basename(product.url.path);
    final filename = basename.toLowerCase().endsWith('.pdf') ? basename : '${product.name}.pdf';
    final destination = OfmPaths(dataDir).pdfPath(region: publicationCode, cycle: cycle, filename: filename);
    final temporary = '$destination.part';
    await Directory(path.dirname(destination)).create(recursive: true);
    await _downloadFile(product.url, temporary, onProgress, client: client);
    final header = await File(temporary).openRead(0, 5).fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
    if (String.fromCharCodes(header) != '%PDF-') {
      await File(temporary).delete();
      throw const OfmDownloadException('Downloaded OFM chart is not a valid PDF.');
    }
    final destinationFile = File(destination);
    if (await destinationFile.exists()) await destinationFile.delete();
    await File(temporary).rename(destination);
    return OfmInstalledProduct(
      region: region,
      publicationCode: publicationCode,
      cycle: cycle,
      type: 'pdf',
      name: product.name,
      details: product.details,
      sourceUrl: product.url,
      localPath: destination,
      timestamp: product.timestamp,
      byteSize: await File(destination).length(),
    );
  }

  Future<OfmInstall> downloadMbtiles({
    required String dataDir,
    required OfmPublication publication,
    required Uri publicationUrl,
    required void Function(double progress) onProgress,
    http.Client? client,
    OfmPublicationProduct? selectedProduct,
  }) async {
    _cancelled = false;
    final product = selectedProduct ?? publication.preferredMbtiles;
    if (product == null) {
      throw const OfmDownloadException('No OFM MBTiles product found in publication.');
    }

    final paths = OfmPaths(dataDir);
    final destination = paths.mbtilesPath(region: publication.region, cycle: publication.cycle);
    final temporary = '$destination.part';
    await Directory(path.dirname(destination)).create(recursive: true);
    await _downloadFile(product.url, temporary, onProgress, client: client);
    final header = await File(temporary).openRead(0, 16).fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
    if (header.length < 16 || String.fromCharCodes(header) != 'SQLite format 3\u0000') {
      await File(temporary).delete();
      throw const OfmDownloadException('Downloaded OFM MBTiles is not a valid SQLite database.');
    }
    final destinationFile = File(destination);
    if (await destinationFile.exists()) await destinationFile.delete();
    await File(temporary).rename(destination);

    return OfmInstall(
      region: publication.region,
      cycle: publication.cycle,
      installedAt: DateTime.now().toUtc(),
      publicationUrl: publicationUrl,
      mbtilesPath: destination,
    );
  }

  Future<(OfmInstall, OfmxImportResult)> downloadOfmx({
    required String dataDir,
    required OfmPublication publication,
    required Uri publicationUrl,
    required void Function(double progress) onProgress,
    http.Client? client,
  }) async {
    _cancelled = false;
    final product = publication.ofmx;
    if (product == null) throw const OfmDownloadException('No OFM OFMX product found in publication.');
    final paths = OfmPaths(dataDir);
    final rawDir = paths.rawRegionDir(region: publication.region, cycle: publication.cycle);
    await Directory(rawDir).create(recursive: true);
    final zipPath = path.join(rawDir, 'ofmx_${publication.region.toLowerCase()}.zip');
    await _downloadFile(product.url, zipPath, (value) => onProgress(value * 0.7), client: client);
    InputFileStream? input;
    try {
      input = InputFileStream(zipPath);
      final archive = ZipDecoder().decodeStream(input);
      final entries = archive.where((entry) => entry.isFile && entry.name.toLowerCase().endsWith('.ofmx')).toList();
      if (entries.isEmpty) throw const OfmDownloadException('Downloaded OFMX ZIP contains no .ofmx data.');
      final entry = entries.firstWhere((entry) => entry.name.toLowerCase().contains('isolated/'), orElse: () => entries.first);
      final destination = path.join(rawDir, path.basename(entry.name));
      final output = OutputFileStream(destination);
      entry.writeContent(output);
      output.closeSync();
      final result = OfmxImporter.parse(await File(destination).readAsString(), region: publication.region, cycle: publication.cycle);
      onProgress(1);
      return (
        OfmInstall(region: publication.region, cycle: publication.cycle, installedAt: DateTime.now().toUtc(), publicationUrl: publicationUrl, ofmxPath: destination),
        result,
      );
    } finally {
      input?.close();
      final zip = File(zipPath);
      if (await zip.exists()) await zip.delete();
    }
  }

  Future<void> _downloadFile(
    Uri uri,
    String destination,
    void Function(double progress) onProgress, {
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    IOSink? sink;
    try {
      final request = http.Request('GET', uri);
      final response = await httpClient.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw OfmDownloadException('Unable to download $uri (${response.statusCode})');
      }
      final total = response.contentLength;
      var downloaded = 0;
      sink = File(destination).openWrite();
      await for (final chunk in response.stream) {
        if (_cancelled) {
          throw const OfmDownloadException('Download cancelled.');
        }
        downloaded += chunk.length;
        sink.add(chunk);
        if (total != null && total > 0) {
          onProgress(downloaded / total);
        }
      }
      await sink.close();
      sink = null;
      onProgress(1);
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {
        // ignore cleanup errors
      }
      final file = File(destination);
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }
}

class OfmDownloadException implements Exception {
  final String message;
  const OfmDownloadException(this.message);

  @override
  String toString() => message;
}
