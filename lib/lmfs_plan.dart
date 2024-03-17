import 'dart:convert';
import 'package:avaremp/constants.dart';
import 'package:avaremp/plan_route.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'dart:core';

import 'destination.dart';


class LmfsPlan {
  static const String proposed = "PROPOSED";
  static const String type = "ICAO";
  static const String direct = "DCT";
  static const String ruleVfr = "VFR";
  bool valid = false;
  String? pid;
  String aircraftId = "";
  String flightRule = ruleVfr;
  String flightType = "G";
  String noOfAircraft = "1";
  String aircraftType = "";
  String wakeTurbulence = "";
  String aircraftEquipment = "N";
  String departure = "";
  String departureDate = "";
  String cruisingSpeed = "";
  String level = "";
  String surveillanceEquipment = "N";
  String? route = direct;
  String? otherInfo = "";
  String destination = "";
  String totalElapsedTime = "";
  String? alternate1 = "";
  String? alternate2 = "";
  String fuelEndurance = "";
  String? peopleOnBoard = "1";
  String aircraftColor = "";
  String supplementalRemarks = "";
  String pilotInCommand = "";
  String pilotInfo = "";
  String versionStamp = "";
  String currentState = proposed;


  static (String route, String destination, String departure) makeRoute(PlanRoute p) {

    String route = "";
    String destination = "";
    String departure = "";
    String k = Constants.useK ? "K" : "";

    int num = p.length;
    if (num >= 2) {
      if (p.getWaypointAt(num - 1).destination is AirportDestination) {
        destination = "$k${p.getWaypointAt(num - 1).destination.locationID}";
      }
      if (p.getWaypointAt(0).destination is AirportDestination) {
        departure = "$k${p.getWaypointAt(0).destination.locationID}";
      }
    }

    if (num > 2) {
      route = "";

      for (int dest = 1; dest < (num - 1); dest++) {
        Destination d = p.getWaypointAt(dest).destination;
        if (d is GpsDestination) {
          route += "${LmfsPlan.convertLocationToGpsCoords(p.getWaypointAt(dest).destination.coordinate)} ";
        } else if (d is AirportDestination) {
          route += "$k${p.getWaypointAt(dest).destination.locationID} ";
        } else {
          route += "${p.getWaypointAt(dest).destination.locationID} ";
        }
      }
    }
    if (route.isEmpty) {
      route = LmfsPlan.direct;
    }

    return (route, destination, departure);
  }

  bool isValid() {
    return valid;
  }

  String? getId() {
    return pid;
  }

