// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weather_notam.dart';

// **************************************************************************
// RealmObjectGenerator
// **************************************************************************

// ignore_for_file: type=lint
class WeatherNotam extends _WeatherNotam
    with RealmEntity, RealmObjectBase, RealmObject {
  WeatherNotam(
    ObjectId id,
    String station,
    String text,
    int utcMs,
  ) {
    RealmObjectBase.set(this, '_id', id);
    RealmObjectBase.set(this, 'station', station);
    RealmObjectBase.set(this, 'text', text);
    RealmObjectBase.set(this, 'utcMs', utcMs);
  }

  WeatherNotam._();

  @override
  ObjectId get id => RealmObjectBase.get<ObjectId>(this, '_id') as ObjectId;
  @override
  set id(ObjectId value) => RealmObjectBase.set(this, '_id', value);

  @override
  String get station => RealmObjectBase.get<String>(this, 'station') as String;
  @override
  set station(String value) => RealmObjectBase.set(this, 'station', value);

  @override
  String get text => RealmObjectBase.get<String>(this, 'text') as String;
  @override
  set text(String value) => RealmObjectBase.set(this, 'text', value);

  @override
  int get utcMs => RealmObjectBase.get<int>(this, 'utcMs') as int;
  @override
  set utcMs(int value) => RealmObjectBase.set(this, 'utcMs', value);

  @override
  Stream<RealmObjectChanges<WeatherNotam>> get changes =>
      RealmObjectBase.getChanges<WeatherNotam>(this);

  @override
  WeatherNotam freeze() => RealmObjectBase.freezeObject<WeatherNotam>(this);

  EJsonValue toEJson() {
    return <String, dynamic>{
      '_id': id.toEJson(),
      'station': station.toEJson(),
      'text': text.toEJson(),
      'utcMs': utcMs.toEJson(),
    };
  }

  static EJsonValue _toEJson(WeatherNotam value) => value.toEJson();
  static WeatherNotam _fromEJson(EJsonValue ejson) {
    return switch (ejson) {
      {
        '_id': EJsonValue id,
        'station': EJsonValue station,
        'text': EJsonValue text,
        'utcMs': EJsonValue utcMs,
      } =>
        WeatherNotam(
          fromEJson(id),
          fromEJson(station),
          fromEJson(text),
          fromEJson(utcMs),
        ),
      _ => raiseInvalidEJson(ejson),
    };
  }

  static final schema = () {
    RealmObjectBase.registerFactory(WeatherNotam._);
    register(_toEJson, _fromEJson);
    return SchemaObject(ObjectType.realmObject, WeatherNotam, 'WeatherNotam', [
      SchemaProperty('id', RealmPropertyType.objectid,
          mapTo: '_id', primaryKey: true),
      SchemaProperty('station', RealmPropertyType.string),
      SchemaProperty('text', RealmPropertyType.string),
      SchemaProperty('utcMs', RealmPropertyType.int),
    ]);
  }();

  @override
  SchemaObject get objectSchema => RealmObjectBase.getSchema(this) ?? schema;
}
