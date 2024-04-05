// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'weather_airsigmet.dart';

// **************************************************************************
// RealmObjectGenerator
// **************************************************************************

// ignore_for_file: type=lint
class WeatherAirSigmet extends _WeatherAirSigmet
    with RealmEntity, RealmObjectBase, RealmObject {
  WeatherAirSigmet(
    ObjectId id,
    String station,
    String text,
    int utcMs,
    String raw,
    String coordinates,
    String hazard,
    String severity,
    String type,
  ) {
    RealmObjectBase.set(this, '_id', id);
    RealmObjectBase.set(this, 'station', station);
    RealmObjectBase.set(this, 'text', text);
    RealmObjectBase.set(this, 'utcMs', utcMs);
    RealmObjectBase.set(this, 'raw', raw);
    RealmObjectBase.set(this, 'coordinates', coordinates);
    RealmObjectBase.set(this, 'hazard', hazard);
    RealmObjectBase.set(this, 'severity', severity);
    RealmObjectBase.set(this, 'type', type);
  }

  WeatherAirSigmet._();

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
  String get raw => RealmObjectBase.get<String>(this, 'raw') as String;
  @override
  set raw(String value) => RealmObjectBase.set(this, 'raw', value);

  @override
  String get coordinates =>
      RealmObjectBase.get<String>(this, 'coordinates') as String;
  @override
  set coordinates(String value) =>
      RealmObjectBase.set(this, 'coordinates', value);

  @override
  String get hazard => RealmObjectBase.get<String>(this, 'hazard') as String;
  @override
  set hazard(String value) => RealmObjectBase.set(this, 'hazard', value);

  @override
  String get severity =>
      RealmObjectBase.get<String>(this, 'severity') as String;
  @override
  set severity(String value) => RealmObjectBase.set(this, 'severity', value);

  @override
  String get type => RealmObjectBase.get<String>(this, 'type') as String;
  @override
  set type(String value) => RealmObjectBase.set(this, 'type', value);

  @override
  Stream<RealmObjectChanges<WeatherAirSigmet>> get changes =>
      RealmObjectBase.getChanges<WeatherAirSigmet>(this);

  @override
  WeatherAirSigmet freeze() =>
      RealmObjectBase.freezeObject<WeatherAirSigmet>(this);

  EJsonValue toEJson() {
    return <String, dynamic>{
      '_id': id.toEJson(),
      'station': station.toEJson(),
      'text': text.toEJson(),
      'utcMs': utcMs.toEJson(),
      'raw': raw.toEJson(),
      'coordinates': coordinates.toEJson(),
      'hazard': hazard.toEJson(),
      'severity': severity.toEJson(),
      'type': type.toEJson(),
    };
  }

  static EJsonValue _toEJson(WeatherAirSigmet value) => value.toEJson();
  static WeatherAirSigmet _fromEJson(EJsonValue ejson) {
    return switch (ejson) {
      {
        '_id': EJsonValue id,
        'station': EJsonValue station,
        'text': EJsonValue text,
        'utcMs': EJsonValue utcMs,
        'raw': EJsonValue raw,
        'coordinates': EJsonValue coordinates,
        'hazard': EJsonValue hazard,
        'severity': EJsonValue severity,
        'type': EJsonValue type,
      } =>
        WeatherAirSigmet(
          fromEJson(id),
          fromEJson(station),
          fromEJson(text),
          fromEJson(utcMs),
          fromEJson(raw),
          fromEJson(coordinates),
          fromEJson(hazard),
          fromEJson(severity),
          fromEJson(type),
        ),
      _ => raiseInvalidEJson(ejson),
    };
  }

  static final schema = () {
    RealmObjectBase.registerFactory(WeatherAirSigmet._);
    register(_toEJson, _fromEJson);
    return SchemaObject(
        ObjectType.realmObject, WeatherAirSigmet, 'WeatherAirSigmet', [
      SchemaProperty('id', RealmPropertyType.objectid,
          mapTo: '_id', primaryKey: true),
      SchemaProperty('station', RealmPropertyType.string),
      SchemaProperty('text', RealmPropertyType.string),
      SchemaProperty('utcMs', RealmPropertyType.int),
      SchemaProperty('raw', RealmPropertyType.string),
      SchemaProperty('coordinates', RealmPropertyType.string),
      SchemaProperty('hazard', RealmPropertyType.string),
      SchemaProperty('severity', RealmPropertyType.string),
      SchemaProperty('type', RealmPropertyType.string),
    ]);
  }();

  @override
  SchemaObject get objectSchema => RealmObjectBase.getSchema(this) ?? schema;
}
