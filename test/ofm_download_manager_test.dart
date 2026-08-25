import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:avaremp/ofm/ofm_download_manager.dart';
import 'package:avaremp/ofm/ofm_publication.dart';

void main() {
  test('downloads and validates an OFM PDF atomically', () async {
    final root = await Directory.systemTemp.createTemp('ofm_pdf_test');
    addTearDown(() => root.delete(recursive: true));
    final client = MockClient((_) async => http.Response.bytes(utf8.encode('%PDF-1.4\nfixture'), 200));
    final product = OfmPublicationProduct(
      type: OfmProductType.chartPdf, rawType: 'PDF CHART COLLECTION', productTitle: 'VFR Charts 1:500k',
      name: 'ES-1', details: 'Malmö', url: Uri.parse('https://example.test/es-1.pdf'),
    );

    final installed = await OfmDownloadManager().downloadPdf(
      dataDir: root.path, region: 'ES', publicationCode: 'ESAA', cycle: '2601',
      product: product, onProgress: (_) {}, client: client,
    );

    expect(await File(installed.localPath).readAsString(), startsWith('%PDF-'));
    expect(File('${installed.localPath}.part').existsSync(), isFalse);
  });

  test('invalid PDF preserves an existing installed chart', () async {
    final root = await Directory.systemTemp.createTemp('ofm_pdf_test');
    addTearDown(() => root.delete(recursive: true));
    final manager = OfmDownloadManager();
    final product = OfmPublicationProduct(
      type: OfmProductType.chartPdf, rawType: 'PDF CHART COLLECTION',
      name: 'ES-1', details: 'Malmö', url: Uri.parse('https://example.test/es-1.pdf'),
    );
    final first = await manager.downloadPdf(
      dataDir: root.path, region: 'ES', publicationCode: 'ESAA', cycle: '2601', product: product,
      onProgress: (_) {}, client: MockClient((_) async => http.Response.bytes(utf8.encode('%PDF-valid'), 200)),
    );
    expect(
      () => manager.downloadPdf(
        dataDir: root.path, region: 'ES', publicationCode: 'ESAA', cycle: '2601', product: product,
        onProgress: (_) {}, client: MockClient((_) async => http.Response('<html>bad</html>', 200)),
      ),
      throwsA(isA<OfmDownloadException>()),
    );
    expect(await File(first.localPath).readAsString(), '%PDF-valid');
  });
}
