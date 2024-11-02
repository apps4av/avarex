import 'dart:convert';
import 'package:avaremp/data/user_aircraft.dart';
import 'package:avaremp/data/user_checklist.dart';
import 'package:avaremp/data/user_plan.dart';
import 'package:avaremp/data/user_recent.dart';
import 'package:avaremp/data/user_settings.dart';
import 'package:avaremp/data/user_wnb.dart';
import 'package:avaremp/wnb.dart';
import 'package:latlong2/latlong.dart';
import 'package:realm/realm.dart';
import 'package:avaremp/aircraft.dart';
import 'package:avaremp/checklist.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/plan/plan_route.dart';
import 'package:avaremp/storage.dart';

class RealmHelper {


  static const int _schemaVersion = 12;

  // remote syncs
  final List<SchemaObject> _remoteObjects = [
    UserRecent.schema, UserPlan.schema, UserAircraft.schema, UserChecklist.schema, UserWnb.schema
  ];

  // local syncs
  final Configuration _config = Configuration.local(
    [
      UserSettings.schema, UserRecent.schema, UserPlan.schema, UserAircraft.schema, UserChecklist.schema, UserWnb.schema
    ],
    schemaVersion: _schemaVersion,
    migrationCallback: (realm, version) {
    },
  );

  late final Realm _realm = Realm(_config);
  Realm? _remoteRealm;
  bool loggedIn = false;
  final _app = App(AppConfiguration('avarexsync-vhshs', maxConnectionTimeout: const Duration(seconds: 10)));
  User? _user;

  Realm _getRealm() {
    return (_remoteRealm != null) ? _remoteRealm! : _realm;
  }

