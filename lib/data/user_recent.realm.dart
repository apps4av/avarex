// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_recent.dart';

// **************************************************************************
// RealmObjectGenerator
// **************************************************************************

// ignore_for_file: type=lint
class UserRecent extends _UserRecent
    with RealmEntity, RealmObjectBase, RealmObject {
  UserRecent(
    ObjectId id,
    String ownerId,
    String locationID,
    String facilityName,
    String type,
    double latitude,
    double longitude,
  ) {
    RealmObjectBase.set(this, '_id', id);
    RealmObjectBase.set(this, 'owner_id', ownerId);
    RealmObjectBase.set(this, 'locationID', locationID);
    RealmObjectBase.set(this, 'facilityName', facilityName);
    RealmObjectBase.set(this, 'type', type);
    RealmObjectBase.set(this, 'latitude', latitude);
    RealmObjectBase.set(this, 'longitude', longitude);
  }

  UserRecent._();

  @override
  ObjectId get id => RealmObjectBase.get<ObjectId>(this, '_id') as ObjectId;
  @override
  set id(ObjectId value) => RealmObjectBase.set(this, '_id', value);

  @override
  String get ownerId => RealmObjectBase.get<String>(this, 'owner_id') as String;
  @override
  set ownerId(String value) => RealmObjectBase.set(this, 'owner_id', value);

  @override
  String get locationID =>
      RealmObjectBase.get<String>(this, 'locationID') as String;
  @override
  set locationID(String value) =>
      RealmObjectBase.set(this, 'locationID', value);

  @override
  String get facilityName =>
      RealmObjectBase.get<String>(this, 'facilityName') as String;
  @override
  set facilityName(String value) =>
      RealmObjectBase.set(this, 'facilityName', value);

  @override
  String get type => RealmObjectBase.get<String>(this, 'type') as String;
  @override
  set type(String value) => RealmObjectBase.set(this, 'type', value);

  @override
  double get latitude =>
      RealmObjectBase.get<double>(this, 'latitude') as double;
  @override
  set latitude(double value) => RealmObjectBase.set(this, 'latitude', value);

  @override
  double get longitude =>
      RealmObjectBase.get<double>(this, 'longitude') as double;
  @override
  set longitude(double value) => RealmObjectBase.set(this, 'longitude', value);

  @override
  Stream<RealmObjectChanges<UserRecent>> get changes =>
      RealmObjectBase.getChanges<UserRecent>(this);

  @override
  UserRecent freeze() => RealmObjectBase.freezeObject<UserRecent>(this);

  EJsonValue toEJson() {
    return <String, dynamic>{
      '_id': id.toEJson(),
      'owner_id': ownerId.toEJson(),
      'locationID': locationID.toEJson(),
      'facilityName': facilityName.toEJson(),
      'type': type.toEJson(),
      'latitude': latitude.toEJson(),
      'longitude': longitude.toEJson(),
    };
  }

  static EJsonValue _toEJson(UserRecent value) => value.toEJson();
  static UserRecent _fromEJson(EJsonValue ejson) {
    return switch (ejson) {
      {
        '_id': EJsonValue id,
        'owner_id': EJsonValue ownerId,
        'locationID': EJsonValue locationID,
        'facilityName': EJsonValue facilityName,
        'type': EJsonValue type,
        'latitude': EJsonValue latitude,
        'longitude': EJsonValue longitude,
      } =>
        UserRecent(
          fromEJson(id),
          fromEJson(ownerId),
          fromEJson(locationID),
          fromEJson(facilityName),
          fromEJson(type),
          fromEJson(latitude),
          fromEJson(longitude),
        ),
      _ => raiseInvalidEJson(ejson),
    };
  }

  static final schema = () {
    RealmObjectBase.registerFactory(UserRecent._);
    register(_toEJson, _fromEJson);
    return SchemaObject(ObjectType.realmObject, UserRecent, 'UserRecent', [
      SchemaProperty('id', RealmPropertyType.objectid,
          mapTo: '_id', primaryKey: true),
      SchemaProperty('ownerId', RealmPropertyType.string, mapTo: 'owner_id'),
      SchemaProperty('locationID', RealmPropertyType.string),
      SchemaProperty('facilityName', RealmPropertyType.string),
      SchemaProperty('type', RealmPropertyType.string),
      SchemaProperty('latitude', RealmPropertyType.double),
      SchemaProperty('longitude', RealmPropertyType.double),
    ]);
  }();

  @override
  SchemaObject get objectSchema => RealmObjectBase.getSchema(this) ?? schema;
}
