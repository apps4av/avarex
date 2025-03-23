import 'dart:async';
import 'dart:io';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/airep.dart';
import 'package:avaremp/weather/airsigmet.dart';
import 'package:avaremp/weather/metar.dart';
import 'package:avaremp/weather/notam.dart';
import 'package:avaremp/weather/taf.dart';
import 'package:avaremp/weather/tfr.dart';
import 'package:avaremp/weather/winds_aloft.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'db_general.dart';

class WeatherDatabaseHelper {
  WeatherDatabaseHelper._();

  static final WeatherDatabaseHelper _db = WeatherDatabaseHelper._();

  static WeatherDatabaseHelper get db => _db;
  static Database? _database;

  Future<Database?> get database async {
    if (_database != null) {
      return _database;
    }
    _database = await _initDB();
    return _database;
  }

  _initDB() async {
    Directory documentsDirectory = Directory(Storage().dataDir);
    String path = join(documentsDirectory.path, "weather.db"); // this is cache and can be versioned without fear of losing data
    return
      await openDatabase(
          path,
          version: 2,
          onCreate: (Database db, int version) async {
            await db.execute("create table windsAloft ("
                "id            integer primary key autoincrement, "
                "station       text, "
                "utcMs         int, "
                "w0k           text, "
                "w3k           text, "
                "w6k           text, "
                "w9k           text, "
                "w12k          text, "
                "w18k          text, "
                "w24k          text, "
                "w30k          text, "
                "w34k          text, "
                "w39k          text, "
                "unique(station) on conflict replace);");
            await db.execute("create table metar ("
                "id            integer primary key autoincrement, "
                "station       text, "
                "utcMs         int, "
                "raw           text, "
                "category      text, "
                "ARPLatitude   float, "
                "ARPLongitude  float, "
                "unique(station) on conflict replace);");
            await db.execute("create table taf ("
                "id            integer primary key autoincrement, "
                "station       text, "
                "utcMs         int, "
                "raw           text, "
                "ARPLatitude   float, "
                "ARPLongitude  float, "
                "unique(station) on conflict replace);");
            await db.execute("create table tfr ("
                "id            integer primary key autoincrement, "
                "station       text, "
                "utcMs         int, "
                "coordinates   text, "
                "upperAltitude text, "
                "lowerAltitude text, "
                "msEffective   int, "
                "msExpires     int, "
                "labelCoordinate int, "
                "unique(station) on conflict replace);");
            await db.execute("create table airep ("
                "id            integer primary key autoincrement, "
                "station       text, "
                "utcMs         int, "
                "raw           text, "
                "coordinates   text, "
                "unique(station) on conflict replace);");
            await db.execute("create table airsigmet ("
                "id            integer primary key autoincrement, "
                "station       text, "
                "utcMs         int, "
                "raw           text, "
                "coordinates   text, "
                "hazard        text, "
                "severity      text, "
                "type          text, "
                "unique(station) on conflict replace);");
            await db.execute("create table notam ("
                "id            integer primary key autoincrement, "
                "station       text, "
                "utcMs         int, "
                "raw           text, "
                "unique(station) on conflict replace);");
          },
          onOpen: (db) {},
          onUpgrade: (Database db, int oldVersion, int newVersion) async {
            if (oldVersion == 1 && newVersion == 2) {
              await db.execute("alter table windsAloft add column receivedMs    int default 0;");
              await db.execute("alter table metar      add column receivedMs    int default 0;");
              await db.execute("alter table taf        add column receivedMs    int default 0;");
              await db.execute("alter table tfr        add column receivedMs    int default 0;");
              await db.execute("alter table airep      add column receivedMs    int default 0;");
              await db.execute("alter table airsigmet  add column receivedMs    int default 0;");
              await db.execute("alter table notam      add column receivedMs    int default 0;");
              await db.execute("alter table windsAloft add column source        text default '';");
              await db.execute("alter table metar      add column source        text default '';");
              await db.execute("alter table taf        add column source        text default '';");
              await db.execute("alter table tfr        add column source        text default '';");
              await db.execute("alter table airep      add column source        text default '';");
              await db.execute("alter table airsigmet  add column source        text default '';");
              await db.execute("alter table notam      add column source        text default '';");
            }
          });
    }

  Future<void> addWindsAloft(WindsAloft wa) async {
    final db = await database;

    if (db != null) {
      await DbGeneral.insert(db, "windsAloft", wa.toMap());
    }
  }

  Future<void> addWindsAlofts(List<WindsAloft> wa) async {
    final db = await database;

    if (db != null && wa.isNotEmpty) {
      await DbGeneral.deleteAndInsertBatch(db, "windsAloft", wa);
    }
  }

