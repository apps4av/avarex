import 'dart:async';
import 'dart:io';
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
        "      select LocationID, FacilityName, Type from airports where LocationID like \"$match%\" "
        "UNION select LocationID, FacilityName, Type from nav      where LocationID like \"$match%\" "
        "UNION select LocationID, FacilityName, Type from fix      where LocationID like \"$match%\" "
        "ORDER BY LocationID ASC"
      );
    }
    return List.generate(maps.length, (i) {
      return FindDestination(
          id: maps[i]['LocationID'] as String,
          name: maps[i]['FacilityName'] as String,
          type: maps[i]['Type'] as String
      );
    });
  }

  Future<List<String>> findCsup(String airport) async {
    List<Map<String, dynamic>> maps = [];
    final db = await database;
    if (db != null) {
      maps = await db.rawQuery("select File from afd where LocationID = \"$airport\"");
    }
    return List.generate(maps.length, (i) {
      return maps[i]['File'] as String;
    });
  }

}

class FindDestination {
  final String id;
  final String type;
  final String name;

  const FindDestination({
    required this.id,
    required this.name,
    required this.type,
  });
}