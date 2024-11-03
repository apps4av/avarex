import 'dart:async';
import 'package:avaremp/data/user_database_helper.dart';

class SettingsCacheProvider {

  final Map<String, String?> _settings = {};

  bool containsKey(String key) {
    bool contains = _settings.containsKey(key);
    return contains;
  }

  bool? getBool(String key, {bool? defaultValue}) {
    String? value = _settings[key];
    return value == null ? defaultValue : value == "false" ? false : true;
  }

  double? getDouble(String key, {double? defaultValue}) {
    String? value = _settings[key];
    return value == null ? defaultValue : double.parse(value);
  }

  int? getInt(String key, {int? defaultValue}) {
    String? value = _settings[key];
    return value == null ? defaultValue : int.parse(value);
  }

  String? getString(String key, {String? defaultValue}) {
    String? value = _settings[key];
    return value ?? defaultValue;
  }

  Set getKeys() {
    return _settings.keys.toSet();
  }

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

  Future<void> init() async {
    List<Map<String, dynamic>> all = await UserDatabaseHelper.db.getAllSettings();
    for(var setting in all) {
      _settings[setting['key']] = setting['value'] as String?;
    }
  }

  Future<void> remove(String key) {
    _settings.remove(key);
    UserDatabaseHelper.db.deleteSetting(key);
    return Future.value();
  }

  Future<void> setBool(String key, bool? value) {
    _settings[key] = value.toString();
    UserDatabaseHelper.db.insertSetting(key, value.toString());
    return Future.value();
  }

  Future<void> setDouble(String key, double? value) {
    _settings[key] = value.toString();
    UserDatabaseHelper.db.insertSetting(key, value.toString());
    return Future.value();
  }

  Future<void> setInt(String key, int? value) {
    _settings[key] = value.toString();
    UserDatabaseHelper.db.insertSetting(key, value.toString());
    return Future.value();
  }

  Future<void> setObject<T>(String key, T? value) {
    _settings[key] = value.toString();
    UserDatabaseHelper.db.insertSetting(key, value.toString());
    return Future.value();
  }

  Future<void> setString(String key, String? value) {
    _settings[key] = value.toString();
    UserDatabaseHelper.db.insertSetting(key, value.toString());
    return Future.value();
  }


}
