// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weather_tfr.dart';

// **************************************************************************
// RealmObjectGenerator
// **************************************************************************

// ignore_for_file: type=lint
class WeatherTfr extends _WeatherTfr
    with RealmEntity, RealmObjectBase, RealmObject {
  WeatherTfr(
    ObjectId id,
    String station,
    String coordinates,
    int utcMs,
    String upperAltitude,
    String lowerAltitude,
    int msEffective,
    int msExpires,
  ) {
    RealmObjectBase.set(this, '_id', id);
    RealmObjectBase.set(this, 'station', station);
    RealmObjectBase.set(this, 'coordinates', coordinates);
    RealmObjectBase.set(this, 'utcMs', utcMs);
    RealmObjectBase.set(this, 'upperAltitude', upperAltitude);
    RealmObjectBase.set(this, 'lowerAltitude', lowerAltitude);
    RealmObjectBase.set(this, 'msEffective', msEffective);
    RealmObjectBase.set(this, 'msExpires', msExpires);
  }

  WeatherTfr._();

  @override
  ObjectId get id => RealmObjectBase.get<ObjectId>(this, '_id') as ObjectId;
  @override
  set id(ObjectId value) => RealmObjectBase.set(this, '_id', value);

  @override
  String get station => RealmObjectBase.get<String>(this, 'station') as String;
  @override
  set station(String value) => RealmObjectBase.set(this, 'station', value);

  @override
  String get coordinates =>
      RealmObjectBase.get<String>(this, 'coordinates') as String;
  @override
  set coordinates(String value) =>
      RealmObjectBase.set(this, 'coordinates', value);

  @override
  int get utcMs => RealmObjectBase.get<int>(this, 'utcMs') as int;
  @override
  set utcMs(int value) => RealmObjectBase.set(this, 'utcMs', value);

  @override
  String get upperAltitude =>
      RealmObjectBase.get<String>(this, 'upperAltitude') as String;
  @override
  set upperAltitude(String value) =>
      RealmObjectBase.set(this, 'upperAltitude', value);

  @override
  String get lowerAltitude =>
      RealmObjectBase.get<String>(this, 'lowerAltitude') as String;
  @override
  set lowerAltitude(String value) =>
      RealmObjectBase.set(this, 'lowerAltitude', value);

  @override
  int get msEffective => RealmObjectBase.get<int>(this, 'msEffective') as int;
  @override
  set msEffective(int value) => RealmObjectBase.set(this, 'msEffective', value);

  @override
  int get msExpires => RealmObjectBase.get<int>(this, 'msExpires') as int;
  @override
  set msExpires(int value) => RealmObjectBase.set(this, 'msExpires', value);

  @override
  Stream<RealmObjectChanges<WeatherTfr>> get changes =>
      RealmObjectBase.getChanges<WeatherTfr>(this);

  @override
  WeatherTfr freeze() => RealmObjectBase.freezeObject<WeatherTfr>(this);

  EJsonValue toEJson() {
    return <String, dynamic>{
      '_id': id.toEJson(),
      'station': station.toEJson(),
      'coordinates': coordinates.toEJson(),
      'utcMs': utcMs.toEJson(),
      'upperAltitude': upperAltitude.toEJson(),
      'lowerAltitude': lowerAltitude.toEJson(),
      'msEffective': msEffective.toEJson(),
      'msExpires': msExpires.toEJson(),
    };
  }

  static EJsonValue _toEJson(WeatherTfr value) => value.toEJson();
  static WeatherTfr _fromEJson(EJsonValue ejson) {
    return switch (ejson) {
      {
        '_id': EJsonValue id,
        'station': EJsonValue station,
        'coordinates': EJsonValue coordinates,
        'utcMs': EJsonValue utcMs,
        'upperAltitude': EJsonValue upperAltitude,
        'lowerAltitude': EJsonValue lowerAltitude,
        'msEffective': EJsonValue msEffective,
        'msExpires': EJsonValue msExpires,
      } =>
        WeatherTfr(
          fromEJson(id),
          fromEJson(station),
          fromEJson(coordinates),
          fromEJson(utcMs),
          fromEJson(upperAltitude),
          fromEJson(lowerAltitude),
          fromEJson(msEffective),
          fromEJson(msExpires),
        ),
      _ => raiseInvalidEJson(ejson),
    };
  }

  static final schema = () {
    RealmObjectBase.registerFactory(WeatherTfr._);
    register(_toEJson, _fromEJson);
    return SchemaObject(ObjectType.realmObject, WeatherTfr, 'WeatherTfr', [
      SchemaProperty('id', RealmPropertyType.objectid,
          mapTo: '_id', primaryKey: true),
      SchemaProperty('station', RealmPropertyType.string),
      SchemaProperty('coordinates', RealmPropertyType.string),
      SchemaProperty('utcMs', RealmPropertyType.int),
      SchemaProperty('upperAltitude', RealmPropertyType.string),
      SchemaProperty('lowerAltitude', RealmPropertyType.string),
      SchemaProperty('msEffective', RealmPropertyType.int),
      SchemaProperty('msExpires', RealmPropertyType.int),
    ]);
  }();

  @override
  SchemaObject get objectSchema => RealmObjectBase.getSchema(this) ?? schema;
}
