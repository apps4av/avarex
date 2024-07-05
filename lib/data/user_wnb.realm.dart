// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_wnb.dart';

// **************************************************************************
// RealmObjectGenerator
// **************************************************************************

// ignore_for_file: type=lint
class UserWnb extends _UserWnb with RealmEntity, RealmObjectBase, RealmObject {
  UserWnb(
    ObjectId id,
    String ownerId,
    String name,
    String aircraft,
    String items,
    double minX,
    double minY,
    double maxX,
    double maxY,
  ) {
    RealmObjectBase.set(this, '_id', id);
    RealmObjectBase.set(this, 'owner_id', ownerId);
    RealmObjectBase.set(this, 'name', name);
    RealmObjectBase.set(this, 'aircraft', aircraft);
    RealmObjectBase.set(this, 'items', items);
    RealmObjectBase.set(this, 'minX', minX);
    RealmObjectBase.set(this, 'minY', minY);
    RealmObjectBase.set(this, 'maxX', maxX);
    RealmObjectBase.set(this, 'maxY', maxY);
  }

  UserWnb._();

  @override
  ObjectId get id => RealmObjectBase.get<ObjectId>(this, '_id') as ObjectId;
  @override
  set id(ObjectId value) => RealmObjectBase.set(this, '_id', value);

  @override
  String get ownerId => RealmObjectBase.get<String>(this, 'owner_id') as String;
  @override
  set ownerId(String value) => RealmObjectBase.set(this, 'owner_id', value);

  @override
  String get name => RealmObjectBase.get<String>(this, 'name') as String;
  @override
  set name(String value) => RealmObjectBase.set(this, 'name', value);

  @override
  String get aircraft =>
      RealmObjectBase.get<String>(this, 'aircraft') as String;
  @override
  set aircraft(String value) => RealmObjectBase.set(this, 'aircraft', value);

  @override
  String get items => RealmObjectBase.get<String>(this, 'items') as String;
  @override
  set items(String value) => RealmObjectBase.set(this, 'items', value);

  @override
  double get minX => RealmObjectBase.get<double>(this, 'minX') as double;
  @override
  set minX(double value) => RealmObjectBase.set(this, 'minX', value);

  @override
  double get minY => RealmObjectBase.get<double>(this, 'minY') as double;
  @override
  set minY(double value) => RealmObjectBase.set(this, 'minY', value);

  @override
  double get maxX => RealmObjectBase.get<double>(this, 'maxX') as double;
  @override
  set maxX(double value) => RealmObjectBase.set(this, 'maxX', value);

  @override
  double get maxY => RealmObjectBase.get<double>(this, 'maxY') as double;
  @override
  set maxY(double value) => RealmObjectBase.set(this, 'maxY', value);

  @override
  Stream<RealmObjectChanges<UserWnb>> get changes =>
      RealmObjectBase.getChanges<UserWnb>(this);

  @override
  Stream<RealmObjectChanges<UserWnb>> changesFor([List<String>? keyPaths]) =>
      RealmObjectBase.getChangesFor<UserWnb>(this, keyPaths);

  @override
  UserWnb freeze() => RealmObjectBase.freezeObject<UserWnb>(this);

  EJsonValue toEJson() {
    return <String, dynamic>{
      '_id': id.toEJson(),
      'owner_id': ownerId.toEJson(),
      'name': name.toEJson(),
      'aircraft': aircraft.toEJson(),
      'items': items.toEJson(),
      'minX': minX.toEJson(),
      'minY': minY.toEJson(),
      'maxX': maxX.toEJson(),
      'maxY': maxY.toEJson(),
    };
  }

  static EJsonValue _toEJson(UserWnb value) => value.toEJson();
  static UserWnb _fromEJson(EJsonValue ejson) {
    return switch (ejson) {
      {
        '_id': EJsonValue id,
        'owner_id': EJsonValue ownerId,
        'name': EJsonValue name,
        'aircraft': EJsonValue aircraft,
        'items': EJsonValue items,
        'minX': EJsonValue minX,
        'minY': EJsonValue minY,
        'maxX': EJsonValue maxX,
        'maxY': EJsonValue maxY,
      } =>
        UserWnb(
          fromEJson(id),
          fromEJson(ownerId),
          fromEJson(name),
          fromEJson(aircraft),
          fromEJson(items),
          fromEJson(minX),
          fromEJson(minY),
          fromEJson(maxX),
          fromEJson(maxY),
        ),
      _ => raiseInvalidEJson(ejson),
    };
  }

  static final schema = () {
    RealmObjectBase.registerFactory(UserWnb._);
    register(_toEJson, _fromEJson);
    return SchemaObject(ObjectType.realmObject, UserWnb, 'UserWnb', [
      SchemaProperty('id', RealmPropertyType.objectid,
          mapTo: '_id', primaryKey: true),
      SchemaProperty('ownerId', RealmPropertyType.string, mapTo: 'owner_id'),
      SchemaProperty('name', RealmPropertyType.string),
      SchemaProperty('aircraft', RealmPropertyType.string),
      SchemaProperty('items', RealmPropertyType.string),
      SchemaProperty('minX', RealmPropertyType.double),
      SchemaProperty('minY', RealmPropertyType.double),
      SchemaProperty('maxX', RealmPropertyType.double),
      SchemaProperty('maxY', RealmPropertyType.double),
    ]);
  }();

  @override
  SchemaObject get objectSchema => RealmObjectBase.getSchema(this) ?? schema;
}
