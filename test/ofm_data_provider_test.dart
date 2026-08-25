import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:latlong2/latlong.dart';

import 'package:avaremp/ofm/ofm_data_provider.dart';
import 'package:avaremp/ofm/ofm_schema.dart';

void main() {
  late Database database;

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    for (final statement in OfmSchema.createStatements) {
      await database.execute(statement);
    }
    await database.insert('ofm_airport', {
      'id': 'airport-1', 'region': 'EB', 'cycle': '2601', 'code_id': 'EBAW',
      'name': 'ANTWERPEN/DEURNE', 'type': 'AH', 'lat': 51.18945833,
      'lon': 4.46039722, 'elevation_ft': 39.0, 'source': 'OFM',
    });
    await database.insert('ofm_airport_comm', {
      'id': 'comm-1', 'airport_id': 'airport-1', 'code_type': 'RADIO',
      'value': '135.2', 'sequence': 1,
    });
    await database.insert('ofm_runway', {
      'id': 'runway-1', 'airport_id': 'airport-1', 'designation': '11/29',
      'length_m': 1510.0, 'width_m': 45.0, 'surface': 'ASPH',
    });
    await database.insert('ofm_runway_end', {
      'id': 'end-11', 'runway_id': 'runway-1', 'designation': '11',
      'lat': 51.19186111, 'lon': 4.454775, 'true_bearing': 109.8,
      'mag_bearing': 112.0, 'tdze_ft': 39.0, 'pattern': 'E',
      'vasi_type': 'PAPI',
    });
    await database.insert('ofm_waypoint', {
      'id': 'vor-1', 'region': 'EB', 'cycle': '2601', 'raw_mid': 'vor-1',
      'code_id': 'BUN', 'kind': 'VOR', 'type': 'VOR', 'name': 'BRUSSELS',
      'lat': 50.9, 'lon': 4.5, 'frequency': '110.6 MHZ', 'mag_var': 2.0,
    });
    await database.insert('ofm_waypoint', {
      'id': 'fix-1', 'region': 'EB', 'cycle': '2601', 'raw_mid': 'fix-1',
      'code_id': 'N2', 'kind': 'FIX', 'type': 'VFR-MRP', 'name': 'NOVEMBER2',
      'lat': 51.0, 'lon': 4.6, 'airport_code': 'EBAW',
    });
  });
  tearDown(() => database.close());

  test('finds source-aware OFM airport results by prefix', () async {
    final provider = OfmDataProvider(database: database);
    final results = await provider.findDestinations('EBA');

    expect(results, hasLength(1));
    expect(results.single.locationID, 'EBAW');
    expect(results.single.source, 'OFM');
    expect(results.single.sourceRegion, 'EB');
  });

  test('loads OFM airport details and nearby airports', () async {
    final provider = OfmDataProvider(database: database);
    final airport = await provider.findAirport('EBAW');
    final nearby = await provider.findNear(const LatLng(51.19, 4.46), factor: 0.01);

    expect(airport, isNotNull);
    expect(airport!.frequencies.single['Frequency'], '135.2');
    expect(airport.runways.single['RunwayID'], '11/29');
    expect(airport.runways.single['LEIdent'], '11');
    expect(airport.runways.single['LELatitude'], '51.19186111');
    expect(airport.runways.single['LELongitude'], '4.454775');
    expect(airport.runways.single['LEVGSI'], 'PAPI');
    expect(nearby.single.locationID, 'EBAW');
  });

  test('finds nearest OFM airports meeting runway length', () async {
    final provider = OfmDataProvider(database: database);
    final results = await provider.findNearestAirportsWithRunways(
      const LatLng(51.19, 4.46),
      4000,
    );

    expect(results.map((item) => item.locationID), contains('EBAW'));
    expect(await provider.findNearestAirportsWithRunways(
      const LatLng(51.19, 4.46),
      6000,
    ), isEmpty);
  });

  test('searches OFM navaids and designated points', () async {
    final provider = OfmDataProvider(database: database);
    final vor = await provider.findDestinations('BUN');
    final point = await provider.findDestinations('NOVEMBER');

    expect(vor.single.type, 'VOR');
    expect(vor.single.locationID, 'BUN');
    expect(point.single.type, 'FIX');
    expect(point.single.locationID, 'N2');
  });

  test('finds nearby OFM airports, navaids, and points', () async {
    final provider = OfmDataProvider(database: database);
    final results = await provider.findNear(const LatLng(51.0, 4.6), factor: 0.1);

    expect(results.map((item) => item.locationID), containsAll(['EBAW', 'BUN', 'N2']));
  });

  test('finds nearest OFM VORs as fully populated nav destinations', () async {
    final provider = OfmDataProvider(database: database);
    final results = await provider.findNearestVOR(const LatLng(51.0, 4.6));

    expect(results.single.locationID, 'BUN');
    expect(results.single.source, 'OFM');
    expect(results.single.class_, '110.6 MHZ');
  });

  test('finds an enclosing airspace when its vertices are outside the viewport', () async {
    await database.insert('ofm_airspace', {
      'id': 'space-1', 'region': 'EB', 'cycle': '2601', 'code_id': 'EBR',
      'code_type': 'R', 'class': 'R', 'name': 'ENCLOSING',
    });
    for (final entry in <(double, double)>[(50.0, 3.0), (52.0, 3.0), (52.0, 6.0), (50.0, 6.0)].indexed) {
      await database.insert('ofm_airspace_vertex', {
        'airspace_id': 'space-1', 'sequence': entry.$1,
        'lat': entry.$2.$1, 'lon': entry.$2.$2,
      });
    }
    final provider = OfmDataProvider(database: database);
    final results = await provider.findAirspacesInBounds(
      minLat: 50.9, maxLat: 51.1, minLon: 4.4, maxLon: 4.6,
    );

    expect(results.single.codeId, 'EBR');
  });
}
