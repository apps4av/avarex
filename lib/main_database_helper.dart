import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'destination.dart';

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

  Future<List<Destination>> findDestinations(String match) async {
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
      return Destination(
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

  Future<List<Destination>> findNear(LatLng point) async {
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
        return Destination(
            locationID: maps[i]['LocationID'] as String,
            facilityName: maps[i]['FacilityName'] as String,
            type: maps[i]['Type'] as String
        );
      });
    }
    return([]);
  }

  Future<AirportDestination?> findAirport(String airport) async {
    List<Map<String, dynamic>> mapsAirports = [];
    List<Map<String, dynamic>> mapsFreq = [];
    List<Map<String, dynamic>> mapsRunways = [];
    List<Map<String, dynamic>> mapsAwos = [];
    final db = await database;
    if (db != null) {
      mapsAirports = await db.rawQuery("select * from airports       where LocationID = '$airport'");
      mapsFreq = await db.rawQuery(    "select * from airportfreq    where LocationID = '$airport'");
      mapsRunways = await db.rawQuery( "select * from airportrunways where LocationID = '$airport'");
      mapsAwos = await db.rawQuery(    "select * from awos           where LocationID = '$airport'");
    }
    if(mapsAirports.isEmpty) {
      return null;
    }

    return AirportDestination(
        locationID: mapsAirports[0]['LocationID'] as String,
        lon: mapsAirports[0]['ARPLongitude'] as double,
        lat: mapsAirports[0]['ARPLatitude'] as double,
        elevation: double.parse(mapsAirports[0]['ARPElevation'] as String),
        facilityName: mapsAirports[0]['FacilityName'] as String,
        type: mapsAirports[0]['Type'] as String,
        ctaf: mapsAirports[0]['CTAFFrequency'] as String,
        unicom: mapsAirports[0]['UNICOMFrequencies'] as String,
        frequencies: mapsFreq,
        awos: mapsAwos,
        runways: mapsRunways
    );
  }
}


