import 'dart:io';
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
}