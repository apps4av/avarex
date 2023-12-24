import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class MainDatabaseHelper {
  MainDatabaseHelper._();

  static final MainDatabaseHelper _db = MainDatabaseHelper._();

  static MainDatabaseHelper get db => _db;
  static Database? _database;

  Future<Database?> get database async {
    if (_database != null) {
      return _database;
    }
    _database = await _initDB();
    return _database;
  }

  _initDB() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, "main.db");
    return
      await openDatabase(path, onOpen: (db) {});
  }

  Future<List<FindDestination>> findDestinations(String match) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery(
        // combine airports, fix, nav that matches match word and return 3 columns to show in the find result
        "      select LocationID, FacilityName, Type from airports where LocationID like '$match%' "
        "UNION select LocationID, FacilityName, Type from nav      where LocationID like '$match%' "
        "UNION select LocationID, FacilityName, Type from fix      where LocationID like '$match%' "
        "ORDER BY LocationID ASC"
      );
    }
    return List.generate(maps.length, (i) {
      return FindDestination(
          locationID: maps[i]['LocationID'] as String,
          facilityName: maps[i]['FacilityName'] as String,
          type: maps[i]['Type'] as String
      );
    });
  }

  Future<List<String>> findCsup(String airport) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select File from afd where LocationID = '$airport'");
    }
    return List.generate(maps.length, (i) {
      return maps[i]['File'] as String;
    });
  }

  Future<List<FindDestination>> findNear(LatLng point) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      num corrFactor = pow(cos(point.latitude * pi / 180.0), 2);
      String asDistance = "((ARPLongitude - ${point
          .longitude}) * (ARPLongitude - ${point.longitude}) * ${corrFactor
          .toDouble()} + (ARPLatitude - ${point
          .latitude}) * (ARPLatitude - ${point.latitude}))";

      String qry = "select LocationID, FacilityName, Type, $asDistance as distance "
          "from airports where distance < 0.001 "
          "order by distance";
      maps = await db.rawQuery(qry);

      return List.generate(maps.length, (i) {
        return FindDestination(
            locationID: maps[i]['LocationID'] as String,
            facilityName: maps[i]['FacilityName'] as String,
            type: maps[i]['Type'] as String
        );
      });
    }
    return([]);
  }

  Future<FindAirportParams?> findAirportParams(String airport) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from airports where LocationID = '$airport'");
    }
    if(maps.isEmpty) {
      return null;
    }
    return FindAirportParams(
        locationID: maps[0]['LocationID'] as String,
        lon: maps[0]['ARPLongitude'] as double,
        lat: maps[0]['ARPLatitude'] as double
    );
  }
}

class FindAirportParams {
  final String locationID;
  final double lon;
  final double lat;

  const FindAirportParams({
    required this.locationID,
    required this.lon,
    required this.lat,
  });
}

class FindDestination {
  final String locationID;
  final String type;
  final String facilityName;

  const FindDestination({
    required this.locationID,
    required this.type,
    required this.facilityName,
  });
}
