import 'dart:async';
import 'dart:io';
import 'package:avaremp/main_database_helper.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
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
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
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
                "unique(LocationID, Type) on conflict replace);");
          },
          onOpen: (db) {});
  }

  Future<void> addRecent(FindDestination recent) async {
    final db = await database;
    Map<String, Object?> map = {"LocationID": recent.locationID, "FacilityName" : recent.facilityName, "Type": recent.type};

    if (db != null) {
      await db.insert("recent", map);
    }
  }

  Future<List<FindDestination>> getRecentAirports() async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from recent where "
          "Type='AIRPORT' or "
          "Type='HELIPORT' or "
          "Type='ULTRALIGHT' or "
          "Type='BALLOONPORT' order by id desc;");
      return List.generate(maps.length, (i) {
        return FindDestination(
            locationID: maps[i]['LocationID'] as String,
            facilityName: maps[i]['FacilityName'] as String,
            type: maps[i]['Type'] as String
        );
      });
    }
    return [];
  }

  Future<List<FindDestination>> getRecent() async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select * from recent order by id desc"); // most recent first
      return List.generate(maps.length, (i) {
        return FindDestination(
            locationID: maps[i]['LocationID'] as String,
            facilityName: maps[i]['FacilityName'] as String,
            type: maps[i]['Type'] as String
        );
      });
    }
    return [];
  }

  Future<void> deleteRecent(FindDestination destination) async {
    final db = await database;
    if (db != null) {
      await db.rawQuery("delete from recent where LocationID="
          "\"${destination.locationID}\" and Type=\"${destination.type}\"");
    }
  }
}

