import 'dart:async';
import 'dart:collection';

import 'package:avaremp/storage.dart';
import 'package:flutter_settings_screen_ex/flutter_settings_screen_ex.dart';

class SettingsCacheProvider extends SharePreferenceCache {

  final HashMap<String, String> _cache = HashMap();

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
    _cache.clear();
    // read into hashmap
    List<Map<String, dynamic>> maps = Storage().userRealmHelper.getAllSettings();
    for(Map<String, dynamic> map in maps) {
      _cache[map['key']] = map['value'];
    }
  }

  @override
  Future<void> remove(String key) {
    _cache.remove(key);
    Storage().userRealmHelper.deleteSetting(key);
    return Future.value();
  }

  @override
  Future<void> removeAll() {
    _cache.clear();
    Storage().userRealmHelper.deleteAllSettings();
    return Future.value();
  }

  @override
  Future<void> setBool(String key, bool? value) {
    _cache[key] = value.toString();
    Storage().userRealmHelper.insertSetting(key, value.toString());
    return Future.value();
  }

  @override
  Future<void> setDouble(String key, double? value) {
    _cache[key] = value.toString();
    Storage().userRealmHelper.insertSetting(key, value.toString());
    return Future.value();
  }

  @override
  Future<void> setInt(String key, int? value) {
    _cache[key] = value.toString();
    Storage().userRealmHelper.insertSetting(key, value.toString());
    return Future.value();
  }

  @override
  Future<void> setObject<T>(String key, T? value) {
    _cache[key] = value.toString();
    Storage().userRealmHelper.insertSetting(key, value.toString());
    return Future.value();
  }

  @override
  Future<void> setString(String key, String? value) {
    _cache[key] = value.toString();
    Storage().userRealmHelper.insertSetting(key, value.toString());
    return Future.value();
  }


}
