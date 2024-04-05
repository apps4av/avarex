// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weather_metar.dart';

// **************************************************************************
// RealmObjectGenerator
// **************************************************************************

// ignore_for_file: type=lint
class WeatherMetar extends _WeatherMetar
    with RealmEntity, RealmObjectBase, RealmObject {
  WeatherMetar(
    ObjectId id,
    String station,
    String raw,
    int utcMs,
    String category,
    double ARPLatitude,
    double ARPLongitude,
  ) {
    RealmObjectBase.set(this, '_id', id);
    RealmObjectBase.set(this, 'station', station);
    RealmObjectBase.set(this, 'raw', raw);
    RealmObjectBase.set(this, 'utcMs', utcMs);
    RealmObjectBase.set(this, 'category', category);
    RealmObjectBase.set(this, 'ARPLatitude', ARPLatitude);
    RealmObjectBase.set(this, 'ARPLongitude', ARPLongitude);
  }

  WeatherMetar._();

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
  String get category =>
      RealmObjectBase.get<String>(this, 'category') as String;
  @override
  set category(String value) => RealmObjectBase.set(this, 'category', value);

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
  Stream<RealmObjectChanges<WeatherMetar>> get changes =>
      RealmObjectBase.getChanges<WeatherMetar>(this);

  @override
  WeatherMetar freeze() => RealmObjectBase.freezeObject<WeatherMetar>(this);

  EJsonValue toEJson() {
    return <String, dynamic>{
      '_id': id.toEJson(),
      'station': station.toEJson(),
      'raw': raw.toEJson(),
      'utcMs': utcMs.toEJson(),
      'category': category.toEJson(),
      'ARPLatitude': ARPLatitude.toEJson(),
      'ARPLongitude': ARPLongitude.toEJson(),
    };
  }

  static EJsonValue _toEJson(WeatherMetar value) => value.toEJson();
  static WeatherMetar _fromEJson(EJsonValue ejson) {
    return switch (ejson) {
      {
        '_id': EJsonValue id,
        'station': EJsonValue station,
        'raw': EJsonValue raw,
        'utcMs': EJsonValue utcMs,
        'category': EJsonValue category,
        'ARPLatitude': EJsonValue ARPLatitude,
        'ARPLongitude': EJsonValue ARPLongitude,
      } =>
        WeatherMetar(
          fromEJson(id),
          fromEJson(station),
          fromEJson(raw),
          fromEJson(utcMs),
          fromEJson(category),
          fromEJson(ARPLatitude),
          fromEJson(ARPLongitude),
        ),
      _ => raiseInvalidEJson(ejson),
    };
  }

  static final schema = () {
    RealmObjectBase.registerFactory(WeatherMetar._);
    register(_toEJson, _fromEJson);
    return SchemaObject(ObjectType.realmObject, WeatherMetar, 'WeatherMetar', [
      SchemaProperty('id', RealmPropertyType.objectid,
          mapTo: '_id', primaryKey: true),
      SchemaProperty('station', RealmPropertyType.string),
      SchemaProperty('raw', RealmPropertyType.string),
      SchemaProperty('utcMs', RealmPropertyType.int),
      SchemaProperty('category', RealmPropertyType.string),
      SchemaProperty('ARPLatitude', RealmPropertyType.double),
      SchemaProperty('ARPLongitude', RealmPropertyType.double),
    ]);
  }();

  @override
  SchemaObject get objectSchema => RealmObjectBase.getSchema(this) ?? schema;
}
