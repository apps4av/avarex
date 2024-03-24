import 'dart:convert';
import 'package:avaremp/storage.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'dart:core';

class LmfsPlan {
  static const String proposed = "PROPOSED";
  static const String _type = "ICAO";
  bool _valid = false;
  String? _pid;
  String versionStamp = "";
  String currentState = proposed;

  String aircraftId = "";
  String flightRule = "";
  String flightType = "";
  String noOfAircraft = "";
  String aircraftType = "";
  String wakeTurbulence = "";
  String aircraftEquipment = "";
  String departure = "";
  String departureDate = "";
  String cruisingSpeed = "";
  String level = "";
  String surveillanceEquipment = "";
  String? route = "";
  String? otherInfo = "";
  String destination = "";
  String totalElapsedTime = "";
  String? alternate1 = "";
  String? alternate2 = "";
  String fuelEndurance = "";
  String? peopleOnBoard = "";
  String aircraftColor = "";
  String supplementalRemarks = "";
  String pilotInCommand = "";
  String pilotInfo = "";


  bool isValid() {
    return _valid;
  }

  String? getId() {
    return _pid;
  }

  void setId(String id) {
    _pid = id;
  }

  LmfsPlan();

  // incoming
  factory LmfsPlan.fromJson(String data) {

    LmfsPlan plan = LmfsPlan();
    try {
      Map<String, dynamic> json = jsonDecode(data);

      Map<String, dynamic>? icao = json['icaoFlightPlan'];
      if (icao == null) {
        return plan;
      }

      plan.flightRule = icao['flightRules'];
      plan.aircraftId = icao['aircraftIdentifier'];
      plan.departure = icao['departure']['locationIdentifier'];
      plan.destination = icao['destination']['locationIdentifier'];
      plan.departureDate = icao['departureInstant'];
      plan.totalElapsedTime = icao['flightDuration'];
      try {
        plan.route = icao['route'];
        if (plan.route == "null") {
          plan.route = null;
        }
      } catch (e2) {
        plan.route = "DCT";
      }
      if (plan.route != null) {
        if (plan.route == "null") {
          plan.route = null;
        }
      }
      try {
        plan.alternate1 = icao['altDestination1']['locationIdentifier'];
      } catch (e2) {
        plan.alternate1 = null;
      }
      if (plan.alternate1 != null) {
        if (plan.alternate1 == "null") {
          plan.alternate1 = null;
        }
      }
      try {
        plan.alternate2 = icao['altDestination2']['locationIdentifier'];
      } catch (e2) {
        plan.alternate2 = null;
      }
      if (plan.alternate2 != null) {
        if (plan.alternate2 == "null") {
          plan.alternate2 = null;
        }
      }
      try {
        plan.otherInfo = icao['otherInfo'];
      } catch (e) {
        plan.otherInfo = null;
      }
      if (plan.otherInfo != null) {
        if (plan.otherInfo == "null") {
          plan.otherInfo = null;
        }
      }
      plan.aircraftType = icao['aircraftType'];
      plan.aircraftEquipment = icao['aircraftEquipment'];
      plan.noOfAircraft = icao['numberOfAircraft'];
      plan.wakeTurbulence = icao['wakeTurbulence'];
      plan.cruisingSpeed = icao['speed']['speedKnots'];
      plan.level = icao['altitude']['altitudeTypeA'];
      plan.fuelEndurance = icao['fuelOnBoard'];
      plan.peopleOnBoard = icao['peopleOnBoard'];
      if (plan.peopleOnBoard == "null") {
        plan.peopleOnBoard = "";
      }
      plan.aircraftColor = icao['aircraftColor'];
      plan.pilotInfo = icao['pilotData'];
      plan.flightType = icao['typeOfFlight'];
      plan.surveillanceEquipment = icao['surveillanceEquipment'];
      plan.supplementalRemarks = icao['suppRemarks'];
      if (plan.supplementalRemarks == "null") {
        plan.supplementalRemarks = "";
      }
      plan.pilotInCommand = icao['pilotInCommand'];
      plan.currentState = json['currentState'];
      plan._valid = true;
    } catch (e) {
      plan._valid = false;
    }
    return plan;
  }

  void _put(Map<String, String> params, String? name, String? val) {
    if (name != null && val != null) {
      if (val.isNotEmpty) {
        if (val != "null") {
          params[name] = val;
        }
      }
    }
  }

