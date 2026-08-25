import 'package:flutter_test/flutter_test.dart';

import 'package:avaremp/ofm/ofmx_importer.dart';

void main() {
  test('parses airspace metadata and preserves vertex order', () {
    final result = OfmxImporter.parse(
      _airspaceFixture,
      region: 'LF',
      cycle: '2601',
    );

    expect(result.airspaces, hasLength(1));
    final airspace = result.airspaces.single;
    expect(airspace['id'], 'LF:2601:airspace-1');
    expect(airspace['code_id'], 'LFBG');
    expect(airspace['class'], 'D');
    expect(airspace['alt_upper_ft'], 1500);
    expect(airspace['alt_lower_ft'], 0);

    expect(result.airspaceVertices, hasLength(3));
    expect(result.airspaceVertices.map((v) => v['sequence']), [0, 1, 2]);
    expect(result.airspaceVertices[1]['code_type'], 'CCA');
    expect(result.airspaceVertices[1]['airspace_id'], 'LF:2601:airspace-1');
    expect(result.airspaceVertices[1]['arc_lat'], 45.75);
    expect(result.airspaceVertices[1]['arc_lon'], -0.35);
  });
}

const _airspaceFixture = '''
<OFMX-Snapshot regions="LF">
  <Ase><AseUid region="LF" mid="airspace-1"><codeType>CTR</codeType><codeId>LFBG</codeId></AseUid><txtName>COGNAC</txtName><codeClass>D</codeClass><codeDistVerUpper>ALT</codeDistVerUpper><valDistVerUpper>1500</valDistVerUpper><uomDistVerUpper>FT</uomDistVerUpper><codeDistVerLower>HEI</codeDistVerLower><valDistVerLower>0</valDistVerLower><uomDistVerLower>FT</uomDistVerLower><codeSelAvbl>Y</codeSelAvbl></Ase>
  <Abd><AbdUid mid="boundary-1"><AseUid region="LF" mid="airspace-1"><codeType>CTR</codeType><codeId>LFBG</codeId></AseUid></AbdUid><Avx><codeType>GRC</codeType><geoLat>45.7N</geoLat><geoLong>000.4W</geoLong></Avx><Avx><codeType>CCA</codeType><geoLat>45.8N</geoLat><geoLong>000.3W</geoLong><geoLatArc>45.75N</geoLatArc><geoLongArc>000.35W</geoLongArc></Avx><Avx><codeType>GRC</codeType><geoLat>45.7N</geoLat><geoLong>000.2W</geoLong></Avx></Abd>
</OFMX-Snapshot>
''';