  Future<WindsAloft?> getWindsAloft(String station) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from windsAloft where station='$station'");
      return WindsAloft.fromMap(maps[0]);
    }
    return null;
  }

  Future<List<WindsAloft>> getAllWindsAloft() async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from windsAloft");
      return List.generate(maps.length, (index) => WindsAloft.fromMap(maps[index]));
    }
    return [];
  }

  Future<void> deleteWindsAloft(String station) async {
    final db = await database;
    if (db != null) {
      await db.rawQuery("delete from windsAloft where station='$station'");
    }
  }

  Future<void> addMetar(Metar metar) async {
    final db = await database;

    if (db != null) {
      await DbGeneral.insert(db, "metar", metar.toMap());
    }
  }

  Future<void> addMetars(List<Metar> metar) async {
    final db = await database;

    if (db != null && metar.isNotEmpty) {
      await DbGeneral.deleteAndInsertBatch(db, "metar", metar);
    }
  }


  Future<Metar?> getMetar(String station) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from metar where station='$station'");
      return Metar.fromMap(maps[0]);
    }
    return null;
  }

  Future<List<Metar>> getAllMetar() async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from metar");
      return List.generate(maps.length, (index) => Metar.fromMap(maps[index]));
    }
    return [];
  }

  Future<void> deleteMetar(String station) async {
    final db = await database;
    if (db != null) {
      await db.rawQuery("delete from metar where station='$station'");
    }
  }


  Future<void> addTaf(Taf taf) async {
    final db = await database;

    if (db != null) {
      await DbGeneral.insert(db, "taf", taf.toMap());
    }
  }

  Future<void> addTafs(List<Taf> taf) async {
    final db = await database;

    if (db != null && taf.isNotEmpty) {
      await DbGeneral.deleteAndInsertBatch(db, "taf", taf);
    }
  }


  Future<Taf?> getTaf(String station) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from taf where station='$station'");
      return Taf.fromMap(maps[0]);
    }
    return null;
  }

  Future<List<Taf>> getAllTaf() async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from taf");
      return List.generate(maps.length, (index) => Taf.fromMap(maps[index]));
    }
    return [];
  }

  Future<void> deleteTaf(String station) async {
    final db = await database;
    if (db != null) {
      await db.rawQuery("delete from taf where station='$station'");
    }
  }

  Future<void> addTfr(Tfr tfr) async {
    final db = await database;

    if (db != null) {
      await DbGeneral.insert(db, "tfr", tfr.toMap());
    }
  }

  Future<void> addTfrs(List<Tfr> tfr) async {
    final db = await database;

    if(db != null && tfr.isNotEmpty) {
      await DbGeneral.deleteAndInsertBatch(db, "tfr", tfr);
    }
  }

  Future<Tfr?> getTfr(String station) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from tfr where station='$station'");
      return Tfr.fromMap(maps[0]);
    }
    return null;
  }

  Future<List<Tfr>> getAllTfr() async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from tfr");
      return List.generate(maps.length, (index) => Tfr.fromMap(maps[index]));
    }
    return [];
  }

  Future<void> deleteTfr(String station) async {
    final db = await database;
    if (db != null) {
      await db.rawQuery("delete from tfr where station='$station'");
    }
  }

  Future<List<Airep>> getAllAirep() async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from airep");
      return List.generate(maps.length, (index) => Airep.fromMap(maps[index]));
    }
    return [];
  }

  Future<void> addAireps(List<Airep> aireps) async {
    final db = await database;

    if (db != null && aireps.isNotEmpty) {
      await DbGeneral.deleteAndInsertBatch(db, "airep", aireps);
    }
  }

  Future<List<AirSigmet>> getAllAirSigmet() async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from airsigmet");
      return List.generate(maps.length, (index) => AirSigmet.fromMap(maps[index]));
    }
    return [];
  }

  Future<void> addAirSigmets(List<AirSigmet> airSigmet) async {
    final db = await database;

    if (db != null && airSigmet.isNotEmpty) {
      await DbGeneral.deleteAndInsertBatch(db, "airsigmet", airSigmet);
    }
  }

  Future<List<Notam>> getAllNotams() async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from notam");
      return List.generate(maps.length, (index) => Notam.fromMap(maps[index]));
    }
    return [];
  }

  Future<Notam?> getNotam(String station) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from notam where station='$station'");
      return Notam.fromMap(maps[0]);
    }
    return null;
  }

  Future<void> addNotam(Notam notam) async {
    final db = await database;

    if (db != null) {
      await DbGeneral.insert(db, "notam", notam.toMap());
    }
  }

}

