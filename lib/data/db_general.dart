import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
class DbGeneral {
  static void set() {
    // Initialize FFI
    if(Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    else if(kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
    }
    else {
      // macos, ios, and android, default SQFlite
    }
  }

  static Future<List<Map<String, Object?>>> query(Database db, String sql, {List<dynamic> params = const []}) async {
    // Guard with try/catch (not just onError): if the database was closed (e.g. during a
    // chart/database download), rawQuery throws synchronously via checkNotClosed before a
    // Future is ever created, so onError alone would let the exception escape.
    try {
      return await db.rawQuery(sql, params);
    }
    catch (error) {
      return [];
    }
  }

  static Future<int> insert(Database db, String table, Map<String, Object?> values) async {
    try {
      return await db.insert(table, values);
    }
    catch (error) {
      return -1;
    }
  }

  static Future<int> replace(Database db, String table, Map<String, Object?> values) async {
    try {
      return await db.insert(table, values, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    catch (error) {
      return -1;
    }
  }

  static Future<void> deleteAndInsertBatch(Database db, String table, List<dynamic> values) async {
    try {
      await db.transaction((txn) async {
        Batch batch = txn.batch();
        batch.delete(table);
        for(dynamic v in values) {
          batch.insert(table, v.toMap());
        }
        await batch.commit();
      });
    }
    catch (error) {
      // database may be closed (e.g. during a download) - ignore
    }
  }
}