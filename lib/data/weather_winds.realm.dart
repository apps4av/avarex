// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weather_winds.dart';

// **************************************************************************
// RealmObjectGenerator
// **************************************************************************

// ignore_for_file: type=lint
class WeatherWinds extends _WeatherWinds
    with RealmEntity, RealmObjectBase, RealmObject {
  WeatherWinds(
    ObjectId id,
    String station,
    int utcMs,
    String w3k,
    String w6k,
    String w9k,
    String w12k,
    String w18k,
    String w24k,
    String w30k,
    String w34k,
    String w39k,
  ) {
    RealmObjectBase.set(this, '_id', id);
    RealmObjectBase.set(this, 'station', station);
    RealmObjectBase.set(this, 'utcMs', utcMs);
    RealmObjectBase.set(this, 'w3k', w3k);
    RealmObjectBase.set(this, 'w6k', w6k);
    RealmObjectBase.set(this, 'w9k', w9k);
    RealmObjectBase.set(this, 'w12k', w12k);
    RealmObjectBase.set(this, 'w18k', w18k);
    RealmObjectBase.set(this, 'w24k', w24k);
    RealmObjectBase.set(this, 'w30k', w30k);
    RealmObjectBase.set(this, 'w34k', w34k);
    RealmObjectBase.set(this, 'w39k', w39k);
  }

  WeatherWinds._();

  @override
  ObjectId get id => RealmObjectBase.get<ObjectId>(this, '_id') as ObjectId;
  @override
  set id(ObjectId value) => RealmObjectBase.set(this, '_id', value);

  @override
  String get station => RealmObjectBase.get<String>(this, 'station') as String;
  @override
  set station(String value) => RealmObjectBase.set(this, 'station', value);

  @override
  int get utcMs => RealmObjectBase.get<int>(this, 'utcMs') as int;
  @override
  set utcMs(int value) => RealmObjectBase.set(this, 'utcMs', value);

  @override
  String get w3k => RealmObjectBase.get<String>(this, 'w3k') as String;
  @override
  set w3k(String value) => RealmObjectBase.set(this, 'w3k', value);

  @override
  String get w6k => RealmObjectBase.get<String>(this, 'w6k') as String;
  @override
  set w6k(String value) => RealmObjectBase.set(this, 'w6k', value);

  @override
  String get w9k => RealmObjectBase.get<String>(this, 'w9k') as String;
  @override
  set w9k(String value) => RealmObjectBase.set(this, 'w9k', value);

  @override
  String get w12k => RealmObjectBase.get<String>(this, 'w12k') as String;
  @override
  set w12k(String value) => RealmObjectBase.set(this, 'w12k', value);

  @override
  String get w18k => RealmObjectBase.get<String>(this, 'w18k') as String;
  @override
  set w18k(String value) => RealmObjectBase.set(this, 'w18k', value);

  @override
  String get w24k => RealmObjectBase.get<String>(this, 'w24k') as String;
  @override
  set w24k(String value) => RealmObjectBase.set(this, 'w24k', value);

  @override
  String get w30k => RealmObjectBase.get<String>(this, 'w30k') as String;
  @override
  set w30k(String value) => RealmObjectBase.set(this, 'w30k', value);

  @override
  String get w34k => RealmObjectBase.get<String>(this, 'w34k') as String;
  @override
  set w34k(String value) => RealmObjectBase.set(this, 'w34k', value);

  @override
  String get w39k => RealmObjectBase.get<String>(this, 'w39k') as String;
  @override
  set w39k(String value) => RealmObjectBase.set(this, 'w39k', value);

  @override
  Stream<RealmObjectChanges<WeatherWinds>> get changes =>
      RealmObjectBase.getChanges<WeatherWinds>(this);

  @override
  WeatherWinds freeze() => RealmObjectBase.freezeObject<WeatherWinds>(this);

  EJsonValue toEJson() {
    return <String, dynamic>{
      '_id': id.toEJson(),
      'station': station.toEJson(),
      'utcMs': utcMs.toEJson(),
      'w3k': w3k.toEJson(),
      'w6k': w6k.toEJson(),
      'w9k': w9k.toEJson(),
      'w12k': w12k.toEJson(),
      'w18k': w18k.toEJson(),
      'w24k': w24k.toEJson(),
      'w30k': w30k.toEJson(),
      'w34k': w34k.toEJson(),
      'w39k': w39k.toEJson(),
    };
  }

  static EJsonValue _toEJson(WeatherWinds value) => value.toEJson();
  static WeatherWinds _fromEJson(EJsonValue ejson) {
    return switch (ejson) {
      {
        '_id': EJsonValue id,
        'station': EJsonValue station,
        'utcMs': EJsonValue utcMs,
        'w3k': EJsonValue w3k,
        'w6k': EJsonValue w6k,
        'w9k': EJsonValue w9k,
        'w12k': EJsonValue w12k,
        'w18k': EJsonValue w18k,
        'w24k': EJsonValue w24k,
        'w30k': EJsonValue w30k,
        'w34k': EJsonValue w34k,
        'w39k': EJsonValue w39k,
      } =>
        WeatherWinds(
          fromEJson(id),
          fromEJson(station),
          fromEJson(utcMs),
          fromEJson(w3k),
          fromEJson(w6k),
          fromEJson(w9k),
          fromEJson(w12k),
          fromEJson(w18k),
          fromEJson(w24k),
          fromEJson(w30k),
          fromEJson(w34k),
          fromEJson(w39k),
        ),
      _ => raiseInvalidEJson(ejson),
    };
  }

  static final schema = () {
    RealmObjectBase.registerFactory(WeatherWinds._);
    register(_toEJson, _fromEJson);
    return SchemaObject(ObjectType.realmObject, WeatherWinds, 'WeatherWinds', [
      SchemaProperty('id', RealmPropertyType.objectid,
          mapTo: '_id', primaryKey: true),
      SchemaProperty('station', RealmPropertyType.string),
      SchemaProperty('utcMs', RealmPropertyType.int),
      SchemaProperty('w3k', RealmPropertyType.string),
      SchemaProperty('w6k', RealmPropertyType.string),
      SchemaProperty('w9k', RealmPropertyType.string),
      SchemaProperty('w12k', RealmPropertyType.string),
      SchemaProperty('w18k', RealmPropertyType.string),
      SchemaProperty('w24k', RealmPropertyType.string),
      SchemaProperty('w30k', RealmPropertyType.string),
      SchemaProperty('w34k', RealmPropertyType.string),
      SchemaProperty('w39k', RealmPropertyType.string),
    ]);
  }();

  @override
  SchemaObject get objectSchema => RealmObjectBase.getSchema(this) ?? schema;
}