  void setId(String id) {
    pid = id;
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
        plan.route = direct;
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
      plan.valid = true;
    } catch (e) {
      plan.valid = false;
    }
    return plan;
  }

  void put(Map<String, String> params, String? name, String? val) {
    if (name != null && val != null) {
      if (val.isEmpty) {
        if (val != "null") {
          params[name] = val;
        }
      }
    }
  }

  Map<String, String> makeMap() {
    Map<String, String> params = {};
    put(params, "type", type);
    put(params, "flightRules", flightRule);
    put(params, "aircraftIdentifier", aircraftId);
    put(params, "departure", departure);
    put(params, "destination", destination);
    put(params, "departureInstant", LmfsPlan.getTimeFromInput(LmfsPlan.getTimeFromInstance(departureDate)));
    put(params, "flightDuration", totalElapsedTime);
    put(params, "route", route);
    put(params, "altDestination1", alternate1);
    put(params, "altDestination2", alternate2);
    put(params, "aircraftType", aircraftType);
    put(params, "otherInfo", otherInfo);
    put(params, "aircraftType", aircraftType);
    put(params, "aircraftEquipment", aircraftEquipment);
    put(params, "numberOfAircraft", noOfAircraft);
    put(params, "wakeTurbulence", wakeTurbulence);
    put(params, "speedKnots", cruisingSpeed);
    put(params, "altitudeTypeA", level);
    put(params, "fuelOnBoard", fuelEndurance);
    put(params, "peopleOnBoard", peopleOnBoard);
    put(params, "aircraftColor", aircraftColor);
    put(params, "pilotData", pilotInfo);
    put(params, "typeOfFlight", flightType);
    put(params, "surveillanceEquipment", surveillanceEquipment);
    put(params, "suppRemarks", supplementalRemarks);
    put(params, "pilotInCommand", pilotInfo);
    return params;
  }

  static String getTime(String future) {
    DateTime now = DateTime.now().toUtc();
    now = now.add(Duration(minutes: int.parse(future)));
    DateFormat sdf = DateFormat("yyyy-MM-dd HH:mmZ");
    return sdf.format(now);
  }

  static String getTimeFromInstance(String instance) {
    DateTime now = DateTime.now().toUtc();
    try {
      int time = int.parse(instance);
      now = DateTime.fromMillisecondsSinceEpoch(time, isUtc: true);
    } catch (e) {
      return "";
    }
    DateFormat sdf = DateFormat("yyyy-MM-dd HH:mmZ");
    return sdf.format(now);
  }

  static String getInstanceFromTime(String time) {
    DateFormat sdf = DateFormat("yyyy-MM-dd HH:mmZ");
    DateTime dt;
    try {
      dt = sdf.parse(time);
    } catch (e) {
      return "";
    }
    return dt.millisecondsSinceEpoch.toString();
  }

  static String getTimeFromInput(String time) {
    String data = "${time.replaceFirst(" ", "T")}:00";
    return data;
  }

  static String getDurationFromInput(String input) {
    String ret = "PT$input";
    return ret;
  }

  static String durationToTime(String input) {
    List<String> ret = input.split("PT");
    if (ret.length < 2) {
      return input;
    }
    return ret[1];
  }

  static String timeToDuration(double time) {
    int hours = time.toInt();
    int min = ((time - hours) * 60.0).toInt();
    return "PT${hours}H${min}M";
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
  String? id;
  String? currentState;
  String? versionStamp;
  String? aircraftId;
  String? destination;
  String? departure;

  void setId(String id) {
    this.id = id;
  }
}

class LmfsPlanList {
  List<LmfsPlanListPlan> mPlans = [];
  int mSelectedIndex = 0;

  LmfsPlanList(String data) {
    try {
      var json = jsonDecode(data);
      var array = json['flightPlanSummary'] as List;
      for (var plan in array) {
        var pl = LmfsPlanListPlan();
        var obj = plan as Map<String, dynamic>;

        pl.setId(obj['flightId']);
        pl.currentState = obj['currentState'];
        pl.versionStamp = obj['versionStamp'];
        pl.aircraftId = obj['aircraftIdentifier'];
        pl.destination = obj['icaoSummaryFields']['destination']['locationIdentifier'];
        pl.departure = obj['icaoSummaryFields']['departure']['locationIdentifier'];
        mPlans.add(pl);
      }
    } catch (e) {
      // Handle exception
    }
  }

  List<LmfsPlanListPlan> getPlans() {
    return mPlans;
  }
}




class LmfsInterface {
  static const String avareLmfsUrl = "https://apps4av.net/new/lmfs.php";
  late Map<String, String> params;
  late String mError;

  LmfsInterface() {
    params = <String, String>{};
  }

  String parseError(String ret) {
    try {
      Map<String, dynamic> json = jsonDecode(ret);
      bool status = json['returnStatus'];
      if (!status) {
        String val = json['returnMessage'];
        val = val.replaceAll("\\", "");
        return val;
      }
    } catch (e) {
      return "Failed";
    }
    return "";
  }

