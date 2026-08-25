import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:latlong2/latlong.dart';

import 'package:avaremp/openaip/openaip_database.dart';

void main() {
  late Database database;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await OpenAipDatabase.createSchema(database);
  });
  tearDown(() => database.close());

  test('replaces a country dataset and queries navigation plus obstacles', () async {
    final store = OpenAipDatabase(database: database);
    await store.replaceCountry(
      country: 'SE',
      airports: const [],
      navaids: [
        {
          '_id': 'nav-1', 'name': 'ALMA', 'identifier': 'ALM', 'type': 3,
          'country': 'SE', 'geometry': {'coordinates': [13.5575, 55.41139]},
          'frequency': {'value': '116.400'},
        }
      ],
      reportingPoints: [
        {
          '_id': 'rpp-1', 'name': 'MARK', 'compulsory': true, 'country': 'SE',
          'geometry': {'coordinates': [20.27028, 63.90361]},
        }
      ],
      airspaces: const [],
      obstacles: [
        {
          '_id': 'obs-1', 'name': 'Tower', 'type': 4, 'country': 'SE',
          'geometry': {'coordinates': [13.0, 55.0]},
          'elevation': {'value': 300}, 'height': {'value': 100},
        }
      ],
    );

    final search = await store.findDestinations('ALM');
    final obstacles = await store.findObstacles(
      latitude: 55.0, longitude: 13.0, minimumMslFeet: 900,
    );

    expect(search.single.locationID, 'ALM');
    expect(search.single.source, 'openAIP');
    expect(obstacles.single.latitude, 55.0);
  });

  test('loads airport details from the original openAIP payload', () async {
    final store = OpenAipDatabase(database: database);
    await store.replaceCountry(
      country: 'SE',
      airports: [
        {
          '_id': 'apt-1', 'name': 'ALINGSAS', 'icaoCode': 'ESGI', 'type': 2,
          'country': 'SE', 'geometry': {'coordinates': [12.57556, 57.94861]},
          'elevation': {'value': 67},
          'frequencies': [{'value': '123.650', 'type': 10, 'name': 'ALINGSAS RADIO'}],
          'runways': [{
            'designator': '01', 'trueHeading': 10,
            'dimension': {'length': {'value': 750}, 'width': {'value': 30}},
            'surface': {'mainComposite': 2},
          }],
        }
      ],
      navaids: const [], reportingPoints: const [], airspaces: const [], obstacles: const [],
    );

    final airport = await store.findAirport('ESGI');

    expect(airport, isNotNull);
    expect(airport!.source, 'openAIP');
    expect(airport.elevation, closeTo(219.8, 0.2));
    expect(airport.frequencies.single['Frequency'], '123.650');
    expect(airport.runways.single['LEIdent'], '01');
  });

  test('queries nearby openAIP airports and waypoints', () async {
    final store = OpenAipDatabase(database: database);
    await store.replaceCountry(
      country: 'SE',
      airports: [{
        '_id': 'apt-1', 'name': 'MALMO', 'icaoCode': 'ESMS', 'type': 3,
        'country': 'SE', 'geometry': {'coordinates': [13.37, 55.53]},
      }],
      navaids: [{
        '_id': 'nav-1', 'name': 'ALMA', 'identifier': 'ALM', 'type': 3,
        'country': 'SE', 'geometry': {'coordinates': [13.55, 55.41]},
      }],
      reportingPoints: const [], airspaces: const [], obstacles: const [],
    );

    final results = await store.findNear(const LatLng(55.5, 13.4), factor: 0.1);

    expect(results.map((item) => item.locationID), containsAll(['ESMS', 'ALM']));
  });

  test('queries openAIP airspaces intersecting map bounds', () async {
    final store = OpenAipDatabase(database: database);
    await store.replaceCountry(
      country: 'SE', airports: const [], navaids: const [], reportingPoints: const [],
      obstacles: const [],
      airspaces: [{
        '_id': 'asp-1', 'name': 'TEST CTR', 'country': 'SE', 'type': 4,
        'icaoClass': 4, 'lowerLimit': {'value': 0, 'unit': 1, 'referenceDatum': 0},
        'upperLimit': {'value': 1500, 'unit': 1, 'referenceDatum': 1},
        'geometry': {'type': 'Polygon', 'coordinates': [[
          [12.0, 55.0], [14.0, 55.0], [14.0, 57.0], [12.0, 57.0], [12.0, 55.0]
        ]]},
      }],
    );

    final results = await store.findAirspacesInBounds(
      minLat: 55.4, maxLat: 55.6, minLon: 12.9, maxLon: 13.1,
    );

    expect(results.single.name, 'TEST CTR');
    expect(results.single.points, hasLength(5));
    expect(results.single.upperFeet, 1500);
  });

  test('filters nearby airports by openAIP runway length', () async {
    final store = OpenAipDatabase(database: database);
    await store.replaceCountry(
      country: 'SE',
      airports: [{
        '_id': 'apt-long', 'name': 'LONG', 'icaoCode': 'ESLG', 'type': 3,
        'country': 'SE', 'geometry': {'coordinates': [13.4, 55.5]},
        'runways': [{'designator': '01', 'dimension': {'length': {'value': 1500}}}],
      }, {
        '_id': 'apt-short', 'name': 'SHORT', 'icaoCode': 'ESSH', 'type': 3,
        'country': 'SE', 'geometry': {'coordinates': [13.5, 55.5]},
        'runways': [{'designator': '02', 'dimension': {'length': {'value': 300}}}],
      }],
      navaids: const [], reportingPoints: const [], airspaces: const [], obstacles: const [],
    );

    final results = await store.findNearestAirportsWithRunways(
      const LatLng(55.5, 13.45), 3000,
    );

    expect(results.map((item) => item.locationID), ['ESLG']);
  });

  test('finds nearest openAIP VOR records', () async {
    final store = OpenAipDatabase(database: database);
    await store.replaceCountry(
      country: 'SE', airports: const [], reportingPoints: const [],
      airspaces: const [], obstacles: const [],
      navaids: [{
        '_id': 'vor-1', 'name': 'ALMA', 'identifier': 'ALM', 'type': 3,
        'country': 'SE', 'geometry': {'coordinates': [13.55, 55.41]},
        'frequency': {'value': '116.400'},
      }, {
        '_id': 'ndb-1', 'name': 'BEACON', 'identifier': 'BCN', 'type': 2,
        'country': 'SE', 'geometry': {'coordinates': [13.50, 55.40]},
      }],
    );

    final results = await store.findNearestVOR(const LatLng(55.5, 13.4));

    expect(results.single.locationID, 'ALM');
    expect(results.single.class_, '116.400');
  });

  test('ignores obstacles without a known top elevation for altitude filtering', () async {
    final store = OpenAipDatabase(database: database);
    await store.replaceCountry(
      country: 'SE', airports: const [], navaids: const [], reportingPoints: const [], airspaces: const [],
      obstacles: [{
        '_id': 'unknown-height', 'name': 'Obstacle', 'type': 0, 'country': 'SE',
        'geometry': {'coordinates': [13.0, 55.0]},
      }],
    );

    final results = await store.findObstacles(
      latitude: 55.0, longitude: 13.0, minimumMslFeet: -1000,
    );

    expect(results, isEmpty);
  });
}
