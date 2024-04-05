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

  late Realm realm;

  Future<void> init() async {
    Configuration config = Configuration.local([UserRecent.schema, UserPlan.schema, UserSettings.schema, UserAircraft.schema]);
    realm = Realm(config);
  }

  void deleteRecent(Destination destination) {
    RealmResults<UserRecent> recent = realm.all<UserRecent>().query("locationID = '${destination.locationID}' and type = '${destination.type}'");

    try {
      realm.write(() {
        realm.delete(recent.first);
      });
    } catch(e) {}

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
    

    realm.write(() {
      realm.add(recent);
    });

  }

  List<Destination> getRecentAirports() {

    RealmResults<UserRecent> recent = realm.all<UserRecent>().query("type == 'AIRPORT' or type == 'HELIPORT' or type == 'ULTRALIGHT' or type == 'BALLOONPORT'");

    List<Destination> destinations = [];
    for(UserRecent r in recent) {
      Destination d = Destination(locationID: r.locationID, type: r.type, facilityName: r.facilityName, coordinate: LatLng(r.latitude, r.longitude));
      destinations.add(d);
    }
    return destinations.reversed.toList();
  }

  List<Destination> getRecent() {
    RealmResults<UserRecent> recent = realm.all<UserRecent>();

    List<Destination> destinations = [];
    for(UserRecent r in recent) {
      Destination d = Destination(locationID: r.locationID, type: r.type, facilityName: r.facilityName, coordinate: LatLng(r.latitude, r.longitude));
      destinations.add(d);
    }
    return destinations.reversed.toList();
  }

  void addPlan(String name, PlanRoute route) {
    // remove for duplicates
    deletePlan(name);

    UserPlan plan = UserPlan(ObjectId(), name, route.toJson(name));

    realm.write(() {
      realm.add(plan);
    });

  }

  void deletePlan(String name) async {
    RealmResults<UserPlan> plan = realm.all<UserPlan>().query("name = '$name'");

    try {
      realm.write(() {
        realm.delete(plan.first);
      });
    } catch(e) {}

  }

  List<String> getPlans() {
    RealmResults<UserPlan> plan = realm.all<UserPlan>();

    List<String> ret = [];

    for(UserPlan p in plan) {
      ret.add(p.name);
    }

    return ret.reversed.toList();
  }

  Future<PlanRoute> getPlan(String name, bool reverse) {

    RealmResults<UserPlan> plan = realm.all<UserPlan>().query("name = '$name'");

    Future<PlanRoute> route = PlanRoute.fromJson(plan.first.route, plan.first.name, reverse);

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

    realm.write(() {
      realm.add(aircraftR);
    });

  }

  void deleteAircraft(String tail) {
    RealmResults<UserAircraft> aircraft = realm.all<UserAircraft>().query("tail = '$tail'");

    try {
      realm.write(() {
        realm.delete(aircraft.first);
      });
    } catch(e) {}

  }

  List<Aircraft> getAllAircraft() {
    RealmResults<UserAircraft> aircraft = realm.all<UserAircraft>();

    List<Aircraft> ret = [];

    for(UserAircraft a in aircraft) {
      ret.add(Aircraft(a.tail, a.type, a.wake, a.icao, a.equipment, a.cruiseTas, a.surveillance, a.fuelEndurance, a.color, a.pic, a.picInfo, a.sinkRate, a.fuelBurn, a.base, a.other));
    }

    return ret.reversed.toList();
  }

  Aircraft getAircraft(String tail) {
    RealmResults<UserAircraft> aircraft = realm.all<UserAircraft>().query("tail = '$tail'");

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

    realm.write(() {
      realm.add(setting);
    });

  }

  void deleteSetting(String key) {
    RealmResults<UserSettings> settings = realm.all<UserSettings>().query("key = '$key'");

    try {
      realm.write(() {
        realm.delete(settings.first);
      });
    } catch(e) {}

  }

  void deleteAllSettings() {

    try {
      realm.write(() {
        realm.deleteAll<UserSettings>();
      });
    } catch(e) {}
  }

  List<Map<String, dynamic>> getAllSettings() {
    RealmResults<UserSettings> settings = realm.all<UserSettings>();

    List<Map<String, dynamic>> ret = [];

    for(UserSettings setting in settings) {
      ret.add({"key": setting.key, "value": setting.value});
    }
    return ret;
  }

}