  Map<String, String> _makeMap() {
    Map<String, String> params = {};
    _put(params, "type", _type);
    _put(params, "flightRules", flightRule);
    _put(params, "aircraftIdentifier", aircraftId);
    _put(params, "departure", departure);
    _put(params, "destination", destination);
    _put(params, "departureInstant", _getTimeFromInput(departureDate));
    _put(params, "flightDuration", _getDurationFromInput(totalElapsedTime));
    _put(params, "route", route);
    _put(params, "altDestination1", alternate1);
    _put(params, "altDestination2", alternate2);
    _put(params, "aircraftType", aircraftType);
    _put(params, "otherInfo", otherInfo);
    _put(params, "aircraftType", aircraftType);
    _put(params, "aircraftEquipment", aircraftEquipment);
    _put(params, "numberOfAircraft", noOfAircraft);
    _put(params, "wakeTurbulence", wakeTurbulence);
    _put(params, "speedKnots", cruisingSpeed);
    _put(params, "altitudeTypeA", level);
    _put(params, "fuelOnBoard", _getDurationFromInput(fuelEndurance));
    _put(params, "peopleOnBoard", peopleOnBoard);
    _put(params, "aircraftColor", aircraftColor);
    _put(params, "pilotData", pilotInfo);
    _put(params, "typeOfFlight", flightType);
    _put(params, "surveillanceEquipment", surveillanceEquipment);
    _put(params, "suppRemarks", supplementalRemarks);
    _put(params, "pilotInCommand", pilotInCommand);
    return params;
  }

  static String _getTime(String future) {
    DateTime now = DateTime.now().toUtc();
    now = now.add(Duration(minutes: int.parse(future)));
    DateFormat sdf = DateFormat("yyyy-MM-dd HH:mmZ");
    return sdf.format(now);
  }
  
  static String _getTimeFromInput(String time) {
    String data = "${time.replaceFirst(" ", "T")}:00";
    return data;
  }

  static String _getDurationFromInput(String input) {
    String ret = "PT$input";
    return ret;
  }

  static String convertLocationToGpsCoords(LatLng p) {
    double lat = p.latitude.abs();
    double lon = p.longitude.abs();
    int latd = lat.toInt();
    int latm = ((lat - latd) * 60.0).toInt();
    int lond = lon.toInt();
    int lonm = ((lon - lond) * 60.0).toInt();
    String latgeo;
    String longeo;
    if (p.latitude < 0) {
      latgeo = "S";
    } else {
      latgeo = "N";
    }
    if (p.longitude < 0) {
      longeo = "W";
    } else {
      longeo = "E";
    }
    String ret = "${latd.toString().padLeft(2, '0')}${latm.toString().padLeft(2, '0')}$latgeo${lond.toString().padLeft(3, '0')}${lonm.toString().padLeft(2, '0')}$longeo";
    return ret;
  }
}

class LmfsPlanListPlan {
  String? _id;
  String? _currentState;
  String? _versionStamp;
  String? _aircraftId;
  String? _destination;
  String? _departure;

  void setId(String id) {
    _id = id;
  }
}

class LmfsPlanList {
  List<LmfsPlanListPlan> _plans = [];
  int _selectedIndex = 0;

  LmfsPlanList(String data) {
    try {
      var json = jsonDecode(data);
      var array = json['flightPlanSummary'] as List;
      for (var plan in array) {
        var pl = LmfsPlanListPlan();
        var obj = plan as Map<String, dynamic>;

        pl.setId(obj['flightId']);
        pl._currentState = obj['currentState'];
        pl._versionStamp = obj['versionStamp'];
        pl._aircraftId = obj['aircraftIdentifier'];
        pl._destination = obj['icaoSummaryFields']['destination']['locationIdentifier'];
        pl._departure = obj['icaoSummaryFields']['departure']['locationIdentifier'];
        _plans.add(pl);
      }
    } catch (e) {
      // Handle exception
    }
  }

  List<LmfsPlanListPlan> getPlans() {
    return _plans;
  }
}




class LmfsInterface {
  static const String _avareLmfsUrl = "https://apps4av.net/new/lmfs.php";
  late Map<String, String> _params;
  late String error;

  LmfsInterface() {
    _params = <String, String>{};
  }

  String _parseError(String ret) {
    try {
      Map<String, dynamic> json = jsonDecode(ret);
      bool status = json['returnStatus'];
      if (!status) {
        dynamic val = json['returnMessage'];
        return val.toString();
      }
    } catch (e) {
      return "Failed";
    }
    return "";
  }

  Future<String> _post(String url) async {
    try {
      final response = await http.post(Uri.parse(url), body: _params);
      if (response.statusCode == 200) {
        return response.body;
      } else {
        return "";
      }
    } catch (e) {
      return "";
    }
  }

