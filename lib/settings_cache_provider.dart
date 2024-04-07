import 'dart:async';

import 'package:avaremp/storage.dart';
import 'package:flutter_settings_screen_ex/flutter_settings_screen_ex.dart';

class SettingsCacheProvider extends SharePreferenceCache {

  @override
  bool containsKey(String key) {
    bool contains = getKeys().contains(key);
    return contains;
  }

  @override
  bool? getBool(String key, {bool? defaultValue}) {
    String? value = Storage().userSettingsRealmHelper.getSetting(key);
    return value == null ? defaultValue : value == "false" ? false : true;
  }

  @override
  double? getDouble(String key, {double? defaultValue}) {
    String? value = Storage().userSettingsRealmHelper.getSetting(key);
    return value == null ? defaultValue : double.parse(value);
  }

  @override
  int? getInt(String key, {int? defaultValue}) {
    String? value = Storage().userSettingsRealmHelper.getSetting(key);
    return value == null ? defaultValue : int.parse(value);
  }

  @override
  Set getKeys() {
    return Storage().userSettingsRealmHelper.getAllSettings().map((e) => e['key']).toSet();
  }

  @override
  String? getString(String key, {String? defaultValue}) {
    String? value = Storage().userSettingsRealmHelper.getSetting(key);
    return value ?? defaultValue;
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
  }

  @override
  Future<void> remove(String key) {
    Storage().userSettingsRealmHelper.deleteSetting(key);
    return Future.value();
  }

  @override
  Future<void> removeAll() {
    Storage().userSettingsRealmHelper.deleteAllSettings();
    return Future.value();
  }

  @override
  Future<void> setBool(String key, bool? value) {
    Storage().userSettingsRealmHelper.insertSetting(key, value.toString());
    return Future.value();
  }

  @override
  Future<void> setDouble(String key, double? value) {
    Storage().userSettingsRealmHelper.insertSetting(key, value.toString());
    return Future.value();
  }

  @override
  Future<void> setInt(String key, int? value) {
    Storage().userSettingsRealmHelper.insertSetting(key, value.toString());
    return Future.value();
  }

  @override
  Future<void> setObject<T>(String key, T? value) {
    Storage().userSettingsRealmHelper.insertSetting(key, value.toString());
    return Future.value();
  }

  @override
  Future<void> setString(String key, String? value) {
    Storage().userSettingsRealmHelper.insertSetting(key, value.toString());
    return Future.value();
  }


}
