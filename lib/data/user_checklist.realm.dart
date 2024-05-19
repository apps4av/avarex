// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_checklist.dart';

// **************************************************************************
// RealmObjectGenerator
// **************************************************************************

// ignore_for_file: type=lint
class UserChecklist extends _UserChecklist
    with RealmEntity, RealmObjectBase, RealmObject {
  UserChecklist(
    ObjectId id,
    String ownerId,
    String name,
    String aircraft,
    String steps,
  ) {
    RealmObjectBase.set(this, '_id', id);
    RealmObjectBase.set(this, 'owner_id', ownerId);
    RealmObjectBase.set(this, 'name', name);
    RealmObjectBase.set(this, 'aircraft', aircraft);
    RealmObjectBase.set(this, 'steps', steps);
  }

  UserChecklist._();

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
  String get aircraft => RealmObjectBase.get<String>(this, 'aircraft') as String;
  @override
  set aircraft(String value) => RealmObjectBase.set(this, 'aircraft', value);

  @override
  String get steps => RealmObjectBase.get<String>(this, 'steps') as String;
  @override
  set steps(String value) => RealmObjectBase.set(this, 'steps', value);

  @override
  Stream<RealmObjectChanges<UserChecklist>> get changes =>
      RealmObjectBase.getChanges<UserChecklist>(this);

  @override
  UserChecklist freeze() => RealmObjectBase.freezeObject<UserChecklist>(this);

  EJsonValue toEJson() {
    return <String, dynamic>{
      '_id': id.toEJson(),
      'owner_id': ownerId.toEJson(),
      'tail': name.toEJson(),
      'type': aircraft.toEJson(),
      'wake': steps.toEJson(),
    };
  }

  static EJsonValue _toEJson(UserChecklist value) => value.toEJson();
  static UserChecklist _fromEJson(EJsonValue ejson) {
    return switch (ejson) {
      {
        '_id': EJsonValue id,
        'owner_id': EJsonValue ownerId,
        'name': EJsonValue name,
        'aircraft': EJsonValue aircraft,
        'steps': EJsonValue steps,
      } =>
        UserChecklist(
          fromEJson(id),
          fromEJson(ownerId),
          fromEJson(name),
          fromEJson(aircraft),
          fromEJson(steps),
        ),
      _ => raiseInvalidEJson(ejson),
    };
  }

  static final schema = () {
    RealmObjectBase.registerFactory(UserChecklist._);
    register(_toEJson, _fromEJson);
    return SchemaObject(ObjectType.realmObject, UserChecklist, 'UserChecklist', [
      SchemaProperty('id', RealmPropertyType.objectid,
          mapTo: '_id', primaryKey: true),
      SchemaProperty('ownerId', RealmPropertyType.string, mapTo: 'owner_id'),
      SchemaProperty('name', RealmPropertyType.string),
      SchemaProperty('aircraft', RealmPropertyType.string),
      SchemaProperty('steps', RealmPropertyType.string),
    ]);
  }();

  @override
  SchemaObject get objectSchema => RealmObjectBase.getSchema(this) ?? schema;
}
