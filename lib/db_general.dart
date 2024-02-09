// if using FFI, set sqflite_ffi in yaml
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
class DbGeneral {
  static void set() {
    // Initialize FFI
    if(Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }
}