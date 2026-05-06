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
    var ret = db.rawQuery(sql, params).onError((error, stackTrace) {
      return [];
    });
    return ret;
  }

  static Future<int> insert(Database db, String table, Map<String, Object?> values) async {
    var ret = db.insert(table, values).onError((error, stackTrace) {
        return -1;
      }
    );
    return ret;
  }

  static Future<int> replace(Database db, String table, Map<String, Object?> values) async {
    var ret = db.insert(table, values, conflictAlgorithm: ConflictAlgorithm.replace).onError((error, stackTrace) {
      return -1;
    }
    );
    return ret;
  }

  static Future<void> deleteAndInsertBatch(Database db, String table, List<dynamic> values) async {
    await db.transaction((txn) async {
      Batch batch = txn.batch();
      batch.delete(table);
      for(dynamic v in values) {
        batch.insert(table, v.toMap());
      }
      await batch.commit().onError((error, stackTrace) {
        return [];
      });
    });
  }
}