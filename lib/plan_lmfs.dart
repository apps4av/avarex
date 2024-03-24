import 'dart:convert';
import 'package:avaremp/storage.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'dart:core';

class PlanLmfs {
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
    _put(params, "type", "ICAO");
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
  final String id;
  final String currentState;
  final String versionStamp;
  final String aircraftId;
  final String destination;
  final String departure;

  LmfsPlanListPlan(this.id, this.currentState, this.versionStamp, this.aircraftId, this.destination, this.departure);
}

class LmfsPlanList {
  final List<LmfsPlanListPlan> _plans = [];

  LmfsPlanList(String data) {
    try {
      var json = jsonDecode(data);
      var array = json['flightPlanSummary'] as List;
      for (var plan in array) {
        var obj = plan as Map<String, dynamic>;
        var pl = LmfsPlanListPlan(
            obj['flightId'],
            obj['currentState'],
            obj['versionStamp'],
            obj['aircraftIdentifier'],
            obj['icaoSummaryFields']['destination']['locationIdentifier'],
            obj['icaoSummaryFields']['departure']['locationIdentifier']);
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
        PlanLmfs._getTimeFromInput(future);
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

  Future<String> fileFlightPlan(PlanLmfs plan) async {
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

  Future<void> getBriefing(
      PlanLmfs pl, bool translated, String routeWidth) async {
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