  String _getUserId() {
    User? usr = _user;
    return null == usr ? "" : usr.id;
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

  Future<String> registerUser(List<String> args) async {
    String email = args[0];
    String password = args[1];
    String failedRegisterMessage = "";
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
    return failedRegisterMessage;
  }

  Future<String> resetPasswordRequest(List<String> args) async {
    String email = args[0];
    String failedPasswordResetMessage = "";
    EmailPasswordAuthProvider authProvider = EmailPasswordAuthProvider(_app);
    try {
      await authProvider.resetPassword(email);
    }
    catch(e) {
      failedPasswordResetMessage = "Unable to reset password. Check your email address and password.";
    }
    return failedPasswordResetMessage;
  }

  Future<String> resetPassword(List<String> args) async {
    String code = args[0];
    String newPassword = args[1];
    String failedPasswordResetMessage = "";
    List<String> tokens = code.split("_"); // split on _
    if(tokens.length != 2) {
      failedPasswordResetMessage = "Invalid reset code. Please check your email for the correct code.";
      return failedPasswordResetMessage;
    }
    EmailPasswordAuthProvider authProvider = EmailPasswordAuthProvider(_app);
    await authProvider.completeResetPassword(newPassword, tokens[0], tokens[1]);

    return failedPasswordResetMessage;
  }

  Future<String> deleteAccount(List<String>args) async {
    String confirmation = args[0];
    String password = args[1];
    String failedDeleteMessage = "";
    if(confirmation != "delete") {
      failedDeleteMessage = "Confirmation not received.";
      return failedDeleteMessage;
    }
    if(password != Storage().settings.getPasswordBackup()) {
      failedDeleteMessage = "Password does not match the password of the account you are deleting.";
      return failedDeleteMessage;
    }
    if(_user == null) {
      failedDeleteMessage = "No user exists.";
      return failedDeleteMessage;
    }
    await _app.deleteUser(_user!);
    return failedDeleteMessage;
  }

  void _closeRemote() {
    _remoteRealm?.close();
    _remoteRealm = null;
    loggedIn = false;
  }

  Future<String> logout(List<String> args) async {
    await _app.currentUser?.logOut();
    _user = null;
    _closeRemote();
    return "";
  }

  Future<String> login(List<String> args) async {
    String username = args[0];
    String password = args[1];

    String failedLoginMessage = "";
    if(loggedIn) { // if logged in do not try again
      failedLoginMessage = "User $username already logged in";
    }
    else {
      _closeRemote();
      // go through login states
      if (username.isEmpty || password.isEmpty) {
        // user does not want to use backup, keep local realm
        failedLoginMessage = "Enter username and password.";
      }
      else {
        try {
          User usr = await _app.logIn(
              Credentials.emailPassword(username, password));
          Configuration config = Configuration.flexibleSync(schemaVersion: 0,
              usr, _remoteObjects, syncErrorHandler: (error) {});
          _user = usr;
          _remoteRealm = Realm(config);

          try {
            _remoteRealm!.subscriptions.update((mutableSubscriptions) {
              mutableSubscriptions.add(_remoteRealm!.all<UserRecent>());
              mutableSubscriptions.add(_remoteRealm!.all<UserAircraft>());
              mutableSubscriptions.add(_remoteRealm!.all<UserPlan>());
              mutableSubscriptions.add(_remoteRealm!.all<UserChecklist>());
              mutableSubscriptions.add(_remoteRealm!.all<UserWnb>());
            });
            _remoteRealm?.subscriptions.waitForSynchronization(); // this can block indefinitely
          }
          catch (e) {
            _closeRemote();
            failedLoginMessage = "Unable to sync with the server.";
          } // no sync as we are offline
          loggedIn = true;
        }
        catch (e) {

          _closeRemote();
          // unable to login, use current user
          User? usr = _app.currentUser;
          if (null != usr) {
            Configuration config = Configuration.flexibleSync(usr, _remoteObjects, schemaVersion: 0, );
            _user = usr;
            _remoteRealm = Realm(config);
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
    return failedLoginMessage;
  }

  void deleteRecent(Destination destination) {
    Realm r = _getRealm();
    RealmResults<UserRecent> recent = r.all<UserRecent>().query("locationID = '${destination.locationID}' and type = '${destination.type}'");

    try {
      r.write(() {
        r.delete(recent.first);
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

    Realm r = _getRealm();

    r.write(() {
      r.add(recent);
    });

  }

  List<Destination> getRecentAirports() {
    List<Destination> destinations = [];
    Realm r = _getRealm();

    RealmResults<UserRecent> recent = r.all<UserRecent>().query("type == 'AIRPORT' or type == 'HELIPORT' or type == 'ULTRALIGHT' or type == 'BALLOONPORT'");

    for(UserRecent r in recent) {
      Destination d = Destination(locationID: r.locationID, type: r.type, facilityName: r.facilityName, coordinate: LatLng(r.latitude, r.longitude));
      destinations.add(d);
    }
    return destinations.reversed.toList();
  }

  List<Destination> getRecent() {
    List<Destination> destinations = [];
    Realm r = _getRealm();

    RealmResults<UserRecent> recent = r.all<UserRecent>();

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

    Realm r = _getRealm();

    r.write(() {
      r.add(plan);
    });

  }

  void deletePlan(String name) async {
    Realm r = _getRealm();

    RealmResults<UserPlan> plan = r.all<UserPlan>().query("name = '$name'");

    try {
      r.write(() {
        r.delete(plan.first);
      });
    } catch(e) {}

  }

  List<String> getPlans() {
    List<String> ret = [];
    Realm r = _getRealm();

    RealmResults<UserPlan> plan = r.all<UserPlan>();


    for(UserPlan p in plan) {
      ret.add(p.name);
    }

    return ret.reversed.toList();
  }

  Future<PlanRoute> getPlan(String name, bool reverse) {

    Realm r = _getRealm();

    RealmResults<UserPlan> plan = r.all<UserPlan>().query("name = '$name'");

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

    Realm r = _getRealm();

    r.write(() {
      r.add(aircraftR);
    });

  }

  void deleteAircraft(String tail) {
    Realm r = _getRealm();

    RealmResults<UserAircraft> aircraft = r.all<UserAircraft>().query("tail = '$tail'");

    try {
      r.write(() {
        r.delete(aircraft.first);
      });
    } catch(e) {}

  }

  List<Aircraft> getAllAircraft() {
    List<Aircraft> ret = [];

    Realm r = _getRealm();

    RealmResults<UserAircraft> aircraft = r.all<UserAircraft>();

    for(UserAircraft a in aircraft) {
      ret.add(Aircraft(a.tail, a.type, a.wake, a.icao, a.equipment, a.cruiseTas, a.surveillance, a.fuelEndurance, a.color, a.pic, a.picInfo, a.sinkRate, a.fuelBurn, a.base, a.other));
    }

    return ret.reversed.toList();
  }

  Aircraft getAircraft(String tail) {
    Realm r = _getRealm();

    RealmResults<UserAircraft> aircraft = r.all<UserAircraft>().query("tail = '$tail'");

    UserAircraft a = aircraft.first;
    return Aircraft(a.tail, a.type, a.wake, a.icao, a.equipment, a.cruiseTas, a.surveillance, a.fuelEndurance, a.color, a.pic, a.picInfo, a.sinkRate, a.fuelBurn, a.base, a.other);
  }


  Future<void> addChecklist(Checklist checklist) async {
    deleteChecklist(checklist.name);

    UserChecklist checklistR = UserChecklist(ObjectId(), _getUserId(),
        checklist.name,
        checklist.aircraft,
        jsonEncode(checklist.steps));

    Realm r = _getRealm();

    r.write(() {
      r.add(checklistR);
    });

  }

  void deleteChecklist(String name) {
    Realm r = _getRealm();

    RealmResults<UserChecklist> checklist = r.all<UserChecklist>().query("name = '$name'");

    try {
      r.write(() {
        r.delete(checklist.first);
      });
    } catch(e) {}

  }

  List<Checklist> getAllChecklist() {
    List<Checklist> ret = [];

    Realm r = _getRealm();

    RealmResults<UserChecklist> checklist = r.all<UserChecklist>();

    for(UserChecklist c in checklist) {
      List<String> steps = List<String>.from(jsonDecode(c.steps));
      ret.add(Checklist(c.name, c.aircraft, steps));
    }

    return ret.reversed.toList();
  }

  Checklist getChecklist(String name) {
    Realm r = _getRealm();

    RealmResults<UserChecklist> checklist = r.all<UserChecklist>().query("name = '$name'");

    UserChecklist c = checklist.first;
    List<String> steps = List<String>.from(jsonDecode(c.steps));
    return Checklist(c.name, c.aircraft, steps);
  }


  Future<void> addWnb(Wnb wnb) async {
    deleteWnb(wnb.name);

    UserWnb wnbR = UserWnb(ObjectId(), _getUserId(),
        wnb.name,
        wnb.aircraft,
        jsonEncode(wnb.items),
        wnb.minX,
        wnb.minY,
        wnb.maxX,
        wnb.maxY,
        jsonEncode(wnb.points));

    Realm r = _getRealm();

    r.write(() {
      r.add(wnbR);
    });
  }

  void deleteWnb(String name) {
    Realm r = _getRealm();

    RealmResults<UserWnb> wnb = r.all<UserWnb>().query("name = '$name'");

    try {
      r.write(() {
        r.delete(wnb.first);
      });
    } catch(e) {}

  }

  List<Wnb> getAllWnb() {
    List<Wnb> ret = [];

    Realm r = _getRealm();

    RealmResults<UserWnb> wnb = r.all<UserWnb>();

    for(UserWnb w in wnb) {
      List<String> items = List<String>.from(jsonDecode(w.items));
      List<String> points = List<String>.from(jsonDecode(w.points));
      ret.add(Wnb(w.name, w.aircraft, items, w.minX, w.minY, w.maxX, w.maxY, points));
    }

    return ret.reversed.toList();
  }

  Wnb getWnb(String name) {
    Realm r = _getRealm();

    RealmResults<UserWnb> wnb = r.all<UserWnb>().query("name = '$name'");

    UserWnb w = wnb.first;
    List<String> items = List<String>.from(jsonDecode(w.items));
    List<String> points = List<String>.from(jsonDecode(w.points));
    return Wnb(w.name, w.aircraft, items, w.minX, w.minY, w.maxX, w.maxY, points);
  }

  void insertSetting(String key, String? value) {

    // remove for duplicates
    deleteSetting(key);

    if(null == value) {
      return;
    }
    UserSettings setting = UserSettings(ObjectId(), "", key, value);

    _realm.write(() {
      _realm.add(setting);
    });

  }

  String? getSetting(String key) {

    RealmResults<UserSettings> settings = _realm.all<UserSettings>().query("key = '$key'");

    if(settings.isEmpty) {
      return null;
    }
    UserSettings? s = settings.first;
    return s.value;
  }

  void deleteSetting(String key) {

    RealmResults<UserSettings> settings = _realm.all<UserSettings>().query("key = '$key'");

    try {
      _realm.write(() {
        _realm.delete(settings.first);
      });
    } catch(e) {}

  }

  void deleteAllSettings() {

    try {
      _realm.write(() {
        _realm.deleteAll<UserSettings>();
      });
    } catch(e) {}
  }

  List<Map<String, dynamic>> getAllSettings() {
    List<Map<String, dynamic>> ret = [];

    RealmResults<UserSettings> settings = _realm.all<UserSettings>();

    for(UserSettings setting in settings) {
      ret.add({"key": setting.key, "value": setting.value});
    }
    return ret;
  }

}