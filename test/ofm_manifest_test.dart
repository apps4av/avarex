import 'package:flutter_test/flutter_test.dart';

import 'package:avaremp/ofm/ofm_manifest.dart';
import 'package:avaremp/ofm/ofm_paths.dart';

void main() {
  test('OFM paths stay under OFM storage root', () {
    final paths = OfmPaths('/tmp/avarex');

    expect(paths.root, '/tmp/avarex/ofm');
    expect(paths.manifestPath, '/tmp/avarex/ofm/manifest.json');
    expect(paths.ofmDatabasePath, '/tmp/avarex/ofm/ofm.db');
    expect(paths.mbtilesPath(region: 'ED', cycle: '2601'), '/tmp/avarex/ofm/maps/2601/ed.mbtiles');
    expect(
      () => paths.mbtilesPath(region: '../ED', cycle: '2601'),
      throwsArgumentError,
    );
  });

  test('OFM manifest round trips installed regions', () {
    final manifest = OfmManifest(installs: [
      OfmInstall(
        region: 'ED',
        cycle: '2601',
        installedAt: DateTime.utc(2026, 2, 1),
        publicationUrl: Uri.parse('https://example.test/ED_2601.xml'),
        mbtilesPath: '/tmp/avarex/ofm/maps/2601/ed.mbtiles',
        ofmxPath: '/tmp/avarex/ofm/raw/2601/ed/ofmx_ed.ofmx',
      ),
    ]);

    final decoded = OfmManifest.fromJson(manifest.toJson());

    expect(decoded.installs, hasLength(1));
    expect(decoded.installs.single.region, 'ED');
    expect(decoded.installs.single.cycle, '2601');
    expect(decoded.installs.single.publicationUrl.toString(), 'https://example.test/ED_2601.xml');
  });

  test('OFM manifest round trips installed PDF chart products', () {
    final product = OfmInstalledProduct(
      region: 'ES', publicationCode: 'ESAA', cycle: '2601', type: 'pdf',
      name: 'ES-1', details: 'Malmö', sourceUrl: Uri.parse('https://example.test/es-1.pdf'),
      localPath: '/tmp/avarex/ofm/charts/2601/esaa/es-1.pdf',
      timestamp: DateTime.utc(2026, 1, 22), byteSize: 24112396,
    );
    final decoded = OfmManifest.fromJsonString(OfmManifest(products: [product]).toJsonString());
    expect(decoded.products.single.name, 'ES-1');
    expect(decoded.products.single.publicationCode, 'ESAA');
    expect(decoded.products.single.byteSize, 24112396);
  });

  test('OFM chart paths are sanitized and stay inside OFM storage', () {
    final paths = OfmPaths('/tmp/avarex');
    expect(paths.pdfPath(region: 'ESAA', cycle: '2601', filename: 'ES-1.pdf'),
        '/tmp/avarex/ofm/charts/2601/esaa/ES-1.pdf');
    expect(() => paths.pdfPath(region: 'ESAA', cycle: '2601', filename: '../escape.pdf'), throwsArgumentError);
  });
}
