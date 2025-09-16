import 'dart:convert';
import 'package:avaremp/app_log.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/storage.dart';
import 'package:http/http.dart' as http;
import 'dart:core';

import 'package:latlong2/latlong.dart';

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

  String? formatRoute(String? route) {
    if(null == route) {
      return null;
    }
    String ret = "";
    List<String> values = route.split(" ");
    for(String value in values) {
      // replace GPS format of Avare to LMFS format
      RegExp exp = RegExp(r"([0-9][0-9][0-9])([0-9][0-9])([0-9][0-9])([NS]),([0-9][0-9][0-9])([0-9][0-9])([0-9][0-9])([EW])");
      if(exp.hasMatch(value)) {
        LatLng ll = Destination.parseFromSexagesimalFullOrPartial(value);
        value = Destination.toSexagesimalLmfs(ll);
      }
      ret += "$value ";
    }
    return ret;
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
    _put(params, "route", formatRoute(route));
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
      AppLog.logMessage("LMFS parse error: $e");
      // Handle exception
    }
  }

  List<LmfsPlanListPlan> getPlans() {
    return _plans;
  }
}

class LmfsInterface {
  static const String _avareLmfsUrl = "https://www.apps4av.org/site/lmfs.php";
  static const String _avareRegisterUrl = "https://www.apps4av.org/site/register.php";
  static const String _avareUnregisterUrl = "https://www.apps4av.org/site/unregister.php";
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

  Future<String> closeFlightPlan(String id) async {
    String webUserName = Storage().settings.getEmail();
    String avareMethod = "FP/$id/close";
    String httpMethod = "POST";
    _params['webUserName'] = webUserName;
    _params['avareMethod'] = avareMethod;
    _params['httpMethod'] = httpMethod;
    String ret = await _post(_avareLmfsUrl);
    error = _parseError(ret);
    return ret;
  }

  /* Of format
   * {"returnStatus":true,"route":null,"atcRecentIFRRoutes":[{"route":"PATSS7 PATSS NELIE VALRE VALRE5","count":63,"minimumFiledAltitude":80,"maximumFiledAltitude":430,"lastDepartureTime":1714923600000},{"route":"LOGAN4 BOSOX V1 MAD BDR ALIXX RYMES","count":7,"minimumFiledAltitude":80,"maximumFiledAltitude":160,"lastDepartureTime":1714773600000},{"route":"LOGAN4 REVSS NELIE VALRE VALRE5","count":3,"minimumFiledAltitude":180,"maximumFiledAltitude":300,"lastDepartureTime":1714767120000},{"route":"LOGAN4 REVSS BAF PWL V405 CASSH V123 HAARP","count":1,"minimumFiledAltitude":140,"maximumFiledAltitude":140,"lastDepartureTime":1712768400000},{"route":"LOGAN4 DUNKK KMVY","count":1,"minimumFiledAltitude":90,"maximumFiledAltitude":90,"lastDepartureTime":1712340540000}],"codedDepartureRoutes":[],"faaPreferredRoutes":[],"returnCodedMessage":[]}
   */
  Future<List<LmfsRoute>> getRoute(String departure, String destination) async {
    List<LmfsRoute> routes = [];
    String webUserName = Storage().settings.getEmail();
    String avareMethod = "util/routeSearch";
    String httpMethod = "GET";
    _params['webUserName'] = webUserName;
    _params['avareMethod'] = avareMethod;
    _params['httpMethod'] = httpMethod;
    _params['departure'] = departure;
    _params['destination'] = destination;
    _params['searchOption'] = "ATC_RECENT_IFR_ROUTES";//"""FAA_PREFERRED_ROUTES";
    _params['searchPathOption'] = "LOW_ALTITUDE_ONLY";

    String ret = await _post(_avareLmfsUrl);
    error = _parseError(ret);

    // parse
    try {
      dynamic object = jsonDecode(ret);
      if(object["returnStatus"] == true) {
        final array = object["atcRecentIFRRoutes"];
        for(dynamic r in array) {
          String route = r["route"];
          int count =  r["count"];
          int lastDepartureTime = r["lastDepartureTime"];
          DateTime time = DateTime.fromMillisecondsSinceEpoch(lastDepartureTime);
          LmfsRoute lmr = LmfsRoute(route, count, time);
          routes.add(lmr);
        }
      }
    }
    catch(e) {
      AppLog.logMessage("LMFS route parse error: $e");
    }
    return routes;
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

  Future<void> getBriefing(PlanLmfs pl) async {
    String webUserName = Storage().settings.getEmail();
    String avareMethod = "FP/routeBriefing";
    String httpMethod = "POST";
    _params = pl._makeMap();
    _params['webUserName'] = webUserName;
    _params['avareMethod'] = avareMethod;
    _params['httpMethod'] = httpMethod;
    _params['briefingType'] = "EMAIL";
    _params['emailAddress'] = Storage().settings.getEmail();
    _params['routeCorridorWidth'] = "50";
    _params['briefingPreferences'] = "{\"plainText\":true}";
    String ret = await _post(_avareLmfsUrl);
    error = _parseError(ret);
  }


  Future<String> register(String email) async {
    _params['email'] = email;
    _params['name'] = "anonynmous";
    _params['regId'] = "";
    String ret = await _post(_avareRegisterUrl);
    error = _parseError(ret);
    return ret;
  }

  Future<String> unregister(String email) async {
    _params['email'] = email;
    _params['name'] = "anonynmous";
    _params['regId'] = "";
    String ret = await _post(_avareUnregisterUrl);
    error = _parseError(ret);
    return ret;
  }

}

class LmfsRoute {
  String route;
  int count;
  DateTime lastDepartureTime;
  LmfsRoute(this.route, this.count, this.lastDepartureTime);
}


