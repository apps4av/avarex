import 'dart:convert';
import 'dart:math';

import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:universal_io/io.dart';

import '../destination/destination.dart';

class OpenAipAirspace {
  final String id;
  final String name;
  final String country;
  final int? type;
  final int? icaoClass;
  final double? lowerFeet;
  final double? upperFeet;
  final bool byNotam;
  final bool onRequest;
  final List<LatLng> points;

  const OpenAipAirspace({
    required this.id, required this.name, required this.country,
    required this.type, required this.icaoClass, required this.lowerFeet,
    required this.upperFeet, required this.byNotam, required this.onRequest,
    required this.points,
  });
}

class OpenAipDatabase {
  final Database database;

  static const int schemaVersion = 2;

  const OpenAipDatabase({required this.database});

  static Future<void> createSchema(Database db) async {
    for (final statement in _statements) {
      await db.execute(statement);
    }
  }

  Future<void> replaceCountry({
    required String country,
    required List<Map<String, dynamic>> airports,
    required List<Map<String, dynamic>> navaids,
    required List<Map<String, dynamic>> reportingPoints,
    required List<Map<String, dynamic>> airspaces,
    required List<Map<String, dynamic>> obstacles,
  }) async {
    final code = country.toUpperCase();
    await database.transaction((tx) async {
      for (final table in ['openaip_airport', 'openaip_waypoint', 'openaip_airspace', 'openaip_obstacle']) {
        await tx.delete(table, where: 'country = ?', whereArgs: [code]);
      }
      for (final item in airports) {
        final coordinate = _coordinate(item);
        if (coordinate == null) continue;
        await tx.insert('openaip_airport', {
          'id': item['_id'], 'country': code, 'code_id': _airportCode(item),
          'name': item['name'], 'type': item['type'], 'lat': coordinate.latitude,
          'lon': coordinate.longitude, 'elevation_ft': _metersToFeet(_nestedNumber(item, 'elevation')),
          'max_runway_ft': _maxRunwayFeet(item),
          'mag_var': item['magneticDeclination'], 'updated_at': item['updatedAt'],
          'raw_json': jsonEncode(item),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final item in [...navaids.map((item) => (item, 'NAVAID')), ...reportingPoints.map((item) => (item, 'REPORTING_POINT'))]) {
        final record = item.$1;
        final coordinate = _coordinate(record);
        if (coordinate == null) continue;
        final isNav = item.$2 == 'NAVAID';
        final frequency = record['frequency'] is Map ? (record['frequency'] as Map)['value'] : null;
        await tx.insert('openaip_waypoint', {
          'id': record['_id'], 'country': code,
          'code_id': isNav ? record['identifier'] : record['name'],
          'name': record['name'], 'kind': isNav ? _navaidType(record['type']) : 'FIX',
          'type': record['type']?.toString(), 'lat': coordinate.latitude,
          'lon': coordinate.longitude, 'frequency': frequency,
          'mag_var': record['magneticDeclination'],
          'compulsory': record['compulsory'] == true ? 1 : 0,
          'updated_at': record['updatedAt'], 'raw_json': jsonEncode(record),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final item in obstacles) {
        final coordinate = _coordinate(item);
        if (coordinate == null) continue;
        await tx.insert('openaip_obstacle', {
          'id': item['_id'], 'country': code, 'name': item['name'],
          'type': item['type'], 'lat': coordinate.latitude, 'lon': coordinate.longitude,
          'elevation_ft': _metersToFeet(_nestedNumber(item, 'elevation')),
          'height_ft': _metersToFeet(_nestedNumber(item, 'height')),
          'updated_at': item['updatedAt'], 'raw_json': jsonEncode(item),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final item in airspaces) {
        final geometry = item['geometry'];
        if (geometry is! Map || geometry['coordinates'] is! List) continue;
        await tx.insert('openaip_airspace', {
          'id': item['_id'], 'country': code, 'name': item['name'],
          'type': item['type'], 'icao_class': item['icaoClass'],
          'geometry_json': jsonEncode(item['geometry']),
          'lower_ft': _verticalFeet(item['lowerLimit']),
          'upper_ft': _verticalFeet(item['upperLimit']),
          'by_notam': item['byNotam'] == true ? 1 : 0,
          'on_request': item['onRequest'] == true ? 1 : 0,
          'updated_at': item['updatedAt'], 'raw_json': jsonEncode(item),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await tx.insert('openaip_country_install', {
        'country': code, 'installed_at': DateTime.now().toUtc().toIso8601String(),
        'airport_count': airports.length, 'waypoint_count': navaids.length + reportingPoints.length,
        'airspace_count': airspaces.length, 'obstacle_count': obstacles.length,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<Destination>> findDestinations(String match, {bool exact = false}) async {
    final normalized = match.trim().toUpperCase();
    if (normalized.isEmpty) return [];
    final operator = exact ? '=' : 'like';
    final value = exact ? normalized : '$normalized%';
    final airportRows = await database.rawQuery('''
select code_id as LocationID, name as FacilityName, 'AIRPORT' as Type,
 lat as ARPLatitude, lon as ARPLongitude, 'openAIP' as Source,
 country as SourceRegion, '' as SourceCycle
from openaip_airport where upper(code_id) $operator ? or upper(coalesce(name,'')) like ? limit 20
''', [value, '%$normalized%']);
    final waypointRows = await database.rawQuery('''
select code_id as LocationID, name as FacilityName,
 case when kind = 'FIX' then 'FIX' else kind end as Type,
 lat as ARPLatitude, lon as ARPLongitude, 'openAIP' as Source,
 country as SourceRegion, '' as SourceCycle
from openaip_waypoint where upper(code_id) $operator ? or upper(coalesce(name,'')) like ? limit 20
''', [value, '%$normalized%']);
    return [...airportRows, ...waypointRows].map(_destinationFromRow).toList();
  }

  Future<List<Destination>> findNear(LatLng point, {double factor = 0.001}) async {
    final correction = cos(point.latitude * pi / 180) * cos(point.latitude * pi / 180);
    Future<List<Map<String, Object?>>> query(String table, String typeExpression) => database.rawQuery('''
select code_id as LocationID, name as FacilityName, $typeExpression as Type,
 lat as ARPLatitude, lon as ARPLongitude, 'openAIP' as Source,
 country as SourceRegion, '' as SourceCycle,
 ((lon - ?) * (lon - ?) * ? + (lat - ?) * (lat - ?)) as distance
from $table where ((lon - ?) * (lon - ?) * ? + (lat - ?) * (lat - ?)) < ?
''', [point.longitude, point.longitude, correction, point.latitude, point.latitude,
      point.longitude, point.longitude, correction, point.latitude, point.latitude, factor]);
    final rows = <Map<String, Object?>>[
      ...await query('openaip_airport', "'AIRPORT'"),
      ...await query('openaip_waypoint', "case when kind = 'FIX' then 'FIX' else kind end"),
    ]..sort((a, b) => ((a['distance'] as num?) ?? 0).compareTo((b['distance'] as num?) ?? 0));
    return rows.take(20).map(_destinationFromRow).toList();
  }

  Future<List<Destination>> findNearestAirportsWithRunways(
    LatLng point,
    int runwayLengthFeet,
  ) async {
    final correction = cos(point.latitude * pi / 180) * cos(point.latitude * pi / 180);
    final rows = await database.rawQuery('''
select code_id as LocationID, name as FacilityName, 'AIRPORT' as Type,
 lat as ARPLatitude, lon as ARPLongitude, 'openAIP' as Source,
 country as SourceRegion, '' as SourceCycle,
 ((lon - ?) * (lon - ?) * ? + (lat - ?) * (lat - ?)) as distance
from openaip_airport where coalesce(max_runway_ft, 0) >= ?
order by distance limit 20
''', [point.longitude, point.longitude, correction, point.latitude, point.latitude, runwayLengthFeet]);
    return rows.map(_destinationFromRow).toList();
  }

  Future<List<NavDestination>> findNearestVOR(LatLng point) async {
    final correction = cos(point.latitude * pi / 180) * cos(point.latitude * pi / 180);
    final rows = await database.rawQuery('''
select code_id, name, kind, lat, lon, frequency, mag_var, country,
 ((lon - ?) * (lon - ?) * ? + (lat - ?) * (lat - ?)) as distance
from openaip_waypoint where kind like 'VOR%' order by distance limit 3
''', [point.longitude, point.longitude, correction, point.latitude, point.latitude]);
    return rows.map((row) => NavDestination(
      locationID: row['code_id'] as String,
      type: row['kind'] as String,
      facilityName: (row['name'] ?? row['code_id']).toString(),
      coordinate: LatLng((row['lat'] as num).toDouble(), (row['lon'] as num).toDouble()),
      source: 'openAIP', sourceRegion: row['country'] as String,
      class_: (row['frequency'] ?? '').toString(),
      hiwas: '',
    )).toList();
  }

  Future<List<LatLng>> findObstacles({
    required double latitude,
    required double longitude,
    required double minimumMslFeet,
  }) async {
    final rows = await database.query('openaip_obstacle', where: '''
elevation_ft is not null and elevation_ft + coalesce(height_ft, 0) > ? and
lat between ? and ? and lon between ? and ?
''', whereArgs: [minimumMslFeet, latitude - 0.4, latitude + 0.4, longitude - 0.4, longitude + 0.4]);
    return rows.map((row) => LatLng((row['lat'] as num).toDouble(), (row['lon'] as num).toDouble())).toList();
  }

  Future<AirportDestination?> findAirport(String code) async {
    final rows = await database.query('openaip_airport',
        where: 'upper(code_id) = ?', whereArgs: [code.trim().toUpperCase()], limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.single;
    final decoded = jsonDecode((row['raw_json'] ?? '{}').toString());
    final payload = decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    final frequencies = (payload['frequencies'] as List? ?? const []).whereType<Map>().map((item) {
      final map = Map<String, dynamic>.from(item);
      return <String, dynamic>{
        'Frequency': (map['value'] ?? '').toString(),
        'Use': (map['name'] ?? _frequencyType(map['type'])).toString(),
        'Remark': (map['remarks'] ?? '').toString(),
      };
    }).toList();
    final runways = (payload['runways'] as List? ?? const []).whereType<Map>().map((item) {
      final map = Map<String, dynamic>.from(item);
      final dimension = map['dimension'] is Map ? Map<String, dynamic>.from(map['dimension']) : const <String, dynamic>{};
      final length = dimension['length'] is Map ? (dimension['length'] as Map)['value'] : null;
      final width = dimension['width'] is Map ? (dimension['width'] as Map)['value'] : null;
      final designator = (map['designator'] ?? '').toString();
      return <String, dynamic>{
        'RunwayID': designator,
        'Length': _metersToFeet(length is num ? length.toDouble() : null) ?? 0,
        'Width': _metersToFeet(width is num ? width.toDouble() : null) ?? 0,
        'Surface': _surfaceName(map['surface'] is Map ? (map['surface'] as Map)['mainComposite'] : null),
        'LEIdent': designator, 'LELatitude': row['lat'].toString(),
        'LELongitude': row['lon'].toString(), 'LEHeading': (map['trueHeading'] ?? '').toString(),
        'LEElevation': (row['elevation_ft'] ?? '').toString(),
        'LEPattern': _turnDirection(map['turnDirection']), 'LEVGSI': '',
        'HEIdent': '', 'HELatitude': '', 'HELongitude': '', 'HEHeading': '',
        'HEElevation': '', 'HEPattern': '', 'HEVGSI': '',
      };
    }).toList();
    final destination = AirportDestination(
      locationID: row['code_id'] as String, type: 'AIRPORT',
      facilityName: (row['name'] ?? row['code_id']).toString(),
      coordinate: LatLng((row['lat'] as num).toDouble(), (row['lon'] as num).toDouble()),
      source: 'openAIP', sourceRegion: row['country'] as String,
      frequencies: frequencies, runways: runways, awos: const [],
      unicom: '', ctaf: '', use: '', fuelTypes: '', customs: '', beacon: '',
      segCircle: '', trafficPatternAltitude: '', atct: '', nonCommercialLandingFee: '',
    );
    destination.elevation = (row['elevation_ft'] as num?)?.toDouble();
    return destination;
  }

  Future<List<OpenAipAirspace>> findAirspacesInBounds({
    required double minLat, required double maxLat,
    required double minLon, required double maxLon,
  }) async {
    final rows = await database.query('openaip_airspace');
    final result = <OpenAipAirspace>[];
    for (final row in rows) {
      final decoded = jsonDecode((row['geometry_json'] ?? '{}').toString());
      if (decoded is! Map || decoded['coordinates'] is! List) continue;
      final rings = decoded['coordinates'] as List;
      if (rings.isEmpty || rings.first is! List) continue;
      final points = (rings.first as List).whereType<List>().where((pair) => pair.length >= 2)
          .map((pair) => LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble())).toList();
      if (points.isEmpty) continue;
      final south = points.map((p) => p.latitude).reduce(min);
      final north = points.map((p) => p.latitude).reduce(max);
      final west = points.map((p) => p.longitude).reduce(min);
      final east = points.map((p) => p.longitude).reduce(max);
      if (south > maxLat || north < minLat || west > maxLon || east < minLon) continue;
      result.add(OpenAipAirspace(
        id: row['id'] as String, name: (row['name'] ?? '').toString(),
        country: row['country'] as String, type: row['type'] as int?,
        icaoClass: row['icao_class'] as int?,
        lowerFeet: (row['lower_ft'] as num?)?.toDouble(),
        upperFeet: (row['upper_ft'] as num?)?.toDouble(),
        byNotam: row['by_notam'] == 1, onRequest: row['on_request'] == 1,
        points: points,
      ));
    }
    return result;
  }

  Future<void> deleteCountry(String country) async {
    final code = country.trim().toUpperCase();
    await database.transaction((tx) async {
      for (final table in ['openaip_airport', 'openaip_waypoint', 'openaip_airspace', 'openaip_obstacle', 'openaip_country_install']) {
        await tx.delete(table, where: 'country = ?', whereArgs: [code]);
      }
    });
  }

  static LatLng? _coordinate(Map<String, dynamic> item) {
    final geometry = item['geometry'];
    if (geometry is! Map || geometry['coordinates'] is! List) return null;
    final coordinates = geometry['coordinates'] as List;
    if (coordinates.length < 2 || coordinates[0] is! num || coordinates[1] is! num) return null;
    return LatLng((coordinates[1] as num).toDouble(), (coordinates[0] as num).toDouble());
  }

  static Destination _destinationFromRow(Map<String, Object?> row) {
    final type = row['Type'] as String;
    final locationID = row['LocationID'] as String;
    final facilityName = (row['FacilityName'] ?? locationID).toString();
    final coordinate = LatLng(
      (row['ARPLatitude'] as num).toDouble(),
      (row['ARPLongitude'] as num).toDouble(),
    );
    final sourceRegion = (row['SourceRegion'] ?? '').toString();
    if (Destination.isAirport(type)) {
      return AirportDestination(
        locationID: locationID, type: type, facilityName: facilityName,
        coordinate: coordinate, source: 'openAIP', sourceRegion: sourceRegion,
        frequencies: const [], runways: const [], awos: const [], unicom: '', ctaf: '',
        use: '', fuelTypes: '', customs: '', beacon: '', segCircle: '',
        trafficPatternAltitude: '', atct: '', nonCommercialLandingFee: '',
      );
    }
    if (Destination.isNav(type)) {
      return NavDestination(
        locationID: locationID, type: type, facilityName: facilityName,
        coordinate: coordinate, source: 'openAIP', sourceRegion: sourceRegion,
        class_: '', hiwas: '',
      );
    }
    return FixDestination(
      locationID: locationID, type: type, facilityName: facilityName,
      coordinate: coordinate, source: 'openAIP', sourceRegion: sourceRegion,
    );
  }

  static String _airportCode(Map<String, dynamic> item) {
    for (final key in ['icaoCode', 'altIdentifier', 'iataCode', 'name']) {
      final value = item[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return item['_id'].toString();
  }

  static double? _nestedNumber(Map<String, dynamic> item, String key) {
    final value = item[key];
    return value is Map && value['value'] is num ? (value['value'] as num).toDouble() : null;
  }

  static double? _metersToFeet(double? meters) => meters == null ? null : meters * 3.280839895013123;

  static double? _maxRunwayFeet(Map<String, dynamic> item) {
    final runways = item['runways'];
    if (runways is! List) return null;
    double? longest;
    for (final runway in runways.whereType<Map>()) {
      final dimension = runway['dimension'];
      final length = dimension is Map ? dimension['length'] : null;
      final value = length is Map && length['value'] is num
          ? (length['value'] as num).toDouble()
          : null;
      final feet = _metersToFeet(value);
      if (feet != null && (longest == null || feet > longest)) longest = feet;
    }
    return longest;
  }

  static double? _verticalFeet(Object? raw) {
    if (raw is! Map || raw['value'] is! num) return null;
    final value = (raw['value'] as num).toDouble();
    return raw['unit'] == 6 ? value * 100 : raw['unit'] == 0 ? _metersToFeet(value) : value;
  }

  static String _navaidType(Object? type) => switch (type) {
    0 => 'DME',
    1 => 'TACAN',
    2 => 'NDB',
    3 || 6 => 'VOR',
    4 || 7 => 'VOR/DME',
    5 || 8 => 'VORTAC',
    _ => 'DME',
  };

  static String _frequencyType(Object? type) => switch (type) {
    4 => 'CTAF',
    5 => 'Delivery',
    6 => 'Departure',
    7 => 'FIS',
    9 => 'Ground',
    10 => 'Information',
    12 => 'Unicom',
    13 => 'Radar',
    14 => 'Tower',
    15 => 'ATIS',
    16 => 'Radio',
    _ => 'Frequency',
  };

  static String _surfaceName(Object? type) => switch (type) {
    0 => 'Asphalt',
    1 => 'Concrete',
    2 => 'Grass',
    3 => 'Sand',
    4 => 'Water',
    _ => type?.toString() ?? '',
  };

  static String _turnDirection(Object? type) => switch (type) {
    0 => 'R',
    1 => 'L',
    _ => '',
  };

  static const _statements = <String>[
    '''create table if not exists openaip_country_install (
      country text primary key, installed_at text not null,
      airport_count integer, waypoint_count integer, airspace_count integer, obstacle_count integer)''',
    '''create table if not exists openaip_airport (
      id text primary key, country text not null, code_id text not null, name text,
      type integer, lat real not null, lon real not null, elevation_ft real,
      max_runway_ft real, mag_var real, updated_at text, raw_json text)''',
    'create index if not exists idx_openaip_airport_code on openaip_airport(code_id)',
    '''create table if not exists openaip_waypoint (
      id text primary key, country text not null, code_id text not null, name text,
      kind text not null, type text, lat real not null, lon real not null,
      frequency text, mag_var real, compulsory integer, updated_at text, raw_json text)''',
    'create index if not exists idx_openaip_waypoint_code on openaip_waypoint(code_id)',
    '''create table if not exists openaip_airspace (
      id text primary key, country text not null, name text, type integer, icao_class integer,
      geometry_json text, lower_ft real, upper_ft real, by_notam integer,
      on_request integer, updated_at text, raw_json text)''',
    '''create table if not exists openaip_obstacle (
      id text primary key, country text not null, name text, type integer,
      lat real not null, lon real not null, elevation_ft real, height_ft real,
      updated_at text, raw_json text)''',
    'create index if not exists idx_openaip_obstacle_lat_lon on openaip_obstacle(lat, lon)',
  ];

  static Future<Database> open(String dataDir) async {
    final dbPath = path.join(dataDir, 'openaip', 'openaip.db');
    await Directory(path.dirname(dbPath)).create(recursive: true);
    final db = await openDatabase(
      dbPath,
      version: schemaVersion,
      onCreate: (db, _) => createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute('alter table openaip_airport add column max_runway_ft real');
          } catch (_) {
            // The column may already exist in databases created by development builds.
          }
        }
      },
    );
    return db;
  }
}
