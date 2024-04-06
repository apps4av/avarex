// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_aircraft.dart';

// **************************************************************************
// RealmObjectGenerator
// **************************************************************************

// ignore_for_file: type=lint
class UserAircraft extends _UserAircraft
    with RealmEntity, RealmObjectBase, RealmObject {
  UserAircraft(
    ObjectId id,
    String ownerId,
    String tail,
    String type,
    String wake,
    String icao,
    String equipment,
    String cruiseTas,
    String surveillance,
    String fuelEndurance,
    String color,
    String pic,
    String picInfo,
    String sinkRate,
    String fuelBurn,
    String base,
    String other,
  ) {
    RealmObjectBase.set(this, '_id', id);
    RealmObjectBase.set(this, 'owner_id', ownerId);
    RealmObjectBase.set(this, 'tail', tail);
    RealmObjectBase.set(this, 'type', type);
    RealmObjectBase.set(this, 'wake', wake);
    RealmObjectBase.set(this, 'icao', icao);
    RealmObjectBase.set(this, 'equipment', equipment);
    RealmObjectBase.set(this, 'cruiseTas', cruiseTas);
    RealmObjectBase.set(this, 'surveillance', surveillance);
    RealmObjectBase.set(this, 'fuelEndurance', fuelEndurance);
    RealmObjectBase.set(this, 'color', color);
    RealmObjectBase.set(this, 'pic', pic);
    RealmObjectBase.set(this, 'picInfo', picInfo);
    RealmObjectBase.set(this, 'sinkRate', sinkRate);
    RealmObjectBase.set(this, 'fuelBurn', fuelBurn);
    RealmObjectBase.set(this, 'base', base);
    RealmObjectBase.set(this, 'other', other);
  }

  UserAircraft._();

  @override
  ObjectId get id => RealmObjectBase.get<ObjectId>(this, '_id') as ObjectId;
  @override
  set id(ObjectId value) => RealmObjectBase.set(this, '_id', value);

  @override
  String get ownerId => RealmObjectBase.get<String>(this, 'owner_id') as String;
  @override
  set ownerId(String value) => RealmObjectBase.set(this, 'owner_id', value);

  @override
  String get tail => RealmObjectBase.get<String>(this, 'tail') as String;
  @override
  set tail(String value) => RealmObjectBase.set(this, 'tail', value);

  @override
  String get type => RealmObjectBase.get<String>(this, 'type') as String;
  @override
  set type(String value) => RealmObjectBase.set(this, 'type', value);

  @override
  String get wake => RealmObjectBase.get<String>(this, 'wake') as String;
  @override
  set wake(String value) => RealmObjectBase.set(this, 'wake', value);

  @override
  String get icao => RealmObjectBase.get<String>(this, 'icao') as String;
  @override
  set icao(String value) => RealmObjectBase.set(this, 'icao', value);

  @override
  String get equipment =>
      RealmObjectBase.get<String>(this, 'equipment') as String;
  @override
  set equipment(String value) => RealmObjectBase.set(this, 'equipment', value);

  @override
  String get cruiseTas =>
      RealmObjectBase.get<String>(this, 'cruiseTas') as String;
  @override
  set cruiseTas(String value) => RealmObjectBase.set(this, 'cruiseTas', value);

  @override
  String get surveillance =>
      RealmObjectBase.get<String>(this, 'surveillance') as String;
  @override
  set surveillance(String value) =>
      RealmObjectBase.set(this, 'surveillance', value);

  @override
  String get fuelEndurance =>
      RealmObjectBase.get<String>(this, 'fuelEndurance') as String;
  @override
  set fuelEndurance(String value) =>
      RealmObjectBase.set(this, 'fuelEndurance', value);

  @override
  String get color => RealmObjectBase.get<String>(this, 'color') as String;
  @override
  set color(String value) => RealmObjectBase.set(this, 'color', value);

  @override
  String get pic => RealmObjectBase.get<String>(this, 'pic') as String;
  @override
  set pic(String value) => RealmObjectBase.set(this, 'pic', value);

  @override
  String get picInfo => RealmObjectBase.get<String>(this, 'picInfo') as String;
  @override
  set picInfo(String value) => RealmObjectBase.set(this, 'picInfo', value);

  @override
  String get sinkRate =>
      RealmObjectBase.get<String>(this, 'sinkRate') as String;
  @override
  set sinkRate(String value) => RealmObjectBase.set(this, 'sinkRate', value);

  @override
  String get fuelBurn =>
      RealmObjectBase.get<String>(this, 'fuelBurn') as String;
  @override
  set fuelBurn(String value) => RealmObjectBase.set(this, 'fuelBurn', value);

  @override
  String get base => RealmObjectBase.get<String>(this, 'base') as String;
  @override
  set base(String value) => RealmObjectBase.set(this, 'base', value);

  @override
  String get other => RealmObjectBase.get<String>(this, 'other') as String;
  @override
  set other(String value) => RealmObjectBase.set(this, 'other', value);

  @override
  Stream<RealmObjectChanges<UserAircraft>> get changes =>
      RealmObjectBase.getChanges<UserAircraft>(this);

  @override
  UserAircraft freeze() => RealmObjectBase.freezeObject<UserAircraft>(this);

  EJsonValue toEJson() {
    return <String, dynamic>{
      '_id': id.toEJson(),
      'owner_id': ownerId.toEJson(),
      'tail': tail.toEJson(),
      'type': type.toEJson(),
      'wake': wake.toEJson(),
      'icao': icao.toEJson(),
      'equipment': equipment.toEJson(),
      'cruiseTas': cruiseTas.toEJson(),
      'surveillance': surveillance.toEJson(),
      'fuelEndurance': fuelEndurance.toEJson(),
      'color': color.toEJson(),
      'pic': pic.toEJson(),
      'picInfo': picInfo.toEJson(),
      'sinkRate': sinkRate.toEJson(),
      'fuelBurn': fuelBurn.toEJson(),
      'base': base.toEJson(),
      'other': other.toEJson(),
    };
  }

  static EJsonValue _toEJson(UserAircraft value) => value.toEJson();
  static UserAircraft _fromEJson(EJsonValue ejson) {
    return switch (ejson) {
      {
        '_id': EJsonValue id,
        'owner_id': EJsonValue ownerId,
        'tail': EJsonValue tail,
        'type': EJsonValue type,
        'wake': EJsonValue wake,
        'icao': EJsonValue icao,
        'equipment': EJsonValue equipment,
        'cruiseTas': EJsonValue cruiseTas,
        'surveillance': EJsonValue surveillance,
        'fuelEndurance': EJsonValue fuelEndurance,
        'color': EJsonValue color,
        'pic': EJsonValue pic,
        'picInfo': EJsonValue picInfo,
        'sinkRate': EJsonValue sinkRate,
        'fuelBurn': EJsonValue fuelBurn,
        'base': EJsonValue base,
        'other': EJsonValue other,
      } =>
        UserAircraft(
          fromEJson(id),
          fromEJson(ownerId),
          fromEJson(tail),
          fromEJson(type),
          fromEJson(wake),
          fromEJson(icao),
          fromEJson(equipment),
          fromEJson(cruiseTas),
          fromEJson(surveillance),
          fromEJson(fuelEndurance),
          fromEJson(color),
          fromEJson(pic),
          fromEJson(picInfo),
          fromEJson(sinkRate),
          fromEJson(fuelBurn),
          fromEJson(base),
          fromEJson(other),
        ),
      _ => raiseInvalidEJson(ejson),
    };
  }

  static final schema = () {
    RealmObjectBase.registerFactory(UserAircraft._);
    register(_toEJson, _fromEJson);
    return SchemaObject(ObjectType.realmObject, UserAircraft, 'UserAircraft', [
      SchemaProperty('id', RealmPropertyType.objectid,
          mapTo: '_id', primaryKey: true),
      SchemaProperty('ownerId', RealmPropertyType.string, mapTo: 'owner_id'),
      SchemaProperty('tail', RealmPropertyType.string),
      SchemaProperty('type', RealmPropertyType.string),
      SchemaProperty('wake', RealmPropertyType.string),
      SchemaProperty('icao', RealmPropertyType.string),
      SchemaProperty('equipment', RealmPropertyType.string),
      SchemaProperty('cruiseTas', RealmPropertyType.string),
      SchemaProperty('surveillance', RealmPropertyType.string),
      SchemaProperty('fuelEndurance', RealmPropertyType.string),
      SchemaProperty('color', RealmPropertyType.string),
      SchemaProperty('pic', RealmPropertyType.string),
      SchemaProperty('picInfo', RealmPropertyType.string),
      SchemaProperty('sinkRate', RealmPropertyType.string),
      SchemaProperty('fuelBurn', RealmPropertyType.string),
      SchemaProperty('base', RealmPropertyType.string),
      SchemaProperty('other', RealmPropertyType.string),
    ]);
  }();

  @override
  SchemaObject get objectSchema => RealmObjectBase.getSchema(this) ?? schema;
}
