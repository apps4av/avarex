// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weather_airep.dart';

// **************************************************************************
// RealmObjectGenerator
// **************************************************************************

// ignore_for_file: type=lint
class WeatherAirep extends _WeatherAirep
    with RealmEntity, RealmObjectBase, RealmObject {
  WeatherAirep(
    ObjectId id,
    String station,
    String raw,
    int utcMs,
    String coordinates,
  ) {
    RealmObjectBase.set(this, '_id', id);
    RealmObjectBase.set(this, 'station', station);
    RealmObjectBase.set(this, 'raw', raw);
    RealmObjectBase.set(this, 'utcMs', utcMs);
    RealmObjectBase.set(this, 'coordinates', coordinates);
  }

  WeatherAirep._();

  @override
  ObjectId get id => RealmObjectBase.get<ObjectId>(this, '_id') as ObjectId;
  @override
  set id(ObjectId value) => RealmObjectBase.set(this, '_id', value);

  @override
  String get station => RealmObjectBase.get<String>(this, 'station') as String;
  @override
  set station(String value) => RealmObjectBase.set(this, 'station', value);

  @override
  String get raw => RealmObjectBase.get<String>(this, 'raw') as String;
  @override
  set raw(String value) => RealmObjectBase.set(this, 'raw', value);

  @override
  int get utcMs => RealmObjectBase.get<int>(this, 'utcMs') as int;
  @override
  set utcMs(int value) => RealmObjectBase.set(this, 'utcMs', value);

  @override
  String get coordinates =>
      RealmObjectBase.get<String>(this, 'coordinates') as String;
  @override
  set coordinates(String value) =>
      RealmObjectBase.set(this, 'coordinates', value);

  @override
  Stream<RealmObjectChanges<WeatherAirep>> get changes =>
      RealmObjectBase.getChanges<WeatherAirep>(this);

  @override
  WeatherAirep freeze() => RealmObjectBase.freezeObject<WeatherAirep>(this);

  EJsonValue toEJson() {
    return <String, dynamic>{
      '_id': id.toEJson(),
      'station': station.toEJson(),
      'raw': raw.toEJson(),
      'utcMs': utcMs.toEJson(),
      'coordinates': coordinates.toEJson(),
    };
  }

  static EJsonValue _toEJson(WeatherAirep value) => value.toEJson();
  static WeatherAirep _fromEJson(EJsonValue ejson) {
    return switch (ejson) {
      {
        '_id': EJsonValue id,
        'station': EJsonValue station,
        'raw': EJsonValue raw,
        'utcMs': EJsonValue utcMs,
        'coordinates': EJsonValue coordinates,
      } =>
        WeatherAirep(
          fromEJson(id),
          fromEJson(station),
          fromEJson(raw),
          fromEJson(utcMs),
          fromEJson(coordinates),
        ),
      _ => raiseInvalidEJson(ejson),
    };
  }

  static final schema = () {
    RealmObjectBase.registerFactory(WeatherAirep._);
    register(_toEJson, _fromEJson);
    return SchemaObject(ObjectType.realmObject, WeatherAirep, 'WeatherAirep', [
      SchemaProperty('id', RealmPropertyType.objectid,
          mapTo: '_id', primaryKey: true),
      SchemaProperty('station', RealmPropertyType.string),
      SchemaProperty('raw', RealmPropertyType.string),
      SchemaProperty('utcMs', RealmPropertyType.int),
      SchemaProperty('coordinates', RealmPropertyType.string),
    ]);
  }();

  @override
  SchemaObject get objectSchema => RealmObjectBase.getSchema(this) ?? schema;
}
