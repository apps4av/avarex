import 'dart:math';

import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';

import '../destination/destination.dart';
import 'ofm_database_helper.dart';

abstract class AeronauticalDataProvider {
  Future<List<Destination>> findDestinations(String match, {bool exact = false});
  Future<List<Destination>> findNear(LatLng point, {double factor = 0.001});
  Future<AirportDestination?> findAirport(String code);
}

class OfmAirspace {
  final String id;
  final String codeId;
  final String name;
  final String airspaceClass;
  final String region;
  final String cycle;
  final double? lowerFeet;
  final double? upperFeet;
  final List<LatLng> vertices;
  final List<OfmAirspaceVertex> geometry;

  const OfmAirspace({required this.id, required this.codeId, required this.name,
    required this.airspaceClass, required this.region, required this.cycle,
    required this.lowerFeet, required this.upperFeet, required this.vertices,
    this.geometry = const []});
}

class OfmAirspaceVertex {
  final LatLng point;
  final String codeType;
  final LatLng? arcCenter;

  const OfmAirspaceVertex({required this.point, required this.codeType, this.arcCenter});
}

class OfmDataProvider implements AeronauticalDataProvider {
  final Database? _database;
  final String? _dataDir;

  const OfmDataProvider({Database? database, String? dataDir})
      : _database = database,
        _dataDir = dataDir;

  Future<Database> _db() async {
    if (_database != null) return _database;
    if (_dataDir == null) throw StateError('dataDir is required when no database is injected');
    return OfmDatabaseHelper.db.open(_dataDir);
  }

