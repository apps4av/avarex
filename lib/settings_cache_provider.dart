import 'dart:async';
import 'package:avaremp/storage.dart';

import 'data/realm_helper.dart';

class SettingsCacheProvider {

  final RealmHelper _userSettingsRealmHelper = Storage().realmHelper;

  bool containsKey(String key) {
    bool contains = getKeys().contains(key);
    return contains;
  }

  bool? getBool(String key, {bool? defaultValue}) {
    String? value = _userSettingsRealmHelper.getSetting(key);
    return value == null ? defaultValue : value == "false" ? false : true;
  }

  double? getDouble(String key, {double? defaultValue}) {
    String? value = _userSettingsRealmHelper.getSetting(key);
    return value == null ? defaultValue : double.parse(value);
  }

  int? getInt(String key, {int? defaultValue}) {
    String? value = _userSettingsRealmHelper.getSetting(key);
    return value == null ? defaultValue : int.parse(value);
  }

  Set getKeys() {
    return _userSettingsRealmHelper.getAllSettings().map((e) => e['key']).toSet();
  }

  String? getString(String key, {String? defaultValue}) {
    String? value = _userSettingsRealmHelper.getSetting(key);
    return value ?? defaultValue;
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
    return Future.value();
  }

  Future<void> remove(String key) {
    _userSettingsRealmHelper.deleteSetting(key);
    return Future.value();
  }

  Future<void> removeAll() {
    _userSettingsRealmHelper.deleteAllSettings();
    return Future.value();
  }

  Future<void> setBool(String key, bool? value) {
    _userSettingsRealmHelper.insertSetting(key, value.toString());
    return Future.value();
  }

  Future<void> setDouble(String key, double? value) {
    _userSettingsRealmHelper.insertSetting(key, value.toString());
    return Future.value();
  }

  Future<void> setInt(String key, int? value) {
    _userSettingsRealmHelper.insertSetting(key, value.toString());
    return Future.value();
  }

  Future<void> setObject<T>(String key, T? value) {
    _userSettingsRealmHelper.insertSetting(key, value.toString());
    return Future.value();
  }

  Future<void> setString(String key, String? value) {
    _userSettingsRealmHelper.insertSetting(key, value.toString());
    return Future.value();
  }


}
