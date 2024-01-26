import 'dart:async';
import 'dart:io';
import 'package:avaremp/winds_aloft.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

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
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, "weather.db");
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
          },
          onOpen: (db) {});
  }

  Future<void> addWindsAloft(WindsAloft wa) async {
    final db = await database;

    if (db != null) {
      await db.insert("windsAloft", wa.toMap());
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

}

