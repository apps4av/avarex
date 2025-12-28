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

  Future<List<Destination>> findBusinesses(Destination airport) async {
    final db = await database;
    num corrFactor = pow(cos(airport.coordinate.latitude * pi / 180.0), 2);
    String distance =
        "((Longitude - ${airport.coordinate.longitude}) * (Longitude - ${airport.coordinate.longitude}) * ${corrFactor.toDouble()} + (Latitude - ${airport.coordinate.latitude}) * (Latitude - ${airport.coordinate.latitude}))";
    if (db != null) {
      String qry = "select * from business where LocationID='${airport.locationID}' order by $distance asc";
      List<Map<String, Object?>> maps = await DbGeneral.query(db, qry);
      return List.generate(maps.length, (i) {
        String name = maps[i]['Name'] as String;
        String placeId = maps[i]['PlaceID'] as String;
        LatLng coordinate = LatLng(maps[i]['Latitude'] as double, maps[i]['Longitude'] as double);
        GpsDestination gps = GpsDestination(locationID: airport.locationID, type: Destination.typeGps, facilityName: name, coordinate: coordinate);
        gps.secondaryName = placeId;
        return gps;
      });
    }
    return [];
  }
}


