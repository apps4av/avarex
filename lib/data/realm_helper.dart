import 'dart:convert';
import 'package:avaremp/data/user_aircraft.dart';
import 'package:avaremp/data/user_checklist.dart';
import 'package:avaremp/data/user_plan.dart';
import 'package:avaremp/data/user_recent.dart';
import 'package:avaremp/data/user_settings.dart';
import 'package:avaremp/data/weather_airep.dart';
import 'package:avaremp/data/weather_airsigmet.dart';
import 'package:avaremp/data/weather_metar.dart';
import 'package:avaremp/data/weather_notam.dart';
import 'package:avaremp/data/weather_taf.dart';
import 'package:avaremp/data/weather_tfr.dart';
import 'package:avaremp/data/weather_winds.dart';
import 'package:latlong2/latlong.dart';
import 'package:realm/realm.dart';
import '../aircraft.dart';
import '../checklist.dart';
import '../destination.dart';
import '../plan_route.dart';
import '../storage.dart';
import '../weather/airep.dart';
import '../weather/airsigmet.dart';
import '../weather/metar.dart';
import '../weather/notam.dart';
import '../weather/taf.dart';
import '../weather/tfr.dart';
import '../weather/winds_aloft.dart';

class RealmHelper {


  static const int _schemaVersion = 10;

  // remote syncs
  final List<SchemaObject> _remoteObjects = [
    UserRecent.schema, UserPlan.schema, UserAircraft.schema, UserChecklist.schema,
  ];

