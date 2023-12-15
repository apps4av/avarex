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
          version: 2,
          onCreate: (Database db, int version) async {
            await db.execute("create table recent ("
                "LocationID   text unique primary key on conflict replace, "
                "FacilityName text, "
                "Type         text);");
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
          "Type='BALLOONPORT';");
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
}

