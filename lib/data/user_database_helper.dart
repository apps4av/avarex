import 'dart:async';
import 'dart:io';
import 'package:avaremp/aircraft.dart';
import 'package:avaremp/checklist.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/plan/plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/wnb.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';



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

            await db.execute("create table wnb ("
                "id           integer primary key autoincrement, "
                "name         text, "
                "aircraft     text, "
                "items        text, "
                "minX         float, "
                "minY         float, "
                "maxX         float, "
                "maxY         float, "
                "points       text, "
                "unique(name) on conflict replace);");

            await db.execute("create table checklist ("
                "id           integer primary key autoincrement, "
                "name         text, "
                "aircraft     text, "
                "items        text, "
                "unique(name) on conflict replace);");

            await db.execute("create table aircraft ("
                "id           integer primary key autoincrement, "
                "tail         text, "
                "type         text, "
                "wake         text, "
                "icao         text, "
                "equipment    text, "
                "cruiseTas    text, "
                "surveillance text, "
                "fuelEndurance text, "
                "color        text, "
                "pic          text, "
                "picInfo      text, "
                "sinkRate     text, "
                "fuelBurn     text, "
                "base         text, "
                "other        text, "
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


  Future<Wnb> getWnb(String name) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from wnb where name='$name'"); // most recent first
    }

    return Wnb.fromMap(maps[0]);
  }

  Future<void> addWnb(Wnb wnb) async {
    final db = await database;

    if (db != null) {
      await db.insert("wnb", wnb.toMap());
    }
  }

  Future<void> deleteWnb(String name) async {
    final db = await database;

    if (db != null) {
      await db.rawQuery("delete from wnb where name='$name'");
    }
  }

  Future<List<Wnb>> getAllWnb() async {
    final db = await database;
    List<Wnb> ret = [];
    if(db != null) {
      List<Map<String, dynamic>> maps = [];
      maps = await db.rawQuery("select * from wnb order by id desc"); // most recent first
      for(Map<String, dynamic> map in maps) {
        ret.add(Wnb.fromMap(map));
      }
    }
    return ret;
  }

  Future<void> addChecklist(Checklist checklist) async {
    final db = await database;

    if (db != null) {
      await db.insert("checklist", checklist.toMap());
    }
  }

  Future<void> deleteChecklist(String name) async {
    final db = await database;

    if (db != null) {
      await db.rawQuery("delete from checklist where name='$name'");
    }
  }

  Future<List<Checklist>> getAllChecklist() async {
    final db = await database;
    List<Checklist> ret = [];
    if(db != null) {
      List<Map<String, dynamic>> maps = [];
      maps = await db.rawQuery("select * from checklist order by id desc"); // most recent first

      for(Map<String, dynamic> map in maps) {
        ret.add(Checklist.fromMap(map));
      }
    }
    return ret;
  }

  Future<Checklist> getChecklist() async {
    final db = await database;
    List<Map<String, dynamic>> maps = [];
    if(db != null) {
      maps = await db.rawQuery("select * from checklist order by id desc"); // most recent first
    }
    return Checklist.fromMap(maps[0]);
  }

  Future<Aircraft> getAircraft(String name) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if(db != null) {
      maps = await db.rawQuery("select * from aircraft where tail='$name'"); // most recent first
    }
    return Aircraft.fromMap(maps[0]);
  }

  Future<void> addAircraft(Aircraft aircraft) async {
    final db = await database;

    if (db != null) {
      await db.insert("aircraft", aircraft.toMap());
    }
  }

  Future<void> deleteAircraft(String name) async {
    final db = await database;

    if (db != null) {
      await db.rawQuery("delete from aircraft where tail='$name'");
    }
  }

  Future<List<Aircraft>> getAllAircraft() async {
    final db = await database;
    List<Map<String, dynamic>> maps = [];
    List<Aircraft> ret = [];
    if (db != null) {
      maps = await db.rawQuery("select * from aircraft order by id desc"); // most recent first
    }

    for (Map<String, dynamic> map in maps) {
      ret.add(Aircraft.fromMap(map));
    }
    return ret;
  }

  Future<void> insertSetting(String key, String? value) async {
    final db = await database;

    if(db != null) {
      db.rawQuery("insert into settings (key, value) values ('$key', '$value')");
    }
  }

  Future<void> deleteSetting(String key) async {
    final db = await database;

    if(db != null) {
      await db.rawQuery("delete from settings where key=$key;");
    }
  }

  Future<List<Map<String, dynamic>>> getAllSettings() async {
    final db = await database;

    if(db != null) {
      List<Map<String, dynamic>> maps = await db.rawQuery("select * from settings;");
      return maps;
    }
    return [];
  }

}
