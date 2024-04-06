import 'dart:io';

import 'package:avaremp/data/user_aircraft.dart';
import 'package:avaremp/data/user_plan.dart';
import 'package:avaremp/data/user_recent.dart';
import 'package:avaremp/data/user_settings.dart';
import 'package:latlong2/latlong.dart';
import 'package:realm/realm.dart';

import '../aircraft.dart';
import '../destination.dart';
import '../path_utils.dart';
import '../plan_route.dart';
import '../storage.dart';

class UserRealmHelper {

  Realm? _realm;
  User? _user;

  String _getUserId() {
    User? usr = _user;
    return null == usr ? "" : usr.id;
  }

  final _app = App(AppConfiguration('avarexsync-vhshs', maxConnectionTimeout: const Duration(seconds: 10)));

  Future<bool> registerUser(String email, String password) async {
    EmailPasswordAuthProvider authProvider = EmailPasswordAuthProvider(_app);
    try {
      await authProvider.registerUser(email, password);
      return true;
    }
    catch(e) {
      return false;
    }
  }

  Future<List<String>?> loadCredentials() async {
    try {
      String data = await File(
          PathUtils.getFilePath(Storage().dataDir, ".password")).readAsString();
      List<String> credentials = data.split("\n");
      return credentials;
    }
    catch(e) {}
    return null;
  }

  static Future<void> saveCredentials(String email, String password) async {
    try {
      File(PathUtils.getFilePath(Storage().dataDir, ".password")).writeAsString("$email\n$password");
    }
    catch(e) {}
  }

  static Future<void> deleteCredentials() async {
    await File(PathUtils.getFilePath(Storage().dataDir, ".password")).delete();
  }

  Future<void> init() async {

    Configuration config;
    List<SchemaObject> objects = [
      UserRecent.schema,
      UserPlan.schema,
      UserSettings.schema,
      UserAircraft.schema
    ];

    _realm?.close();

    // go through login states
    List<String>? credentials = await loadCredentials();
    if(null == credentials || credentials.length < 2) {
      // local only
      config = Configuration.local(objects);
    }
    else {
      try {
        User usr = await _app.logIn(Credentials.emailPassword(credentials[0], credentials[1]));
        config = Configuration.flexibleSync(usr, objects);
        _user = usr;
      }
      catch(e) {
        // unable to login, use current user
        User? usr = _app.currentUser;
        if(null != usr) {
          config = Configuration.flexibleSync(usr, objects);
        }
        else {
          // never get here
          config = Configuration.local(objects);
        }
      }

      _realm = Realm(config);

      try {
        _realm!.subscriptions.update((mutableSubscriptions) {
          mutableSubscriptions.add(_realm!.all<UserSettings>());
          mutableSubscriptions.add(_realm!.all<UserRecent>());
          mutableSubscriptions.add(_realm!.all<UserAircraft>());
          mutableSubscriptions.add(_realm!.all<UserPlan>());
        });
        await _realm!.subscriptions.waitForSynchronization();
      }
      catch(e) {} // no sync as we are offline

    }
  }

  void deleteRecent(Destination destination) {
    if(null == _realm) {
      return;
    }
    RealmResults<UserRecent> recent = _realm!.all<UserRecent>().query("locationID = '${destination.locationID}' and type = '${destination.type}'");

    try {
      _realm!.write(() {
        _realm!.delete(recent.first);
      });
    } catch(e) {}

  }

  void addRecent(Destination destination) {
    // remove for duplicates
    deleteRecent(destination);

    UserRecent recent = UserRecent(ObjectId(), _getUserId(),
      destination.locationID,
      destination.facilityName,
      destination.type,
      destination.coordinate.latitude,
      destination.coordinate.longitude);

    if(null == _realm) {
      return;
    }

    _realm!.write(() {
      _realm!.add(recent);
    });

  }

  List<Destination> getRecentAirports() {
    List<Destination> destinations = [];

    if(null == _realm) {
      return destinations;
    }

    RealmResults<UserRecent> recent = _realm!.all<UserRecent>().query("type == 'AIRPORT' or type == 'HELIPORT' or type == 'ULTRALIGHT' or type == 'BALLOONPORT'");

    for(UserRecent r in recent) {
      Destination d = Destination(locationID: r.locationID, type: r.type, facilityName: r.facilityName, coordinate: LatLng(r.latitude, r.longitude));
      destinations.add(d);
    }
    return destinations.reversed.toList();
  }

  List<Destination> getRecent() {
    List<Destination> destinations = [];
    if(null == _realm) {
      return destinations;
    }

    RealmResults<UserRecent> recent = _realm!.all<UserRecent>();

    for(UserRecent r in recent) {
      Destination d = Destination(locationID: r.locationID, type: r.type, facilityName: r.facilityName, coordinate: LatLng(r.latitude, r.longitude));
      destinations.add(d);
    }
    return destinations.reversed.toList();
  }