  Future<LmfsPlanList> getFlightPlans() async {
    String webUserName = Storage().settings.getEmail();
    String avareMethod = "FP/$webUserName/retrieveFlightPlanSummaries";
    String httpMethod = "GET";
    _params['webUserName'] = webUserName;
    _params['avareMethod'] = avareMethod;
    _params['httpMethod'] = httpMethod;
    String ret = await _post(_avareLmfsUrl);
    error = _parseError(ret);
    return LmfsPlanList(ret);
  }

  Future<LmfsPlan> getFlightPlan(String id) async {
    String webUserName = Storage().settings.getEmail();
    String avareMethod = "FP/$id/retrieve";
    String httpMethod = "GET";
    _params['webUserName'] = webUserName;
    _params['avareMethod'] = avareMethod;
    _params['httpMethod'] = httpMethod;
    String ret = await _post(_avareLmfsUrl);
    error = _parseError(ret);
    return LmfsPlan.fromJson(ret);
  }

  Future<String> closeFlightPlan(String id, String loc) async {
    String webUserName = Storage().settings.getEmail();
    String avareMethod = "FP/$id/close";
    String httpMethod = "POST";
    _params['webUserName'] = webUserName;
    _params['avareMethod'] = avareMethod;
    _params['httpMethod'] = httpMethod;
    if (loc != "") {
      _params['closeDestinationInfo'] = loc;
    }
    String ret = await _post(_avareLmfsUrl);
    error = _parseError(ret);
    return ret;
  }

  Future<String> activateFlightPlan(
      String id, String version, String future) async {
    String webUserName = Storage().settings.getEmail();
    String avareMethod = "FP/$id/activate";
    String httpMethod = "POST";
    _params['webUserName'] = webUserName;
    _params['avareMethod'] = avareMethod;
    _params['httpMethod'] = httpMethod;
    _params['actualDepartureInstant'] =
        LmfsPlan._getTimeFromInput(LmfsPlan._getTime(future));
    _params['versionStamp'] = version;
    String ret = await _post(_avareLmfsUrl);
    error = _parseError(ret);
    return ret;
  }

  Future<String> cancelFlightPlan(String id) async {
    String webUserName = Storage().settings.getEmail();
    String avareMethod = "FP/$id/cancel";
    String httpMethod = "POST";
    _params['webUserName'] = webUserName;
    _params['avareMethod'] = avareMethod;
    _params['httpMethod'] = httpMethod;
    String ret = await _post(_avareLmfsUrl);
    error = _parseError(ret);
    return ret;
  }

  Future<String> fileFlightPlan(LmfsPlan plan) async {
    String webUserName = Storage().settings.getEmail();
    String avareMethod = "FP/file";
    String httpMethod = "POST";
    _params = plan._makeMap();
    _params['webUserName'] = webUserName;
    _params['avareMethod'] = avareMethod;
    _params['httpMethod'] = httpMethod;
    String ret = await _post(_avareLmfsUrl);
    error = _parseError(ret);
    return ret;
  }

  Future<String> amendFlightPlan(LmfsPlan plan) async {
    String webUserName = Storage().settings.getEmail();
    String avareMethod = "FP/${plan.getId()}/amend";
    String httpMethod = "POST";
    _params = plan._makeMap();
    _params['webUserName'] = webUserName;
    _params['avareMethod'] = avareMethod;
    _params['httpMethod'] = httpMethod;
    _params['versionStamp'] = plan.versionStamp;
    String ret = await _post(_avareLmfsUrl);
    error = _parseError(ret);
    return ret;
  }

  Future<void> getBriefing(
      LmfsPlan pl, bool translated, String routeWidth) async {
    String webUserName = Storage().settings.getEmail();
    String avareMethod = "FP/emailBriefing";
    String httpMethod = "POST";
    _params = pl._makeMap();
    _params['webUserName'] = webUserName;
    _params['avareMethod'] = avareMethod;
    _params['httpMethod'] = httpMethod;
    _params['briefingType'] = "EMAIL";
    _params['briefingEmailAddresses'] = Storage().settings.getEmail();
    _params['recipientEmailAddresses'] = Storage().settings.getEmail();
    _params['routeCorridorWidth'] = routeWidth;
    if (translated) {
      _params['briefingPreferences'] = "{\"plainText\":true}";
    }
    String ret = await _post(_avareLmfsUrl);
    error = _parseError(ret);
  }

}






