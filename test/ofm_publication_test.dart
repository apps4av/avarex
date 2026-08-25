import 'package:flutter_test/flutter_test.dart';

import 'package:avaremp/ofm/ofm_publication.dart';

void main() {
  const fixture = '''
<publications>
  <nearCycles>
    <cycle id="2601" string="22.01.2026" startValidity="2026-01-22T00:00:00Z" endValidity="2026-02-19T00:00:00Z" />
  </nearCycles>
  <item type="downloads">
    <section type="data">
      <product type="OFMX" title_english="OFMX">
        <download name="OFMX ED" timestamp="2026-02-01T17:45:00Z" details_english="Germany snapshot" URL="https://snapshots.openflightmaps.org/live/2601/ofmx/ed/latest/ofmx_ed.zip" />
      </product>
    </section>
    <section type="applicationInterface">
      <product type="EPSG3857_MBTILES_BASE_NONINTERACTIVE" title_english="Mapbox Tiles">
        <download name="TILESET ED" timestamp="2026-01-22T19:06:00Z" details_english="Germany">
          <variant filter1_english="normal resolution" URL="https://snapshots.openflightmaps.org/live/2601/tiles/ed/noninteractive/epsg3857/ed_256.mbtiles" />
          <variant filter1_english="double resolution (@2x)" URL="https://snapshots.openflightmaps.org/live/2601/tiles/ed/noninteractive/epsg3857/ed_256@2x.mbtiles" />
        </download>
      </product>
      <product type="PDF CHART COLLECTION" title_english="VFR Charts 1:500k">
        <download name="ES-1" timestamp="2026-01-22T03:12:00Z" details_english="Malmö" URL="https://example.test/es-1.pdf" />
        <download name="ES-2" timestamp="2026-01-22T03:18:00Z" details_english="Göteborg" URL="https://example.test/es-2.pdf" />
      </product>
      <product type="EPSG3857_SLIPPYTILES_BASE_NONINTERACTIVE" title_english="EPSG3857 tiles">
        <download name="TILESET ES"><variant filter1_english="tiles clipped" URL="https://example.test/slippy.zip" /></download>
      </product>
    </section>
  </item>
</publications>
''';

  test('parses near cycles and OFM download products from publication XML', () {
    final publication = OfmPublication.parse(
      region: 'ED',
      cycle: '2601',
      xml: fixture,
    );

    expect(publication.region, 'ED');
    expect(publication.cycle, '2601');
    expect(publication.nearCycles.single.id, '2601');
    expect(publication.products.where((p) => p.type == OfmProductType.ofmx), hasLength(1));
    expect(publication.products.where((p) => p.type == OfmProductType.mbtiles), hasLength(2));
    expect(publication.preferredMbtiles?.url.toString(), endsWith('ed_256.mbtiles'));
    expect(publication.ofmx?.url.toString(), endsWith('ofmx_ed.zip'));
    expect(publication.chartPdfs.map((p) => p.name), ['ES-1', 'ES-2']);
    expect(publication.normalMbtiles?.url.toString(), endsWith('ed_256.mbtiles'));
    expect(publication.retinaMbtiles?.url.toString(), endsWith('ed_256@2x.mbtiles'));
    expect(publication.slippyTileArchives.single.url.toString(), endsWith('slippy.zip'));
    expect(publication.chartPdfs.first.productTitle, 'VFR Charts 1:500k');
  });
}
