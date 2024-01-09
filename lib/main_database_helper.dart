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
    List<Map<String, dynamic>> mapsAirways = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery(
        // combine airports, fix, nav that matches match word and return 3 columns to show in the find result
        "      select LocationID, FacilityName, Type, ARPLongitude, ARPLatitude from airports where (LocationID like '$match%') "
        "union select LocationID, FacilityName, Type, ARPLongitude, ARPLatitude from nav      where (LocationID like '$match%') "
        "union select LocationID, FacilityName, Type, ARPLongitude, ARPLatitude from fix      where (LocationID like '$match%') "
        "order by Type asc"
      );
      mapsAirways = await db.rawQuery(
        "select name, sequence, Longitude, Latitude from airways where name = '$match' COLLATE NOCASE "
        "order by cast(sequence as integer) asc limit 1"
      );
    }

    List<Destination> ret = List.generate(maps.length, (i) {
      return Destination(
          locationID: maps[i]['LocationID'] as String,
          facilityName: maps[i]['FacilityName'] as String,
          type: maps[i]['Type'] as String,
          coordinate: LatLng(maps[i]['ARPLatitude'] as double, maps[i]['ARPLongitude'] as double),
      );
    });


    if(mapsAirways.isNotEmpty) {
      Destination d = Destination(
          locationID: mapsAirways[0]['name'] as String,
          facilityName: mapsAirways[0]['name'] as String,
          type: Destination.typeAirway,
          coordinate: LatLng(mapsAirways[0]['Latitude'] as double, mapsAirways[0]['Longitude'] as double),
        );
      ret.add(d);
    }

    return ret;
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

  Future<List<String>> findAlternates(String airport) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery(
          "      select File from takeoff   where LocationID = '$airport' "
          "union select File from alternate where LocationID = '$airport'");
    }
    return List.generate(maps.length, (i) {
      return maps[i]['File'] as String;
    });
  }

  Future<List<Destination>> findNear(LatLng point) async {
    final db = await database;
    List<Destination> ret = [];
    if (db != null) {
      num corrFactor = pow(cos(point.latitude * pi / 180.0), 2);
      String asDistance = "((ARPLongitude - ${point
          .longitude}) * (ARPLongitude - ${point.longitude}) * ${corrFactor
          .toDouble()} + (ARPLatitude - ${point
          .latitude}) * (ARPLatitude - ${point.latitude}))";

      String qry =
          "      select LocationID, ARPLatitude, ARPLongitude, FacilityName, Type, $asDistance as distance from airports where distance < 0.001 "
          "union select LocationID, ARPLatitude, ARPLongitude, FacilityName, Type, $asDistance as distance from nav      where distance < 0.001 "
          "union select LocationID, ARPLatitude, ARPLongitude, FacilityName, Type, $asDistance as distance from fix      where distance < 0.001 "
          "order by Type asc, distance asc";
      List<Map<String, dynamic>> maps = await db.rawQuery(qry);

      ret = List.generate(maps.length, (i) {
        return Destination(
            locationID: maps[i]['LocationID'] as String,
            facilityName: maps[i]['FacilityName'] as String,
            type: maps[i]['Type'] as String,
            coordinate: LatLng(maps[i]['ARPLatitude'] as double, maps[i]['ARPLongitude'] as double),
        );
      });
    }
    // always add touch point of GPS, GPS is not a database type so prefix with _
    String gps = Destination.formatSexagesimal(point.toSexagesimal());
    ret.add(Destination(locationID: gps, type: Destination.typeGps, facilityName: Destination.typeGps, coordinate: point));
    return(ret);
  }

  Future<Destination> findNearNavOrFixElseGps(LatLng point) async {
    final db = await database;
    List<Destination> ret = [];
    if (db != null) {
      num corrFactor = pow(cos(point.latitude * pi / 180.0), 2);
      String asDistance = "((ARPLongitude - ${point
          .longitude}) * (ARPLongitude - ${point.longitude}) * ${corrFactor
          .toDouble()} + (ARPLatitude - ${point
          .latitude}) * (ARPLatitude - ${point.latitude}))";

      String qry =
          "      select LocationID, ARPLatitude, ARPLongitude, FacilityName, Type, $asDistance as distance from nav      where distance < 0.001 "
          "union select LocationID, ARPLatitude, ARPLongitude, FacilityName, Type, $asDistance as distance from fix      where distance < 0.001 "
          "order by distance asc";
      List<Map<String, dynamic>> maps = await db.rawQuery(qry);

      return Destination(
        locationID: maps[0]['LocationID'] as String,
        facilityName: maps[0]['FacilityName'] as String,
        type: maps[0]['Type'] as String,
        coordinate: LatLng(maps[0]['ARPLatitude'] as double, maps[0]['ARPLongitude'] as double));
    }
    // always add touch point of GPS, GPS is not a database type so prefix with _
    String gps = Destination.formatSexagesimal(point.toSexagesimal());
    return Destination(locationID: gps, type: Destination.typeGps, facilityName: Destination.typeGps, coordinate: point);
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

    double elevation = 0;
    try {
      elevation = double.parse(mapsAirports[0]['ARPElevation'] as String);
    }
    catch(e) {}

    return AirportDestination(
        locationID: mapsAirports[0]['LocationID'] as String,
        elevation: elevation,
        facilityName: mapsAirports[0]['FacilityName'] as String,
        coordinate: LatLng(mapsAirports[0]['ARPLatitude'] as double, mapsAirports[0]['ARPLongitude'] as double),
        type: mapsAirports[0]['Type'] as String,
        ctaf: mapsAirports[0]['CTAFFrequency'] as String,
        unicom: mapsAirports[0]['UNICOMFrequencies'] as String,
        frequencies: mapsFreq,
        awos: mapsAwos,
        runways: mapsRunways
    );
  }

  Future<NavDestination?> findNav(String nav) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from nav where LocationID = '$nav'");
    }
    if(maps.isEmpty) {
      return null;
    }

    double elevation = 0;
    try {
      elevation = double.parse(maps[0]['Elevation'] as String);
    }
    catch(e) {}

    return NavDestination(
        locationID: maps[0]['LocationID'] as String,
        type: maps[0]['Type'] as String,
        facilityName: maps[0]['FacilityName'] as String,
        coordinate: LatLng(maps[0]['ARPLatitude'] as double, maps[0]['ARPLongitude'] as double),
        elevation: elevation,
        variation: maps[0]['Variation'] as int,
        hiwas: maps[0]['Hiwas'] as String,
        class_: maps[0]['Class'] as String,
    );
  }

  Future<FixDestination?> findFix(String fix) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from fix where LocationID = '$fix'");
    }
    if(maps.isEmpty) {
      return null;
    }

    return FixDestination(
      locationID: maps[0]['LocationID'] as String,
      type: maps[0]['Type'] as String,
      facilityName: maps[0]['FacilityName'] as String,
      coordinate: LatLng(maps[0]['ARPLatitude'] as double, maps[0]['ARPLongitude'] as double),
    );
  }

  Future<AirwayDestination?> findAirway(String airway) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select name, sequence, Longitude, Latitude from airways where name = '$airway' COLLATE NOCASE "
          "order by cast(sequence as integer) asc");
    }
    if(maps.isEmpty) {
      return null;
    }

    List<Destination> ret2 = List.generate(maps.length, (i) {
      return Destination(
        locationID: maps[i]['name'] as String,
        facilityName: maps[i]['name'] as String,
        type: Destination.typeAirway,
        coordinate: LatLng(maps[i]['Latitude'] as double, maps[i]['Longitude'] as double),
      );
    });

    if(ret2.isNotEmpty) { // add all airway points
      AirwayDestination airwayDestination = AirwayDestination(
          locationID: ret2[0].locationID,
          type: ret2[0].type,
          facilityName: ret2[0].facilityName,
          coordinate: ret2[0].coordinate,
          points: ret2);
      return airwayDestination;
    }

    return null;
  }


  Future<List<double>?> findAirportDiagramMatrix(String id) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from airportdiags where LocationID = '$id'");
    }
    if(maps.isEmpty) {
      return null;
    }

    List<double> ret = [];
    ret.add(maps[0]['tfwA'] as double);
    ret.add(maps[0]['tfwB'] as double);
    ret.add(maps[0]['tfwC'] as double);
    ret.add(maps[0]['tfwD'] as double);
    ret.add(maps[0]['tfwE'] as double);
    ret.add(maps[0]['tfwF'] as double);
    ret.add(maps[0]['wftA'] as double);
    ret.add(maps[0]['wftB'] as double);
    ret.add(maps[0]['wftC'] as double);
    ret.add(maps[0]['wftD'] as double);
    ret.add(maps[0]['wftE'] as double);
    ret.add(maps[0]['wftF'] as double);

    return ret;
  }

}


