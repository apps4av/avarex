import 'dart:async';
import 'dart:collection';

import 'package:avaremp/user_database_helper.dart';
import 'package:flutter_settings_screen_ex/flutter_settings_screen_ex.dart';
import 'package:sqflite/sqflite.dart';

class SettingsCacheProvider extends SharePreferenceCache {

  final HashMap<String, String> _cache = HashMap();
  Database? _db;

  @override
  bool containsKey(String key) {
    bool contains = _cache.containsKey(key);
    return contains;
  }

  @override
  bool? getBool(String key, {bool? defaultValue}) {
    return _cache[key] == null ? defaultValue : _cache[key] == "false" ? false : true;
  }

  @override
  double? getDouble(String key, {double? defaultValue}) {
    return _cache[key] == null ? defaultValue : double.parse(_cache[key]!);
  }

  @override
  int? getInt(String key, {int? defaultValue}) {
    return _cache[key] == null ? defaultValue : int.parse(_cache[key]!);
  }

  @override
  Set getKeys() {
    return _cache.keys.toSet();
  }

  @override
  String? getString(String key, {String? defaultValue}) {
    return _cache[key] == null ? defaultValue : _cache[key]!;
  }

  @override
  T? getValue<T>(String key, {T? defaultValue}) {

    if(T == double) {
      return getDouble(key, defaultValue : defaultValue as double) as T;
    }
    else if(T == String) {
      return getString(key, defaultValue : defaultValue as String) as T;
    }
    else if(T == bool) {
      return getBool(key, defaultValue : defaultValue as bool) as T;
    }
    else if(T == int) {
      return getInt(key, defaultValue : defaultValue as int) as T;
    }
    return defaultValue;
  }

  @override
  Future<void> init() async {
    _db = await UserDatabaseHelper.db.database;
    _cache.clear();
    // read into hashmap
    List<Map<String, dynamic>> maps = await UserDatabaseHelper.getAllSettings(_db);
    for(Map<String, dynamic> map in maps) {
      _cache[map['key']] = map['value'];
    }
  }

  @override
  Future<void> remove(String key) {
    _cache.remove(key);
    return UserDatabaseHelper.deleteSetting(_db, key);
  }

  @override
  Future<void> removeAll() {
    _cache.clear();
    return UserDatabaseHelper.deleteAllSettings(_db);
  }

  @override
  Future<void> setBool(String key, bool? value) {
    _cache[key] = value.toString();
    return UserDatabaseHelper.insertSetting(_db, key, value.toString());
  }

  @override
  Future<void> setDouble(String key, double? value) {
    _cache[key] = value.toString();
    return UserDatabaseHelper.insertSetting(_db, key, value.toString());
  }

  @override
  Future<void> setInt(String key, int? value) {
    _cache[key] = value.toString();
    return UserDatabaseHelper.insertSetting(_db, key, value.toString());
  }

  @override
  Future<void> setObject<T>(String key, T? value) {
    _cache[key] = value.toString();
    return UserDatabaseHelper.insertSetting(_db, key, value.toString());
  }

  @override
  Future<void> setString(String key, String? value) {
    _cache[key] = value.toString();
    return UserDatabaseHelper.insertSetting(_db, key, value.toString());
  }


}
