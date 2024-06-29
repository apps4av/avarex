// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weather_taf.dart';

// **************************************************************************
// RealmObjectGenerator
// **************************************************************************

// ignore_for_file: type=lint
class WeatherTaf extends _WeatherTaf
    with RealmEntity, RealmObjectBase, RealmObject {
  WeatherTaf(
    ObjectId id,
    String station,
    String raw,
    int utcMs,
    double ARPLatitude,
    double ARPLongitude,
  ) {
    RealmObjectBase.set(this, '_id', id);
    RealmObjectBase.set(this, 'station', station);
    RealmObjectBase.set(this, 'raw', raw);
    RealmObjectBase.set(this, 'utcMs', utcMs);
    RealmObjectBase.set(this, 'ARPLatitude', ARPLatitude);
    RealmObjectBase.set(this, 'ARPLongitude', ARPLongitude);
  }

  WeatherTaf._();

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
  double get ARPLatitude =>
      RealmObjectBase.get<double>(this, 'ARPLatitude') as double;
  @override
  set ARPLatitude(double value) =>
      RealmObjectBase.set(this, 'ARPLatitude', value);

  @override
  double get ARPLongitude =>
      RealmObjectBase.get<double>(this, 'ARPLongitude') as double;
  @override
  set ARPLongitude(double value) =>
      RealmObjectBase.set(this, 'ARPLongitude', value);

  @override
  Stream<RealmObjectChanges<WeatherTaf>> get changes =>
      RealmObjectBase.getChanges<WeatherTaf>(this);

  @override
  WeatherTaf freeze() => RealmObjectBase.freezeObject<WeatherTaf>(this);

  EJsonValue toEJson() {
    return <String, dynamic>{
      '_id': id.toEJson(),
      'station': station.toEJson(),
      'raw': raw.toEJson(),
      'utcMs': utcMs.toEJson(),
      'ARPLatitude': ARPLatitude.toEJson(),
      'ARPLongitude': ARPLongitude.toEJson(),
    };
  }

  static EJsonValue _toEJson(WeatherTaf value) => value.toEJson();
  static WeatherTaf _fromEJson(EJsonValue ejson) {
    return switch (ejson) {
      {
        '_id': EJsonValue id,
        'station': EJsonValue station,
        'raw': EJsonValue raw,
        'utcMs': EJsonValue utcMs,
        'ARPLatitude': EJsonValue ARPLatitude,
        'ARPLongitude': EJsonValue ARPLongitude,
      } =>
        WeatherTaf(
          fromEJson(id),
          fromEJson(station),
          fromEJson(raw),
          fromEJson(utcMs),
          fromEJson(ARPLatitude),
          fromEJson(ARPLongitude),
        ),
      _ => raiseInvalidEJson(ejson),
    };
  }

  static final schema = () {
    RealmObjectBase.registerFactory(WeatherTaf._);
    register(_toEJson, _fromEJson);
    return SchemaObject(ObjectType.realmObject, WeatherTaf, 'WeatherTaf', [
      SchemaProperty('id', RealmPropertyType.objectid,
          mapTo: '_id', primaryKey: true),
      SchemaProperty('station', RealmPropertyType.string),
      SchemaProperty('raw', RealmPropertyType.string),
      SchemaProperty('utcMs', RealmPropertyType.int),
      SchemaProperty('ARPLatitude', RealmPropertyType.double),
      SchemaProperty('ARPLongitude', RealmPropertyType.double),
    ]);
  }();

  @override
  SchemaObject get objectSchema => RealmObjectBase.getSchema(this) ?? schema;
}
