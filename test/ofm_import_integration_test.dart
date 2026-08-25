import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:avaremp/ofm/ofm_data_provider.dart';
import 'package:avaremp/ofm/ofm_schema.dart';
import 'package:avaremp/ofm/ofmx_importer.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('imports fixtures and queries airport and airspace end to end', () async {
    final database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(database.close);
    for (final statement in OfmSchema.createStatements) {
      await database.execute(statement);
    }

    final airportImport = OfmxImporter.parse(_airportFixture, region: 'EB', cycle: '2601');
    final airspaceImport = OfmxImporter.parse(_airspaceFixture, region: 'LF', cycle: '2601');
    for (final entry in <String, List<Map<String, Object?>>>{
      'ofm_airport': airportImport.airports,
      'ofm_airport_comm': airportImport.airportComms,
      'ofm_runway': airportImport.runways,
      'ofm_runway_end': airportImport.runwayEnds,
      'ofm_waypoint': airportImport.waypoints,
      'ofm_airspace': airspaceImport.airspaces,
      'ofm_airspace_vertex': airspaceImport.airspaceVertices,
    }.entries) {
      for (final row in entry.value) {
        await database.insert(entry.key, row);
      }
    }

    final provider = OfmDataProvider(database: database);
    final airport = await provider.findAirport('EBAW');
    final bounds = await provider.findAirspacesInBounds(minLat: 45, maxLat: 46, minLon: -1, maxLon: 1);

    expect(airport?.source, 'OFM');
    expect(airport?.runways, hasLength(1));
    expect(bounds.single.codeId, 'LFBG');
    expect(bounds.single.vertices, hasLength(3));
  });
}

const _airportFixture = '''<OFMX-Snapshot><Ahp><AhpUid region="EB" mid="a"><codeId>EBAW</codeId></AhpUid><txtName>ANTWERPEN</txtName><codeType>AH</codeType><geoLat>51.18N</geoLat><geoLong>4.46E</geoLong></Ahp><Rwy><RwyUid mid="r"><AhpUid mid="a"><codeId>EBAW</codeId></AhpUid><txtDesig>11/29</txtDesig></RwyUid><valLen>1510</valLen><valWid>45</valWid><uomDimRwy>M</uomDimRwy></Rwy></OFMX-Snapshot>''';
const _airspaceFixture = '''<OFMX-Snapshot><Ase><AseUid region="LF" mid="s"><codeType>CTR</codeType><codeId>LFBG</codeId></AseUid><txtName>COGNAC</txtName><codeClass>D</codeClass></Ase><Abd><AbdUid><AseUid mid="s"><codeId>LFBG</codeId></AseUid></AbdUid><Avx><codeType>GRC</codeType><geoLat>45.7N</geoLat><geoLong>0.4W</geoLong></Avx><Avx><codeType>GRC</codeType><geoLat>45.8N</geoLat><geoLong>0.3W</geoLong></Avx><Avx><codeType>GRC</codeType><geoLat>45.7N</geoLat><geoLong>0.2W</geoLong></Avx></Abd></OFMX-Snapshot>''';
