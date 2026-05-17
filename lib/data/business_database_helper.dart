import 'dart:async';
import 'dart:math';
import 'package:universal_io/io.dart';
import 'package:avaremp/storage.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:avaremp/destination/destination.dart';
import 'db_general.dart';

class BusinessDatabaseHelper {
  BusinessDatabaseHelper._();

  static final BusinessDatabaseHelper _db = BusinessDatabaseHelper._();

  static BusinessDatabaseHelper get db => _db;
  static Database? _database;

  Future<Database?> get database async {
    if (_database != null) {
      return _database;
    }
    _database = await _initDB();
    return _database;
  }

  Future<Database> _initDB() async {
    Directory documentsDirectory = Directory(Storage().dataDir);
    String path = join(documentsDirectory.path, "business.db");
    return
      await openDatabase(path, onOpen: (db) {});
  }

  /// Close the cached connection after [business.db] was replaced or removed on disk
  /// (e.g. Business/FBO chart download/delete) so the next open uses the new file.
  static Future<void> invalidateConnection() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  Future<List<Destination>> findBusinesses(Destination airport) async {
    try {
      final db = await database;
      if (db == null) {
        return [];
      }
      num corrFactor = pow(cos(airport.coordinate.latitude * pi / 180.0), 2);
      String distance =
          "((Longitude - ${airport.coordinate.longitude}) * (Longitude - ${airport.coordinate.longitude}) * ${corrFactor.toDouble()} + (Latitude - ${airport.coordinate.latitude}) * (Latitude - ${airport.coordinate.latitude}))";
      String qry = "select * from business where LocationID='${airport.locationID}' order by $distance asc";
      List<Map<String, Object?>> maps = await DbGeneral.query(db, qry);
      List<Destination> out = [];
      for (final m in maps) {
        final double? lat = _readDouble(m['Latitude']);
        final double? lon = _readDouble(m['Longitude']);
        if (lat == null || lon == null) {
          continue;
        }
        final String name = (m['Name'] ?? '').toString();
        final String placeId = (m['PlaceID'] ?? '').toString();
        final gps = GpsDestination(
          locationID: airport.locationID,
          type: Destination.typeGps,
          facilityName: name,
          coordinate: LatLng(lat, lon),
        );
        gps.secondaryName = placeId;
        out.add(gps);
      }
      return out;
    } catch (_) {
      // business.db may be missing, have a different schema, or store
      // numeric columns as TEXT. Treat any failure as "no businesses".
      return [];
    }
  }

  static double? _readDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}


