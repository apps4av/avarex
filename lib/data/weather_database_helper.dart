import 'dart:async';
import 'dart:io';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/airsigmet.dart';
import 'package:avaremp/weather/taf.dart';
import 'package:avaremp/weather/tfr.dart';
import 'package:avaremp/weather/winds_aloft.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../weather/airep.dart';
import '../weather/metar.dart';
import '../weather/notam.dart';

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
          version: 1,
          onCreate: (Database db, int version) async {
            await db.execute("create table windsAloft ("
                "id            integer primary key autoincrement, "
                "station       text, "
                "utcMs         int, "
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
          onOpen: (db) {});
  }

  Future<void> addWindsAloft(WindsAloft wa) async {
    final db = await database;

    if (db != null) {
      await db.insert("windsAloft", wa.toMap());
    }
  }

  Future<void> addWindsAlofts(List<WindsAloft> wa) async {
    final db = await database;

    if (db != null && wa.isNotEmpty) {
      await db.transaction((txn) async {
        Batch batch = txn.batch();
        batch.delete("windsAloft");
        for(WindsAloft w in wa) {
          batch.insert("windsAloft", w.toMap());
        }
        await batch.commit();
      });
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
      await db.insert("metar", metar.toMap());
    }
  }

  Future<void> addMetars(List<Metar> metar) async {
    final db = await database;

    if (db != null && metar.isNotEmpty) {
      await db.transaction((txn) async {
        Batch batch = txn.batch();
        batch.delete("metar");
        for(Metar m in metar) {
          batch.insert("metar", m.toMap());
        }
        await batch.commit();
      });
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
      await db.insert("taf", taf.toMap());
    }
  }

  Future<void> addTafs(List<Taf> taf) async {
    final db = await database;

    if (db != null && taf.isNotEmpty) {
      await db.transaction((txn) async {
        Batch batch = txn.batch();
        batch.delete("taf");
        for(Taf t in taf) {
          batch.insert("taf", t.toMap());
        }
        await batch.commit();
      });
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
      await db.insert("tfr", tfr.toMap());
    }
  }

  Future<void> addTfrs(List<Tfr> tfr) async {
    final db = await database;

    if (db != null && tfr.isNotEmpty) {
      await db.transaction((txn) async {
        Batch batch = txn.batch();
        batch.delete("tfr");
        for(Tfr t in tfr) {
          batch.insert("tfr", t.toMap());
        }
        await batch.commit();
      });
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
      await db.transaction((txn) async {
        Batch batch = txn.batch();
        batch.delete("airep");
        for(Airep a in aireps) {
          batch.insert("airep", a.toMap());
        }
        await batch.commit();
      });
    }
  }

  Future<void> addAirep(Airep airep) async {
    final db = await database;

    if (db != null) {
      await db.insert("airep", airep.toMap());
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
      await db.transaction((txn) async {
        Batch batch = txn.batch();
        batch.delete("airsigmet");
        for(AirSigmet a in airSigmet) {
          batch.insert("airsigmet", a.toMap());
        }
        await batch.commit();
      });
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
      await db.insert("notam", notam.toMap());
    }
  }

}


