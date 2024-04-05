import 'package:avaremp/data/user_aircraft.dart';
import 'package:avaremp/data/user_plan.dart';
import 'package:avaremp/data/user_recent.dart';
import 'package:avaremp/data/user_settings.dart';
import 'package:latlong2/latlong.dart';
import 'package:realm/realm.dart';

import '../aircraft.dart';
import '../destination.dart';
import '../plan_route.dart';

class UserRealmHelper {

  final config = Configuration.local([UserRecent.schema, UserPlan.schema, UserSettings.schema, UserAircraft.schema]);

  void deleteRecent(Destination destination) {
    final realm = Realm(config);
    RealmResults<UserRecent> recent = realm.all<UserRecent>().query("locationID = '${destination.locationID}' and type = '${destination.type}'");

    try {
      realm.write(() {
        realm.delete(recent.first);
      });
    } catch(e) {}

    realm.close();
  }

  void addRecent(Destination destination) {
    // remove for duplicates
    deleteRecent(destination);

    UserRecent recent = UserRecent(ObjectId(),
      destination.locationID,
      destination.facilityName,
      destination.type,
      destination.coordinate.latitude,
      destination.coordinate.longitude);
    
    final realm = Realm(config);

    realm.write(() {
      realm.add(recent);
    });

    realm.close();
  }

  List<Destination> getRecentAirports() {

    final realm = Realm(config);
    RealmResults<UserRecent> recent = realm.all<UserRecent>().query("type == 'AIRPORT' or type == 'HELIPORT' or type == 'ULTRALIGHT' or type == 'BALLOONPORT'");

    List<Destination> destinations = [];
    for(UserRecent r in recent) {
      Destination d = Destination(locationID: r.locationID, type: r.type, facilityName: r.facilityName, coordinate: LatLng(r.latitude, r.longitude));
      destinations.add(d);
    }
    realm.close();
    return destinations.reversed.toList();
  }

  List<Destination> getRecent() {
    final realm = Realm(config);
    RealmResults<UserRecent> recent = realm.all<UserRecent>();

    List<Destination> destinations = [];
    for(UserRecent r in recent) {
      Destination d = Destination(locationID: r.locationID, type: r.type, facilityName: r.facilityName, coordinate: LatLng(r.latitude, r.longitude));
      destinations.add(d);
    }
    realm.close();
    return destinations.reversed.toList();
  }

  void addPlan(String name, PlanRoute route) {
    // remove for duplicates
    deletePlan(name);

    UserPlan plan = UserPlan(ObjectId(), name, route.toJson(name));

    final realm = Realm(config);

    realm.write(() {
      realm.add(plan);
    });

    realm.close();
  }

  void deletePlan(String name) async {
    final realm = Realm(config);
    RealmResults<UserPlan> plan = realm.all<UserPlan>().query("name = '$name'");

    try {
      realm.write(() {
        realm.delete(plan.first);
      });
    } catch(e) {}

    realm.close();

  }

  List<String> getPlans() {
    final realm = Realm(config);
    RealmResults<UserPlan> plan = realm.all<UserPlan>();

    List<String> ret = [];

    for(UserPlan p in plan) {
      ret.add(p.name);
    }

    realm.close();

    return ret.reversed.toList();
  }

  Future<PlanRoute> getPlan(String name, bool reverse) {

    final realm = Realm(config);
    RealmResults<UserPlan> plan = realm.all<UserPlan>().query("name = '$name'");

    Future<PlanRoute> route = PlanRoute.fromJson(plan.first.route, plan.first.name, reverse);

    realm.close();
    return route;
  }

  Future<void> addAircraft(Aircraft aircraft) async {
    deleteAircraft(aircraft.tail);

    UserAircraft aircraftR = UserAircraft(ObjectId(),
      aircraft.tail,
      aircraft.type,
      aircraft.wake,
      aircraft.icao,
      aircraft.equipment,
      aircraft.cruiseTas,
      aircraft.surveillance,
      aircraft.fuelEndurance,
      aircraft.color,
      aircraft.pic,
      aircraft.picInfo,
      aircraft.sinkRate,
      aircraft.fuelBurn,
      aircraft.base,
      aircraft.other);

    final realm = Realm(config);

    realm.write(() {
      realm.add(aircraftR);
    });

    realm.close();

  }

  void deleteAircraft(String tail) {
    final realm = Realm(config);
    RealmResults<UserAircraft> aircraft = realm.all<UserAircraft>().query("tail = '$tail'");

    try {
      realm.write(() {
        realm.delete(aircraft.first);
      });
    } catch(e) {}

    realm.close();

  }

  List<Aircraft> getAllAircraft() {
    final realm = Realm(config);
    RealmResults<UserAircraft> aircraft = realm.all<UserAircraft>();

    List<Aircraft> ret = [];

    for(UserAircraft a in aircraft) {
      ret.add(Aircraft(a.tail, a.type, a.wake, a.icao, a.equipment, a.cruiseTas, a.surveillance, a.fuelEndurance, a.color, a.pic, a.picInfo, a.sinkRate, a.fuelBurn, a.base, a.other));
    }

    realm.close();

    return ret.reversed.toList();
  }

  Aircraft getAircraft(String tail) {
    final realm = Realm(config);
    RealmResults<UserAircraft> aircraft = realm.all<UserAircraft>().query("tail = '$tail'");

    realm.close();

    UserAircraft a = aircraft.first;
    return Aircraft(a.tail, a.type, a.wake, a.icao, a.equipment, a.cruiseTas, a.surveillance, a.fuelEndurance, a.color, a.pic, a.picInfo, a.sinkRate, a.fuelBurn, a.base, a.other);
  }

  void insertSetting(String key, String? value) {

    // remove for duplicates
    deleteSetting(key);

    if(null == value) {
      return;
    }
    UserSettings setting = UserSettings(ObjectId(), key, value);

    final realm = Realm(config);

    realm.write(() {
      realm.add(setting);
    });

    realm.close();
  }

  void deleteSetting(String key) {
    final realm = Realm(config);
    RealmResults<UserSettings> settings = realm.all<UserSettings>().query("key = '$key'");

    try {
      realm.write(() {
        realm.delete(settings.first);
      });
    } catch(e) {}

    realm.close();
  }

  void deleteAllSettings() {
    final realm = Realm(config);

    try {
      realm.write(() {
        realm.deleteAll<UserSettings>();
      });
    } catch(e) {}

    realm.close();
  }

  List<Map<String, dynamic>> getAllSettings() {
    final realm = Realm(config);
    RealmResults<UserSettings> settings = realm.all<UserSettings>();

    List<Map<String, dynamic>> ret = [];

    for(UserSettings setting in settings) {
      ret.add({"key": setting.key, "value": setting.value});
    }

    realm.close();

    return ret;
  }

}