  Future<String> post(String url) async {
    try {
      final response = await http.post(Uri.parse(url), body: params);
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
    String webUserName = "governer@gmail.com";
    String avareMethod = "FP/$webUserName/retrieveFlightPlanSummaries";
    String httpMethod = "GET";
    params['webUserName'] = webUserName;
    params['avareMethod'] = avareMethod;
    params['httpMethod'] = httpMethod;
    String ret = await post(avareLmfsUrl);
    mError = parseError(ret);
    return LmfsPlanList(ret);
  }

  Future<LmfsPlan> getFlightPlan(String id) async {
    String webUserName = "governer@gmail.com";
    String avareMethod = "FP/$id/retrieve";
    String httpMethod = "GET";
    params['webUserName'] = webUserName;
    params['avareMethod'] = avareMethod;
    params['httpMethod'] = httpMethod;
    String ret = await post(avareLmfsUrl);
    mError = parseError(ret);
    return LmfsPlan.fromJson(ret);
  }

  Future<String> closeFlightPlan(String id, String loc) async {
    String webUserName = "governer@gmail.com";
    String avareMethod = "FP/$id/close";
    String httpMethod = "POST";
    params['webUserName'] = webUserName;
    params['avareMethod'] = avareMethod;
    params['httpMethod'] = httpMethod;
    if (loc != "") {
      params['closeDestinationInfo'] = loc;
    }
    String ret = await post(avareLmfsUrl);
    mError = parseError(ret);
    return ret;
  }

  Future<String> activateFlightPlan(
      String id, String version, String future) async {
    String webUserName = "governer@gmail.com";
    String avareMethod = "FP/$id/activate";
    String httpMethod = "POST";
    params['webUserName'] = webUserName;
    params['avareMethod'] = avareMethod;
    params['httpMethod'] = httpMethod;
    params['actualDepartureInstant'] =
        LmfsPlan.getTimeFromInput(LmfsPlan.getTime(future));
    params['versionStamp'] = version;
    String ret = await post(avareLmfsUrl);
    mError = parseError(ret);
    return ret;
  }

  Future<String> cancelFlightPlan(String id) async {
    String webUserName = "governer@gmail.com";
    String avareMethod = "FP/$id/cancel";
    String httpMethod = "POST";
    params['webUserName'] = webUserName;
    params['avareMethod'] = avareMethod;
    params['httpMethod'] = httpMethod;
    String ret = await post(avareLmfsUrl);
    mError = parseError(ret);
    return ret;
  }

  Future<String> fileFlightPlan(LmfsPlan plan) async {
    String webUserName = "governer@gmail.com";
    String avareMethod = "FP/file";
    String httpMethod = "POST";
    params = plan.makeMap();
    params['webUserName'] = webUserName;
    params['avareMethod'] = avareMethod;
    params['httpMethod'] = httpMethod;
    String ret = await post(avareLmfsUrl);
    mError = parseError(ret);
    return ret;
  }

  Future<String> amendFlightPlan(LmfsPlan plan) async {
    String webUserName = "governer@gmail.com";
    String avareMethod = "FP/${plan.getId()}/amend";
    String httpMethod = "POST";
    params = plan.makeMap();
    params['webUserName'] = webUserName;
    params['avareMethod'] = avareMethod;
    params['httpMethod'] = httpMethod;
    params['versionStamp'] = plan.versionStamp;
    String ret = await post(avareLmfsUrl);
    mError = parseError(ret);
    return ret;
  }

  Future<void> getBriefing(
      LmfsPlan pl, bool translated, String routeWidth) async {
    String webUserName = "governer@gmail.com";
    String avareMethod = "FP/emailBriefing";
    String httpMethod = "POST";
    params = pl.makeMap();
    params['webUserName'] = webUserName;
    params['avareMethod'] = avareMethod;
    params['httpMethod'] = httpMethod;
    params['briefingType'] = "EMAIL";
    params['briefingEmailAddresses'] = "governer@gmail.com";
    params['recipientEmailAddresses'] = "governer@gmail.com";
    params['routeCorridorWidth'] = routeWidth;
    if (translated) {
      params['briefingPreferences'] = "{\"plainText\":true}";
    }
    String ret = await post(avareLmfsUrl);
    mError = parseError(ret);
  }

  String getError() {
    return mError;
  }
}






