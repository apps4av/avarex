// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_plan.dart';

// **************************************************************************
// RealmObjectGenerator
// **************************************************************************

// ignore_for_file: type=lint
class UserPlan extends _UserPlan
    with RealmEntity, RealmObjectBase, RealmObject {
  UserPlan(
    ObjectId id,
    String name,
    String route,
  ) {
    RealmObjectBase.set(this, '_id', id);
    RealmObjectBase.set(this, 'name', name);
    RealmObjectBase.set(this, 'route', route);
  }

  UserPlan._();

  @override
  ObjectId get id => RealmObjectBase.get<ObjectId>(this, '_id') as ObjectId;
  @override
  set id(ObjectId value) => RealmObjectBase.set(this, '_id', value);

  @override
  String get name => RealmObjectBase.get<String>(this, 'name') as String;
  @override
  set name(String value) => RealmObjectBase.set(this, 'name', value);

  @override
  String get route => RealmObjectBase.get<String>(this, 'route') as String;
  @override
  set route(String value) => RealmObjectBase.set(this, 'route', value);

  @override
  Stream<RealmObjectChanges<UserPlan>> get changes =>
      RealmObjectBase.getChanges<UserPlan>(this);

  @override
  UserPlan freeze() => RealmObjectBase.freezeObject<UserPlan>(this);

  EJsonValue toEJson() {
    return <String, dynamic>{
      '_id': id.toEJson(),
      'name': name.toEJson(),
      'route': route.toEJson(),
    };
  }

  static EJsonValue _toEJson(UserPlan value) => value.toEJson();
  static UserPlan _fromEJson(EJsonValue ejson) {
    return switch (ejson) {
      {
        '_id': EJsonValue id,
        'name': EJsonValue name,
        'route': EJsonValue route,
      } =>
        UserPlan(
          fromEJson(id),
          fromEJson(name),
          fromEJson(route),
        ),
      _ => raiseInvalidEJson(ejson),
    };
  }

  static final schema = () {
    RealmObjectBase.registerFactory(UserPlan._);
    register(_toEJson, _fromEJson);
    return SchemaObject(ObjectType.realmObject, UserPlan, 'UserPlan', [
      SchemaProperty('id', RealmPropertyType.objectid,
          mapTo: '_id', primaryKey: true),
      SchemaProperty('name', RealmPropertyType.string),
      SchemaProperty('route', RealmPropertyType.string),
    ]);
  }();

  @override
  SchemaObject get objectSchema => RealmObjectBase.getSchema(this) ?? schema;
}
