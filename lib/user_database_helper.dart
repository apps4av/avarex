import 'dart:async';
import 'dart:io';
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
                "id   integer primary key autoincrement, "
                "wid  text unique on conflict replace, "
                "type text, "
                "name text);");
          },
          onOpen: (db) {});
  }

  Future<void> addRecent(Recent recent) async {
    final db = await database;
    if (db != null) {
      await db.insert("recent", recent.toMap());
    }
  }

  Future<void> getRecent(Recent recent) async {
    final db = await database;
    if (db != null) {
      await db.insert("recent", recent.toMap());
    }
  }

}

class Recent {

  String wid;
  String type;
  String name;

  Recent(this.wid, this.type, this.name);

  Map<String, Object?> toMap() {
    var map = <String, Object?>{
      "wid":  wid,
      "type": type,
      "name": name
    };
    return map;
  }
}
