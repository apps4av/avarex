import 'dart:convert';
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
import '../weather/airep.dart';
import '../weather/airsigmet.dart';
import '../weather/metar.dart';
import '../weather/notam.dart';
import '../weather/taf.dart';
import '../weather/tfr.dart';
import '../weather/winds_aloft.dart';

class RealmHelper {

  Configuration config = Configuration.local(
    [WeatherAirep.schema, WeatherWinds.schema, WeatherMetar.schema, WeatherTaf.schema, WeatherTfr.schema, WeatherAirSigmet.schema, WeatherNotam.schema, UserSettings.schema],
    schemaVersion: 2,
    migrationCallback: (realm, version){},
  );

  late final Realm _realm = Realm(config);

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