  @override
  Future<List<Destination>> findDestinations(String match, {bool exact = false}) async {
    final db = await _db();
    final normalized = match.trim().toUpperCase();
    if (normalized.isEmpty) return [];
    final operator = exact ? '=' : 'like';
    final value = exact ? normalized : '$normalized%';
    final airportRows = await db.rawQuery('''
select code_id as LocationID, name as FacilityName,
       case when type in ('AH', 'AD', 'HP') then 'AIRPORT' else coalesce(type, 'AIRPORT') end as Type,
       lat as ARPLatitude, lon as ARPLongitude,
       'OFM' as Source, region as SourceRegion, cycle as SourceCycle
from ofm_airport
where upper(code_id) $operator ? or upper(coalesce(name, '')) like ?
order by case when upper(code_id) = ? then 0 else 1 end, code_id
limit 20
''', [value, '%$normalized%', normalized]);
    final waypointRows = await db.rawQuery('''
select code_id as LocationID, name as FacilityName,
       case when kind = 'FIX' then 'FIX' else kind end as Type,
       lat as ARPLatitude, lon as ARPLongitude,
       'OFM' as Source, region as SourceRegion, cycle as SourceCycle
from ofm_waypoint
where upper(code_id) $operator ? or upper(coalesce(name, '')) like ?
order by case when upper(code_id) = ? then 0 else 1 end, code_id
limit 20
''', [value, '%$normalized%', normalized]);
    return [...airportRows, ...waypointRows]
        .map((row) => Destination.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  @override
  Future<List<Destination>> findNear(LatLng point, {double factor = 0.001}) async {
    final db = await _db();
    final correction = pow(cos(point.latitude * pi / 180), 2);
    final airportRows = await db.rawQuery('''
select code_id as LocationID, name as FacilityName, 'AIRPORT' as Type,
       lat as ARPLatitude, lon as ARPLongitude,
       'OFM' as Source, region as SourceRegion, cycle as SourceCycle,
       ((lon - ?) * (lon - ?) * ? + (lat - ?) * (lat - ?)) as distance
from ofm_airport
where ((lon - ?) * (lon - ?) * ? + (lat - ?) * (lat - ?)) < ?
order by distance
limit 20
''', [point.longitude, point.longitude, correction, point.latitude, point.latitude,
      point.longitude, point.longitude, correction, point.latitude, point.latitude, factor]);
    final waypointRows = await db.rawQuery('''
select code_id as LocationID, name as FacilityName,
       case when kind = 'FIX' then 'FIX' else kind end as Type,
       lat as ARPLatitude, lon as ARPLongitude,
       'OFM' as Source, region as SourceRegion, cycle as SourceCycle,
       ((lon - ?) * (lon - ?) * ? + (lat - ?) * (lat - ?)) as distance
from ofm_waypoint
where ((lon - ?) * (lon - ?) * ? + (lat - ?) * (lat - ?)) < ?
order by distance
limit 20
''', [point.longitude, point.longitude, correction, point.latitude, point.latitude,
      point.longitude, point.longitude, correction, point.latitude, point.latitude, factor]);
    final rows = [...airportRows, ...waypointRows]
      ..sort((a, b) => ((a['distance'] as num?) ?? 0).compareTo((b['distance'] as num?) ?? 0));
    return rows.map((row) => Destination.fromMap(Map<String, dynamic>.from(row))).toList();
  }

  Future<List<Destination>> findNearestAirportsWithRunways(
    LatLng point,
    int minimumRunwayLengthFeet,
  ) async {
    final db = await _db();
    final correction = pow(cos(point.latitude * pi / 180), 2);
    final minimumMeters = minimumRunwayLengthFeet / 3.280839895013123;
    final rows = await db.rawQuery('''
select a.code_id as LocationID, a.name as FacilityName, 'AIRPORT' as Type,
       a.lat as ARPLatitude, a.lon as ARPLongitude,
       'OFM' as Source, a.region as SourceRegion, a.cycle as SourceCycle,
       ((a.lon - ?) * (a.lon - ?) * ? + (a.lat - ?) * (a.lat - ?)) as distance
from ofm_airport a
where exists (
  select 1 from ofm_runway r
  where r.airport_id = a.id and coalesce(r.length_m, 0) >= ?
)
order by distance
limit 20
''', [point.longitude, point.longitude, correction, point.latitude, point.latitude, minimumMeters]);
    return rows.map((row) => Destination.fromMap(Map<String, dynamic>.from(row))).toList();
  }

  Future<List<NavDestination>> findNearestVOR(LatLng point) async {
    final db = await _db();
    final correction = pow(cos(point.latitude * pi / 180), 2);
    final rows = await db.rawQuery('''
select *, ((lon - ?) * (lon - ?) * ? + (lat - ?) * (lat - ?)) as distance
from ofm_waypoint
where kind = 'VOR'
order by distance
limit 3
''', [point.longitude, point.longitude, correction, point.latitude, point.latitude]);
    return rows.map((row) => NavDestination(
      locationID: row['code_id'] as String,
      type: (row['type'] ?? 'VOR').toString(),
      facilityName: (row['name'] ?? row['code_id']).toString(),
      coordinate: LatLng((row['lat'] as num).toDouble(), (row['lon'] as num).toDouble()),
      source: 'OFM',
      sourceRegion: row['region'] as String,
      sourceCycle: row['cycle'] as String,
      class_: (row['frequency'] ?? '').toString(),
      hiwas: (row['remark'] ?? '').toString(),
    )).toList();
  }

  @override
  Future<AirportDestination?> findAirport(String code) async {
    final db = await _db();
    final rows = await db.query('ofm_airport', where: 'upper(code_id) = ?', whereArgs: [code.toUpperCase()], limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.single;
    final id = row['id'] as String;
    final comms = await db.query('ofm_airport_comm', where: 'airport_id = ?', whereArgs: [id], orderBy: 'sequence');
    final runways = await db.query('ofm_runway', where: 'airport_id = ?', whereArgs: [id], orderBy: 'designation');
    final runwayDetails = <Map<String, dynamic>>[];
    for (final runway in runways) {
      final ends = await db.query(
        'ofm_runway_end',
        where: 'runway_id = ?',
        whereArgs: [runway['id']],
        orderBy: 'designation',
      );
      final low = ends.isEmpty ? null : ends.first;
      final high = ends.length < 2 ? null : ends[1];
      String value(Map<String, Object?>? end, String key) => (end?[key] ?? '').toString();
      runwayDetails.add(<String, dynamic>{
        'RunwayID': (runway['designation'] ?? '').toString(),
        'Length': ((runway['length_m'] as num?)?.toDouble() ?? 0) * 3.280839895013123,
        'Width': ((runway['width_m'] as num?)?.toDouble() ?? 0) * 3.280839895013123,
        'Surface': (runway['surface'] ?? '').toString(),
        'LEIdent': value(low, 'designation'),
        'LELatitude': value(low, 'lat'),
        'LELongitude': value(low, 'lon'),
        'LEHeading': value(low, 'mag_bearing'),
        'LEElevation': value(low, 'tdze_ft'),
        'LEPattern': value(low, 'pattern'),
        'LEVGSI': value(low, 'vasi_type'),
        'HEIdent': value(high, 'designation'),
        'HELatitude': value(high, 'lat'),
        'HELongitude': value(high, 'lon'),
        'HEHeading': value(high, 'mag_bearing'),
        'HEElevation': value(high, 'tdze_ft'),
        'HEPattern': value(high, 'pattern'),
        'HEVGSI': value(high, 'vasi_type'),
      });
    }
    final destination = AirportDestination(
      locationID: row['code_id'] as String,
      facilityName: (row['name'] ?? row['code_id']).toString(),
      type: 'AIRPORT',
      coordinate: LatLng(row['lat'] as double, row['lon'] as double),
      source: 'OFM',
      sourceRegion: row['region'] as String,
      sourceCycle: row['cycle'] as String,
      frequencies: comms.map((item) => <String, dynamic>{
        'Frequency': (item['value'] ?? '').toString(),
        'Use': (item['code_type'] ?? '').toString(),
        'Remark': (item['remark'] ?? '').toString(),
      }).toList(),
      awos: const [],
      runways: runwayDetails,
      unicom: '', ctaf: '', use: '', fuelTypes: '', customs: '', beacon: '',
      segCircle: '', trafficPatternAltitude: '', atct: '', nonCommercialLandingFee: '',
    );
    destination.elevation = (row['elevation_ft'] as num?)?.toDouble();
    return destination;
  }

  Future<List<OfmAirspace>> findAirspacesInBounds({
    required double minLat, required double maxLat,
    required double minLon, required double maxLon,
  }) async {
    final db = await _db();
    final rows = await db.rawQuery('''
select a.* from ofm_airspace a
where exists (
  select 1 from ofm_airspace_vertex v where v.airspace_id = a.id
  group by v.airspace_id
  having min(v.lat) <= ? and max(v.lat) >= ?
     and min(v.lon) <= ? and max(v.lon) >= ?
)
order by a.name
''', [maxLat, minLat, maxLon, minLon]);
    final result = <OfmAirspace>[];
    for (final row in rows) {
      final vertexRows = await db.query('ofm_airspace_vertex', where: 'airspace_id = ?', whereArgs: [row['id']], orderBy: 'sequence');
      final geometry = vertexRows.map((v) => OfmAirspaceVertex(
        point: LatLng((v['lat'] as num).toDouble(), (v['lon'] as num).toDouble()),
        codeType: (v['code_type'] ?? 'GRC').toString(),
        arcCenter: v['arc_lat'] == null || v['arc_lon'] == null
            ? null
            : LatLng((v['arc_lat'] as num).toDouble(), (v['arc_lon'] as num).toDouble()),
      )).toList();
      result.add(OfmAirspace(
        id: row['id'] as String,
        codeId: (row['code_id'] ?? '').toString(),
        name: (row['name'] ?? '').toString(),
        airspaceClass: (row['class'] ?? '').toString(),
        region: row['region'] as String,
        cycle: row['cycle'] as String,
        lowerFeet: (row['alt_lower_ft'] as num?)?.toDouble(),
        upperFeet: (row['alt_upper_ft'] as num?)?.toDouble(),
        vertices: geometry.map((v) => v.point).toList(),
        geometry: geometry,
      ));
    }
    return result;
  }
}