  void addPlan(String name, PlanRoute route) {
    // remove for duplicates
    deletePlan(name);

    UserPlan plan = UserPlan(ObjectId(), _getUserId(), name, route.toJson(name));

    if(null == _realm) {
      return;
    }
    _realm!.write(() {
      _realm!.add(plan);
    });

  }

  void deletePlan(String name) async {
    if(null == _realm) {
      return;
    }

    RealmResults<UserPlan> plan = _realm!.all<UserPlan>().query("name = '$name'");

    try {
      _realm!.write(() {
        _realm!.delete(plan.first);
      });
    } catch(e) {}

  }

  List<String> getPlans() {
    List<String> ret = [];
    if(null == _realm) {
      return ret;
    }

    RealmResults<UserPlan> plan = _realm!.all<UserPlan>();


    for(UserPlan p in plan) {
      ret.add(p.name);
    }

    return ret.reversed.toList();
  }

  Future<PlanRoute> getPlan(String name, bool reverse) {

    if(null == _realm) {
      return PlanRoute.fromLine("New Plan", "");
    }

    RealmResults<UserPlan> plan = _realm!.all<UserPlan>().query("name = '$name'");

    Future<PlanRoute> route = PlanRoute.fromJson(plan.first.route, plan.first.name, reverse);

    return route;
  }

  Future<void> addAircraft(Aircraft aircraft) async {
    deleteAircraft(aircraft.tail);

    UserAircraft aircraftR = UserAircraft(ObjectId(), _getUserId(),
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

    if(null == _realm) {
      return;
    }

    _realm!.write(() {
      _realm!.add(aircraftR);
    });

  }

  void deleteAircraft(String tail) {
    if(null == _realm) {
      return;
    }

    RealmResults<UserAircraft> aircraft = _realm!.all<UserAircraft>().query("tail = '$tail'");

    try {
      _realm!.write(() {
        _realm!.delete(aircraft.first);
      });
    } catch(e) {}

  }

  List<Aircraft> getAllAircraft() {
    List<Aircraft> ret = [];

    if(null == _realm) {
      return ret;
    }

    RealmResults<UserAircraft> aircraft = _realm!.all<UserAircraft>();

    for(UserAircraft a in aircraft) {
      ret.add(Aircraft(a.tail, a.type, a.wake, a.icao, a.equipment, a.cruiseTas, a.surveillance, a.fuelEndurance, a.color, a.pic, a.picInfo, a.sinkRate, a.fuelBurn, a.base, a.other));
    }

    return ret.reversed.toList();
  }

  Aircraft getAircraft(String tail) {
    if(null == _realm) {
      return Aircraft.empty();
    }

    RealmResults<UserAircraft> aircraft = _realm!.all<UserAircraft>().query("tail = '$tail'");

    UserAircraft a = aircraft.first;
    return Aircraft(a.tail, a.type, a.wake, a.icao, a.equipment, a.cruiseTas, a.surveillance, a.fuelEndurance, a.color, a.pic, a.picInfo, a.sinkRate, a.fuelBurn, a.base, a.other);
  }

  void insertSetting(String key, String? value) {

    // remove for duplicates
    deleteSetting(key);

    if(null == value) {
      return;
    }
    UserSettings setting = UserSettings(ObjectId(), _getUserId(), key, value);

    if(null == _realm) {
      return null;
    }

    _realm!.write(() {
      _realm!.add(setting);
    });

  }

  String? getSetting(String key) {
    if(null == _realm) {
      return null;
    }

    RealmResults<UserSettings> settings = _realm!.all<UserSettings>().query("key = '$key'");

    if(settings.isEmpty) {
      return null;
    }
    UserSettings? s = settings.first;
    return s.value;
  }

  void deleteSetting(String key) {
    if(null == _realm) {
      return null;
    }

    RealmResults<UserSettings> settings = _realm!.all<UserSettings>().query("key = '$key'");

    try {
      _realm!.write(() {
        _realm!.delete(settings.first);
      });
    } catch(e) {}

  }

  void deleteAllSettings() {

    if(null == _realm) {
      return null;
    }

    try {
      _realm!.write(() {
        _realm!.deleteAll<UserSettings>();
      });
    } catch(e) {}
  }

  List<Map<String, dynamic>> getAllSettings() {
    List<Map<String, dynamic>> ret = [];

    if(null == _realm) {
      return ret;
    }

    RealmResults<UserSettings> settings = _realm!.all<UserSettings>();


    for(UserSettings setting in settings) {
      ret.add({"key": setting.key, "value": setting.value});
    }
    return ret;
  }

}