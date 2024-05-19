import 'dart:convert';

import 'package:avaremp/data/user_aircraft.dart';
import 'package:avaremp/data/user_checklist.dart';
import 'package:avaremp/data/user_plan.dart';
import 'package:avaremp/data/user_recent.dart';
import 'package:latlong2/latlong.dart';
import 'package:realm/realm.dart';

import '../aircraft.dart';
import '../checklist.dart';
import '../destination.dart';
import '../plan_route.dart';
import '../storage.dart';

class UserRealmHelper {

  Realm? _realm;
  User? _user;
  bool loggedIn = false;
  List<SchemaObject> objects = [
    UserRecent.schema,
    UserPlan.schema,
    UserAircraft.schema,
    UserChecklist.schema,
  ];

  String failedLoginMessage = "";
  String failedRegisterMessage = "";

  String _getUserId() {
    User? usr = _user;
    return null == usr ? "" : usr.id;
  }

  final _app = App(AppConfiguration('avarexsync-vhshs', maxConnectionTimeout: const Duration(seconds: 10)));

  Future<void> registerUser(String email, String password) async {
    failedRegisterMessage = "";
    failedLoginMessage = "";
    EmailPasswordAuthProvider authProvider = EmailPasswordAuthProvider(_app);
    try {
      await authProvider.registerUser(email, password);
      failedRegisterMessage = "";
    }
    catch(e) {
      if(e.toString().contains("status code: 409")) {
        failedRegisterMessage = "User $email is already registered.";
      }
      else {
        failedRegisterMessage = "Unable to register with the server. Please check your internet connection.";
      }
    }
  }

  (String, String) loadCredentials() {
    return (Storage().settings.getEmailBackup(), Storage().settings.getPasswordBackup());
  }

  void saveCredentials(String email, String password) {
    Storage().settings.setEmailBackup(email);
    Storage().settings.setPasswordBackup(password);
  }

  Future<void> deleteCredentials() async {
    Storage().settings.setEmailBackup("");
    Storage().settings.setPasswordBackup("");
  }

  Future<void> resetPasswordRequest(String email) async {
    EmailPasswordAuthProvider authProvider = EmailPasswordAuthProvider(_app);
    await authProvider.resetPassword(email);
  }

  Future<bool> resetPassword(String newPassword, String code) async {
    List<String> tokens = code.split("_"); // split on _
    if(tokens.length != 2) {
      return false;
    }
    EmailPasswordAuthProvider authProvider = EmailPasswordAuthProvider(_app);
    await authProvider.completeResetPassword(newPassword, tokens[0], tokens[1]);

    return true;
  }

  Future<void> logout() async {
    await _app.currentUser?.logOut();
    _realm?.close();
    _realm = null;
    _user = null;
    loggedIn = false;
    failedLoginMessage = "";
    failedRegisterMessage = "";

    // go back to local
    Configuration config;
    config = Configuration.local(objects);
    _realm = Realm(config); // start with local
  }

  Future<void> login(String username, String password) async {

    failedRegisterMessage = "";
    failedLoginMessage = "";
    if(loggedIn) { // if logged in do not try again
      failedLoginMessage = "User $username already logged in";
    }
    else {
      Configuration config;
      _realm?.close();
      config = Configuration.local(objects);
      _realm = Realm(config); // start with local

      // go through login states
      if (username.isEmpty || password.isEmpty) {
        loggedIn = false; // user does not want to use backup, keep local realm
        failedLoginMessage = "Enter username and password.";
      }
      else {
        try {
          User usr = await _app.logIn(
              Credentials.emailPassword(username, password));
          config = Configuration.flexibleSync(
              usr, objects, syncErrorHandler: (error) {});
          _user = usr;
          _realm?.close(); // close local
          _realm = Realm(config);

          try {
            _realm!.subscriptions.update((mutableSubscriptions) {
              mutableSubscriptions.add(_realm!.all<UserRecent>());
              mutableSubscriptions.add(_realm!.all<UserAircraft>());
              mutableSubscriptions.add(_realm!.all<UserPlan>());
              mutableSubscriptions.add(_realm!.all<UserChecklist>());
            });
            _realm?.subscriptions
                .waitForSynchronization(); // this can block indefinitely
          }
          catch (e) {
            loggedIn = false;
            failedLoginMessage = "Unable to sync with the server.";
          } // no sync as we are offline
          loggedIn = true;
        }
        catch (e) {

          loggedIn = false;
          // unable to login, use current user
          User? usr = _app.currentUser;
          if (null != usr) {
            config = Configuration.flexibleSync(usr, objects);
            _user = usr;
            _realm?.close(); // close local
            _realm = Realm(config); // local
          }
          if (e.toString().contains("failed: 401") ||
              e.toString().contains("status code: 401")) {
            failedLoginMessage = "Cannot log in with the provided username / password";
          }
          else {
            failedLoginMessage = "Unable to log in";
          }
        }
      }
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


  Future<void> addChecklist(Checklist checklist) async {
    deleteChecklist(checklist.name);

    UserChecklist checklistR = UserChecklist(ObjectId(), _getUserId(),
        checklist.name,
        checklist.aircraft,
        jsonEncode(checklist.steps));

    if(null == _realm) {
      return;
    }

    _realm!.write(() {
      _realm!.add(checklistR);
    });

  }

  void deleteChecklist(String name) {
    if(null == _realm) {
      return;
    }

    RealmResults<UserChecklist> checklist = _realm!.all<UserChecklist>().query("name = '$name'");

    try {
      _realm!.write(() {
        _realm!.delete(checklist.first);
      });
    } catch(e) {}

  }

  List<Checklist> getAllChecklist() {
    List<Checklist> ret = [];

    if(null == _realm) {
      return ret;
    }

    RealmResults<UserChecklist> checklist = _realm!.all<UserChecklist>();

    for(UserChecklist c in checklist) {
      List<String> steps = List<String>.from(jsonDecode(c.steps));
      ret.add(Checklist(c.name, c.aircraft, steps));
    }

    return ret.reversed.toList();
  }

  Checklist getChecklist(String name) {
    if(null == _realm) {
      return Checklist.empty();
    }

    RealmResults<UserChecklist> checklist = _realm!.all<UserChecklist>().query("name = '$name'");

    UserChecklist c = checklist.first;
    List<String> steps = List<String>.from(jsonDecode(c.steps));
    return Checklist(c.name, c.aircraft, steps);
  }

}

