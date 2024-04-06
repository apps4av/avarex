// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_settings.dart';

// **************************************************************************
// RealmObjectGenerator
// **************************************************************************

// ignore_for_file: type=lint
class UserSettings extends _UserSettings
    with RealmEntity, RealmObjectBase, RealmObject {
  UserSettings(
    ObjectId id,
    String ownerId,
    String key,
    String value,
  ) {
    RealmObjectBase.set(this, '_id', id);
    RealmObjectBase.set(this, 'owner_id', ownerId);
    RealmObjectBase.set(this, 'key', key);
    RealmObjectBase.set(this, 'value', value);
  }

  UserSettings._();

  @override
  ObjectId get id => RealmObjectBase.get<ObjectId>(this, '_id') as ObjectId;
  @override
  set id(ObjectId value) => RealmObjectBase.set(this, '_id', value);

  @override
  String get ownerId => RealmObjectBase.get<String>(this, 'owner_id') as String;
  @override
  set ownerId(String value) => RealmObjectBase.set(this, 'owner_id', value);

  @override
  String get key => RealmObjectBase.get<String>(this, 'key') as String;
  @override
  set key(String value) => RealmObjectBase.set(this, 'key', value);

  @override
  String get value => RealmObjectBase.get<String>(this, 'value') as String;
  @override
  set value(String value) => RealmObjectBase.set(this, 'value', value);

  @override
  Stream<RealmObjectChanges<UserSettings>> get changes =>
      RealmObjectBase.getChanges<UserSettings>(this);

  @override
  UserSettings freeze() => RealmObjectBase.freezeObject<UserSettings>(this);

  EJsonValue toEJson() {
    return <String, dynamic>{
      '_id': id.toEJson(),
      'owner_id': ownerId.toEJson(),
      'key': key.toEJson(),
      'value': value.toEJson(),
    };
  }

  static EJsonValue _toEJson(UserSettings value) => value.toEJson();
  static UserSettings _fromEJson(EJsonValue ejson) {
    return switch (ejson) {
      {
        '_id': EJsonValue id,
        'owner_id': EJsonValue ownerId,
        'key': EJsonValue key,
        'value': EJsonValue value,
      } =>
        UserSettings(
          fromEJson(id),
          fromEJson(ownerId),
          fromEJson(key),
          fromEJson(value),
        ),
      _ => raiseInvalidEJson(ejson),
    };
  }

  static final schema = () {
    RealmObjectBase.registerFactory(UserSettings._);
    register(_toEJson, _fromEJson);
    return SchemaObject(ObjectType.realmObject, UserSettings, 'UserSettings', [
      SchemaProperty('id', RealmPropertyType.objectid,
          mapTo: '_id', primaryKey: true),
      SchemaProperty('ownerId', RealmPropertyType.string, mapTo: 'owner_id'),
      SchemaProperty('key', RealmPropertyType.string),
      SchemaProperty('value', RealmPropertyType.string),
    ]);
  }();

  @override
  SchemaObject get objectSchema => RealmObjectBase.getSchema(this) ?? schema;
}
