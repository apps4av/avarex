import 'package:flutter_test/flutter_test.dart';

import 'package:avaremp/ofm/ofmx_importer.dart';

void main() {
  test('parses designated points, VORs, and NDBs', () {
    final result = OfmxImporter.parse(_fixture, region: 'ED', cycle: '2601');

    expect(result.waypoints, hasLength(3));
    final point = result.waypoints.singleWhere((item) => item['code_id'] == 'N2');
    expect(point['kind'], 'FIX');
    expect(point['type'], 'VFR-MRP');
    expect(point['airport_code'], 'ETNG');

    final vor = result.waypoints.singleWhere((item) => item['code_id'] == 'MHV');
    expect(vor['kind'], 'VOR');
    expect(vor['frequency'], '109.80 MHZ');
    expect(vor['mag_var'], 2);

    final ndb = result.waypoints.singleWhere((item) => item['code_id'] == 'LAA');
    expect(ndb['kind'], 'NDB');
    expect(ndb['frequency'], '352.0 KHZ');
  });
}

const _fixture = '''
<OFMX-Snapshot regions="ED">
  <Dpn><DpnUid mid="point-1" region="ED"><codeId>N2</codeId><geoLat>50.99777778N</geoLat><geoLong>006.11972222E</geoLong></DpnUid><AhpUidAssoc mid="airport-1" region="ED"><codeId>ETNG</codeId></AhpUidAssoc><codeType>VFR-MRP</codeType><txtName>NOVEMBER2</txtName></Dpn>
  <Vor><VorUid mid="vor-1" region="ED"><codeId>MHV</codeId><geoLat>51.23730000N</geoLat><geoLong>006.49024444E</geoLong></VorUid><txtName>MÖNCHENGLADBACH</txtName><codeType>VOR</codeType><valFreq>109.80</valFreq><uomFreq>MHZ</uomFreq><valMagVar>2</valMagVar><dateMagVar>2025</dateMagVar><txtRmk>Operational coverage</txtRmk></Vor>
  <Ndb><NdbUid mid="ndb-1" region="ED"><codeId>LAA</codeId><geoLat>51.60168611N</geoLat><geoLong>006.17270000E</geoLong></NdbUid><txtName>NIEDERRHEIN</txtName><valFreq>352.0</valFreq><uomFreq>KHZ</uomFreq><txtRmk>Operational range 23 NM above MVA.</txtRmk></Ndb>
</OFMX-Snapshot>
''';
