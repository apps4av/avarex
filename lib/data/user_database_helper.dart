import 'dart:async';
import 'dart:io';
import 'package:avaremp/plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../aircraft.dart';
import '../destination.dart';


class UserDatabaseHelper {
  UserDatabaseHelper._();

  static final UserDatabaseHelper _db = UserDatabaseHelper._();

  static UserDatabaseHelper get db => _db;
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
    String path = join(documentsDirectory.path, "user.db");
    return
      await openDatabase(
          path,
          version: 1,
          onCreate: (Database db, int version) async {
            await db.execute("create table recent ("
                "id           integer primary key autoincrement, "
                "LocationID   text, "
                "FacilityName text, "
                "Type         text, "
                "ARPLatitude  float, "
                "ARPLongitude float, "
                "unique(LocationID, Type) on conflict replace);");

            await db.execute("create table plan ("
                "id           integer primary key autoincrement, "
                "name         text, "
                "route        text, "
                "unique(name) on conflict replace);");

            await db.execute("create table settings ("
                "key          text primary key, "
                "value        text, "
                "unique(key)  on conflict replace);");

            await db.execute("create table aircraft ("
                "id            integer primary key autoincrement, "
                "tail          text, "
                "type          text, "
                "wake          text, "
                "icao          text, "
                "equipment     text, "
                "cruiseTas     text, "
                "surveillance  text, "
                "fuelEndurance text, "
                "color         text, "
                "pic           text, "
                "picInfo       text, "
                "sinkRate      text, "
                "fuelBurn      text, "
                "base          text, "
                "unique(tail) on conflict replace);");
          },
          onOpen: (db) {});
  }

  Future<void> addRecent(Destination recent) async {
    final db = await database;

    if (db != null) {
      await db.insert("recent", recent.toMap());
    }
  }

  Future<List<Destination>> getRecentAirports() async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from recent where "
          "Type='AIRPORT' or "
          "Type='HELIPORT' or "
          "Type='ULTRALIGHT' or "
          "Type='BALLOONPORT' order by id desc;");
      return List.generate(maps.length, (i) {
        return Destination.fromMap(maps[i]);
      });
    }
    return [];
  }

  Future<List<Destination>> getRecent() async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from recent order by id desc"); // most recent first
      return List.generate(maps.length, (i) {
        return Destination.fromMap(maps[i]);
      });
    }
    return [];
  }

  Future<void> deleteRecent(Destination destination) async {
    final db = await database;
    if (db != null) {
      await db.rawQuery("delete from recent where LocationID="
          "'${destination.locationID}' and Type='${destination.type}'");
    }
  }

  Future<void> addPlan(String name, PlanRoute route) async {
    final db = await database;

    if (db != null) { // do not add empty plans
      await db.insert("plan", route.toMap(name));
    }
  }

  Future<void> deletePlan(String name) async {
    final db = await database;

    if (db != null) {
      await db.rawQuery("delete from plan where name='$name'");
    }
  }

  Future<List<String>> getPlans() async {
    List<Map<String, dynamic>> maps = [];
    List<String> ret = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select name from plan order by id desc"); // most recent first
    }

    for(Map<String, dynamic> map in maps) {
      ret.add(map['name']);
    }
    return ret;
  }

  Future<PlanRoute> getPlan(String name, bool reverse) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from plan where name='$name'"); // most recent first
    }

    PlanRoute route = await PlanRoute.fromMap(maps[0], reverse);
    return route;
  }

  Future<void> addAircraft(Aircraft aircraft) async {
    final db = await database;

    if (db != null) { // do not add empty plans
      await db.insert("aircraft", aircraft.toMap());
    }
  }

  Future<void> deleteAircraft(String tail) async {
    final db = await database;

    if (db != null) {
      await db.rawQuery("delete from aircraft where tail='$tail'");
    }
  }

  Future<List<Aircraft>> getAllAircraft() async {
    List<Map<String, dynamic>> maps = [];
    List<Aircraft> ret = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from aircraft order by id desc"); // most recent first
    }

    for(Map<String, dynamic> map in maps) {
      ret.add(Aircraft.fromMap(map));
    }
    return ret;
  }

  Future<Aircraft> getAircraft(String tail) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from aircraft where tail='$tail'");
    }

    Aircraft aircraft = Aircraft.fromMap(maps[0]);
    return aircraft;
  }

  static Future<void> insertSetting(Database? db, String key, String? value) {
    Completer<void> completer = Completer();
    Map<String, String?> map = {};
    map[key] = value;

    if(db != null) {
      db.rawQuery("insert into settings (key, value) values ('$key', '$value')").then((value) => completer.complete());
    }
    return completer.future;
  }

  static Future<void> deleteSetting(Database? db, String key) {
    Completer<void> completer = Completer();

    if(db != null) {
      db.rawQuery("delete from settings where key=$key;").then((value) => completer.complete());
    }
    return completer.future;
  }

  static Future<void> deleteAllSettings(Database? db) {
    Completer<void> completer = Completer();

    if(db != null) {
      db.rawQuery("delete * settings;").then((value) => completer.complete());
    }
    return completer.future;
  }

  static Future<List<Map<String, dynamic>>> getAllSettings(Database? db) async {
    if(db != null) {
      List<Map<String, dynamic>> maps = await db.rawQuery("select * from settings;");
      return maps;
    }
    return [];
  }

}