  // local syncs
  final Configuration _config = Configuration.local(
    [
      WeatherAirep.schema, WeatherWinds.schema, WeatherMetar.schema, WeatherTaf.schema, WeatherTfr.schema, WeatherAirSigmet.schema, WeatherNotam.schema, UserSettings.schema, UserRecent.schema, UserPlan.schema, UserAircraft.schema, UserChecklist.schema,
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


  void addWindsAloft(WindsAloft wa)  {

    deleteWindsAloft(wa.station);

    WeatherWinds object = WeatherWinds(ObjectId(),
      wa.station,
      wa.expires.millisecondsSinceEpoch,
      wa.w3k,
      wa.w6k,
      wa.w9k,
      wa.w12k,
      wa.w18k,
      wa.w24k,
      wa.w30k,
      wa.w34k,
      wa.w39k);

    _realm.write(() {
      _realm.add(object);
    });

  }

  Future<void> addWindsAlofts(List<WindsAloft> wa) async {

    if(wa.isEmpty) {
      return;
    }

    _realm.write(() {
      _realm.deleteAll<WeatherWinds>();
    });

    _realm.write(() {
      _realm.addAll<WeatherWinds>(wa.map((w) {
        WeatherWinds object = WeatherWinds(ObjectId(),
            w.station,
            w.expires.millisecondsSinceEpoch,
            w.w3k,
            w.w6k,
            w.w9k,
            w.w12k,
            w.w18k,
            w.w24k,
            w.w30k,
            w.w34k,
            w.w39k);
        return object;
      }));
    });
  }

  WindsAloft? getWindsAloft(String station)  {
    try {
      WeatherWinds object = _realm
          .all<WeatherWinds>()
          .query("station = '$station'")
          .first;
      return WindsAloft(
        object.station,
        DateTime.fromMillisecondsSinceEpoch(object.utcMs),
        object.w3k,
        object.w6k,
        object.w9k,
        object.w12k,
        object.w18k,
        object.w24k,
        object.w30k,
        object.w34k,
        object.w39k,
      );
    } catch(e) {
      return null;
    }
  }

  Future<List<WindsAloft>> getAllWindsAloft() async {

    RealmResults<WeatherWinds> entries = _realm.all<WeatherWinds>();

    return entries.map((e) {
      return WindsAloft(
        e.station,
        DateTime.fromMillisecondsSinceEpoch(e.utcMs),
        e.w3k,
        e.w6k,
        e.w9k,
        e.w12k,
        e.w18k,
        e.w24k,
        e.w30k,
        e.w34k,
        e.w39k,
      );
    }).toList();
  }

  void deleteWindsAloft(String station)  {

    RealmResults<WeatherWinds> entries = _realm.all<WeatherWinds>().query("station = '$station'");

    try {
      _realm.write(() {
        _realm.delete(entries.first);
      });
    } catch(e) {}

  }

  void addMetar(Metar metar)  {

    deleteMetar(metar.station);

    WeatherMetar object = WeatherMetar(ObjectId(),
        metar.station,
        metar.text,
        metar.expires.millisecondsSinceEpoch,
        metar.category,
        metar.coordinate.latitude,
        metar.coordinate.longitude,
    );

    _realm.write(() {
      _realm.add(object);
    });
  }

  Future<void> addMetars(List<Metar> metar) async {
    if(metar.isEmpty) {
      return;
    }

    _realm.write(() {
      _realm.deleteAll<WeatherMetar>();
    });

    _realm.write(() {
      _realm.addAll<WeatherMetar>(metar.map((m) {
        WeatherMetar object = WeatherMetar(ObjectId(),
            m.station,
            m.text,
            m.expires.millisecondsSinceEpoch,
            m.category,
            m.coordinate.latitude,
            m.coordinate.longitude,
        );
        return object;
      }));
    });
  }


  Metar? getMetar(String station)  {
    try {
      WeatherMetar object = _realm
          .all<WeatherMetar>()
          .query("station = '$station'")
          .first;
      return Metar(
        object.station,
        DateTime.fromMillisecondsSinceEpoch(object.utcMs),
        object.raw,
        object.category,
        LatLng(object.ARPLatitude, object.ARPLongitude),
      );
    } catch(e) {
      return null;
    }
  }

  Future<List<Metar>> getAllMetar() async {
    RealmResults<WeatherMetar> entries = _realm.all<WeatherMetar>();

    return entries.map((e) {
      return Metar(
        e.station,
        DateTime.fromMillisecondsSinceEpoch(e.utcMs),
        e.raw,
        e.category,
        LatLng(e.ARPLatitude, e.ARPLongitude),
      );
    }).toList();
  }

  void deleteMetar(String station)  {
    RealmResults<WeatherMetar> entries = _realm.all<WeatherMetar>().query("station = '$station'");

    try {
      _realm.write(() {
        _realm.delete(entries.first);
      });
    } catch(e) {}
  }


  void addTaf(Taf taf)  {
    deleteTaf(taf.station);

    WeatherTaf object = WeatherTaf(ObjectId(),
      taf.station,
      taf.text,
      taf.expires.millisecondsSinceEpoch,
      taf.coordinate.latitude,
      taf.coordinate.longitude,
    );

    _realm.write(() {
      _realm.add(object);
    });
  }

  Future<void> addTafs(List<Taf> taf) async  {
    if(taf.isEmpty) {
      return;
    }

    _realm.write(() {
      _realm.deleteAll<WeatherTaf>();
    });

    _realm.write(() {
      _realm.addAll<WeatherTaf>(taf.map((t) {
        WeatherTaf object = WeatherTaf(ObjectId(),
          t.station,
          t.text,
          t.expires.millisecondsSinceEpoch,
          t.coordinate.latitude,
          t.coordinate.longitude,
        );
        return object;
      }));
    });
  }


  Taf? getTaf(String station)  {
    try {
      WeatherTaf object = _realm
          .all<WeatherTaf>()
          .query("station = '$station'")
          .first;
      return Taf(
        object.station,
        DateTime.fromMillisecondsSinceEpoch(object.utcMs),
        object.raw,
        LatLng(object.ARPLatitude, object.ARPLongitude),
      );
    } catch(e) {
      return null;
    }
  }

  Future<List<Taf>> getAllTaf() async  {
    RealmResults<WeatherTaf> entries = _realm.all<WeatherTaf>();

    return entries.map((e) {
      return Taf(
        e.station,
        DateTime.fromMillisecondsSinceEpoch(e.utcMs),
        e.raw,
        LatLng(e.ARPLatitude, e.ARPLongitude),
      );
    }).toList();
  }

  void deleteTaf(String station)  {
    RealmResults<WeatherTaf> entries = _realm.all<WeatherTaf>().query("station = '$station'");

    try {
      _realm.write(() {
        _realm.delete(entries.first);
      });
    } catch(e) {}
  }

  void addTfr(Tfr tfr)  {
    deleteTfr(tfr.station);

    WeatherTfr object = WeatherTfr(ObjectId(),
      tfr.station,
      jsonEncode(tfr.coordinates),
      tfr.expires.millisecondsSinceEpoch,
      tfr.upperAltitude,
      tfr.lowerAltitude,
      tfr.msEffective,
      tfr.msExpires,
      tfr.labelCoordinate,
    );

    _realm.write(() {
      _realm.add(object);
    });
  }

  Future<void> addTfrs(List<Tfr> tfr) async {
    if(tfr.isEmpty) {
      return;
    }

    _realm.write(() {
      _realm.deleteAll<WeatherTfr>();
    });

    _realm.write(() {
      _realm.addAll<WeatherTfr>(tfr.map((t) {
        WeatherTfr object = WeatherTfr(ObjectId(),
          t.station,
          jsonEncode(t.coordinates),
          t.expires.millisecondsSinceEpoch,
          t.upperAltitude,
          t.lowerAltitude,
          t.msEffective,
          t.msExpires,
          t.labelCoordinate,
        );
        return object;
      }));
    });
  }

  Tfr? getTfr(String station)  {
    try {
      WeatherTfr object = _realm
          .all<WeatherTfr>()
          .query("station = '$station'")
          .first;
      List<dynamic> coordinates = jsonDecode(object.coordinates);
      List<LatLng> ll = [];
      for(dynamic coordinate in coordinates) {
        List<dynamic> cc = coordinate['coordinates'];
        ll.add(LatLng(cc[1], cc[0]));
      }
      return Tfr(
        object.station,
        DateTime.fromMillisecondsSinceEpoch(object.utcMs),
        ll,
        object.upperAltitude,
        object.lowerAltitude,
        object.msEffective,
        object.msExpires,
        object.labelCoordinate,
      );
    } catch(e) {
      return null;
    }
  }

  Future<List<Tfr>> getAllTfr() async  {
    RealmResults<WeatherTfr> entries = _realm.all<WeatherTfr>();

    return entries.map((e) {
      List<dynamic> coordinates = jsonDecode(e.coordinates);
      List<LatLng> ll = [];
      for(dynamic coordinate in coordinates) {
        List<dynamic> cc = coordinate['coordinates'];
        ll.add(LatLng(cc[1], cc[0]));
      }
      return Tfr(
        e.station,
        DateTime.fromMillisecondsSinceEpoch(e.utcMs),
        ll,
        e.upperAltitude,
        e.lowerAltitude,
        e.msEffective,
        e.msExpires,
        e.labelCoordinate,
      );
    }).toList();
  }

  void deleteTfr(String station)  {
    RealmResults<WeatherTfr> entries = _realm.all<WeatherTfr>().query("station = '$station'");

    try {
      _realm.write(() {
        _realm.delete(entries.first);
      });
    } catch(e) {}
  }

  Future<List<Airep>> getAllAirep() async {
    RealmResults<WeatherAirep> entries = _realm.all<WeatherAirep>();

    return entries.map((e) {
      List<dynamic> coordinates = jsonDecode(e.coordinates);

      return Airep(
        e.station,
        DateTime.fromMillisecondsSinceEpoch(e.utcMs),
        e.raw,
        LatLng(coordinates[0], coordinates[1]),
      );
    }).toList();
  }

  Future<void> addAireps(List<Airep> aireps) async {
    if(aireps.isEmpty) {
      return;
    }

    _realm.write(() {
      _realm.deleteAll<WeatherAirep>();
    });

    _realm.write(() {
      _realm.addAll<WeatherAirep>(aireps.map((a) {
        WeatherAirep object = WeatherAirep(ObjectId(),
          a.station,
          a.text,
          a.expires.millisecondsSinceEpoch,
          jsonEncode([a.coordinates.latitude, a.coordinates.longitude]),
        );
        return object;
      }));
    });
  }

  void addAirep(Airep airep)  {
    deleteAirep(airep.station);

    WeatherAirep object = WeatherAirep(ObjectId(),
      airep.station,
      airep.text,
      airep.expires.millisecondsSinceEpoch,
      jsonEncode([airep.coordinates.latitude, airep.coordinates.longitude]),
    );

    _realm.write(() {
      _realm.add(object);
    });
  }

  void deleteAirep(String station)  {
    RealmResults<WeatherAirep> entries = _realm.all<WeatherAirep>().query("station = '$station'");

    try {
      _realm.write(() {
        _realm.delete(entries.first);
      });
    } catch(e) {}
  }


  Future<List<AirSigmet>> getAllAirSigmet() async {
    RealmResults<WeatherAirSigmet> entries = _realm.all<WeatherAirSigmet>();

    return entries.map((e) {
      List<dynamic> coordinates = jsonDecode(e.coordinates);
      List<LatLng> ll = [];
      for(dynamic coordinate in coordinates) {
        ll.add(LatLng(coordinate[0], coordinate[1]));
      }

      return AirSigmet(
        e.station,
        DateTime.fromMillisecondsSinceEpoch(e.utcMs),
        e.raw,
        ll,
        e.hazard,
        e.severity,
        e.type,
      );
    }).toList();
  }

  Future<void> addAirSigmets(List<AirSigmet> airSigmet) async  {
    if(airSigmet.isEmpty) {
      return;
    }

    _realm.write(() {
      _realm.deleteAll<WeatherAirSigmet>();
    });

    _realm.write(() {
      _realm.addAll<WeatherAirSigmet>(airSigmet.map((a) {
        WeatherAirSigmet object = WeatherAirSigmet(ObjectId(),
          a.station,
          a.text,
          a.expires.millisecondsSinceEpoch,
          a.text,
          jsonEncode(a.coordinates.map((c) => [c.latitude, c.longitude]).toList()),
          a.hazard,
          a.severity,
          a.type,
        );
        return object;
      }));
    });
  }

  Future<List<Notam>> getAllNotams() async {
    RealmResults<WeatherNotam> entries = _realm.all<WeatherNotam>();

    return entries.map((e) {
      return Notam(
        e.station,
        DateTime.fromMillisecondsSinceEpoch(e.utcMs),
        e.text,
      );
    }).toList();
  }

  Notam? getNotam(String station)  {
    try {
      WeatherNotam object = _realm
          .all<WeatherNotam>()
          .query("station = '$station'")
          .first;
      return Notam(
        object.station,
        DateTime.fromMillisecondsSinceEpoch(object.utcMs),
        object.text,
      );
    } catch(e) {
      return null;
    }
  }

  void addNotam(Notam notam)  {
    deleteNotam(notam.station);

    WeatherNotam object = WeatherNotam(ObjectId(),
      notam.station,
      notam.text,
      notam.expires.millisecondsSinceEpoch,
    );

    _realm.write(() {
      _realm.add(object);
    });
  }

  void deleteNotam(String station)  {
    RealmResults<WeatherNotam> entries = _realm.all<WeatherNotam>().query("station = '$station'");

    try {
      _realm.write(() {
        _realm.delete(entries.first);
      });
    } catch(e) {}
  }


}