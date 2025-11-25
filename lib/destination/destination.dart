// destination base class

import 'dart:convert';
import 'package:universal_io/io.dart';

import 'package:avaremp/app_log.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'destination_calculations.dart';
import 'package:avaremp/data/main_database_helper.dart';

class Destination {

  final String locationID;
  final String type;
  final String facilityName;
  final LatLng coordinate;
  double? elevation;
  double? geoAltitude;
  double? geoVariation;
  String? secondaryName; // used for holding other names like airway name
  DestinationCalculations? calculations; // how to get there

  Destination({
    required this.locationID,
    required this.type,
    required this.facilityName,
    required this.coordinate,
  }) {
    MainDatabaseHelper.db.getGeoInfo(coordinate).then((value) {
      geoAltitude = value.$1;
      geoVariation = value.$2;
    });
  }

  @override
  toString() {
    return locationID;
  }

  static const String typeGps = "GPS";
  static const String typeAirway = "Airway";
  static const String typeProcedure = "Procedure";

  static bool isAirway(String type) {
    return type == typeAirway;
  }

  static bool isProcedure(String type) {
    return type == typeProcedure;
  }

  static bool isNav(String type) {
    return type == "TACAN" ||
        type == "NDB/DME" ||
        type == "MARINE NDB" ||
        type == "UHF/NDB" ||
        type == "NDB" ||
        type == "VOR/DME" ||
        type == "VOT" ||
        type == "VORTAC" ||
        type == "FAN MARKER" ||
        type == "VOR";
  }

  static String toSexagesimal(LatLng ll) {
    double lat = ll.latitude;
    double lon = ll.longitude;
    // convert lat to sexagesimal
    String latDir = lat >= 0 ? "N" : "S";
    String lonDir = lon >= 0 ? "E" : "W";
    lat = lat.abs();
    lon = lon.abs();
    int latDeg = lat.floor();
    double latMin = (lat - latDeg) * 60;
    int latMinInt = latMin.floor();
    double latSec = (latMin - latMinInt) * 60;
    int latSecInt = latSec.floor();
    int lonDeg = lon.floor();
    double lonMin = (lon - lonDeg) * 60;
    int lonMinInt = lonMin.floor();
    double lonSec = (lonMin - lonMinInt) * 60;
    int lonSecInt = lonSec.floor();
    return "${latDeg.toString().padLeft(3, "0")}${latMinInt.toString().padLeft(2, "0")}${latSecInt.toString().padLeft(2, "0")}$latDir,"
           "${lonDeg.toString().padLeft(3, "0")}${lonMinInt.toString().padLeft(2, "0")}${lonSecInt.toString().padLeft(2, "0")}$lonDir";

  }

  // This is 1800wxbrief format
  static String toSexagesimalLmfs(LatLng ll) {
    double lat = ll.latitude;
    double lon = ll.longitude;
    // convert lat to sexagesimal
    String latDir = lat >= 0 ? "N" : "S";
    String lonDir = lon >= 0 ? "E" : "W";
    lat = lat.abs();
    lon = lon.abs();
    int latDeg = lat.floor();
    double latMin = (lat - latDeg) * 60;
    int latMinInt = latMin.floor();
    double latSec = (latMin - latMinInt) * 60;
    int latSecInt = latSec.floor();
    int lonDeg = lon.floor();
    double lonMin = (lon - lonDeg) * 60;
    int lonMinInt = lonMin.floor();
    double lonSec = (lonMin - lonMinInt) * 60;
    int lonSecInt = lonSec.floor();
    return "${latDeg.toString().padLeft(2, "0")}${latMinInt.toString().padLeft(2, "0")}${latSecInt.toString().padLeft(2, "0")}$latDir/"
        "${lonDeg.toString().padLeft(3, "0")}${lonMinInt.toString().padLeft(2, "0")}${lonSecInt.toString().padLeft(2, "0")}$lonDir";

  }


  static LatLng parseFromSexagesimalFullOrPartial(String input) {
    double lat = 0;
    double latMin = 0;
    double latSec = 0;
    String latGeo = "N";
    double lon = 0;
    double lonMin = 0;
    double lonSec = 0;
    String lonGeo = "W";

    RegExp exp = RegExp(r"([0-9][0-9][0-9])([0-9][0-9])([0-9][0-9])([NS]),([0-9][0-9][0-9])([0-9][0-9])([0-9][0-9])([EW])");
    Match? match = exp.firstMatch(input);
    if(null != match) {
      lat = double.parse(match.group(1)!);
      latMin = double.parse(match.group(2)!);
      latSec = double.parse(match.group(3)!);
      latGeo = match.group(4)!;
      lon = double.parse(match.group(5)!);
      lonMin = double.parse(match.group(6)!);
      lonSec = double.parse(match.group(7)!);
      lonGeo = match.group(8)!;
    }

    lat += latMin / 60.0 + latSec / 3600.0;
    lon += lonMin / 60.0 + lonSec / 3600.0;
    if(latGeo == "S") {
      lat = -lat;
    }
    if(lonGeo == "W") {
      lon = -lon;
    }
    LatLng coordinate = LatLng(lat, lon);
    return coordinate;
  }

  // convert address to latlng
  static Future<LatLng?> findGpsCoordinateFromAddressLookup(String address) async {
    String query =  Uri.encodeFull("https://nominatim.openstreetmap.org/search?addressdetails=1&format=jsonv2&limit=1&q=$address");
    // now do http get on the query
    try {
      HttpClient client = HttpClient();
      client.userAgent = "AvareX";
      HttpClientRequest request = await client.getUrl(Uri.parse(query));
      HttpClientResponse response = await request.close();

      if (response.statusCode == HttpStatus.ok) {
        String responseBody = await response.transform(utf8.decoder).join();
        final decoded = json.decode(responseBody);
        return LatLng(double.parse(decoded[0]["lat"]), double.parse(decoded[0]["lon"]));
      } else {
        return null;
      }
    }
    catch(e) {
      AppLog.logMessage("Error in findGpsCoordinateFromAddressLookup: $e");
    }
    return null;
  }

  static bool isAirport(String type) {
    return type == "AIRPORT" ||
        type == "SEAPLANE BAS" ||
        type == "HELIPORT" ||
        type == "ULTRALIGHT" ||
        type == "GLIDERPORT" ||
        type == "BALLOONPORT" ||
        type == "OUR-AP";
  }

  static bool isFix(String type) {
    return type == "YREP-PT" ||
        type == "YRNAV-WP" ||
        type == "NARTCC-BDRY" ||
        type == "NAWY-INTXN" ||
        type == "NTURN-PT" ||
        type == "YWAYPOINT" ||
        type == "YMIL-REP-PT" ||
        type == "YCOORDN-FIX" ||
        type == "YMIL-WAYPOINT" ||
        type == "YNRS-WAYPOINT" ||
        type == "YVFR-WP" ||
        type == "YGPS-WP" ||
        type == "YCNF" ||
        type == "YRADAR" ||
        type == "NDME-FIX" ||
        type == "NNOT-ASSIGNED" ||
        type == "NDP-TRANS-XING" ||
        type == "NSTAR-TRANS-XIN" ||
        type == "NBRG-INTXN";
  }

  static bool isGps(String type) {
    return type == "GPS";
  }

  factory Destination.fromMap(Map<String, dynamic> maps) {
    return Destination(
      locationID: maps['LocationID'] as String,
      facilityName: maps['FacilityName'] as String,
      type: maps['Type'] as String,
      coordinate: LatLng(maps['ARPLatitude'] as double, maps['ARPLongitude'] as double));
  }

  Map<String, Object?> toMap() {
    Map<String, Object?> map  = {
      "LocationID": locationID,
      "FacilityName" : facilityName,
      "Type": type,
      "ARPLatitude": coordinate.latitude,
      "ARPLongitude": coordinate.longitude,
    };
    return map;
  }

  factory Destination.fromLatLng(LatLng ll) {
    return Destination(
        locationID: toSexagesimal(ll),
        facilityName: toSexagesimal(ll),
        type: Destination.typeGps,
        coordinate: ll);
  }
}

class NavDestination extends Destination {

  String class_;
  String hiwas;

  NavDestination({
    required super.locationID,
    required super.type,
    required super.facilityName,
    required super.coordinate,
    required this.class_,
    required this.hiwas,});

  factory NavDestination.fromMap(Map<String, dynamic> maps) {

    double elevation = 0;
    try {
      elevation = double.parse(maps['Elevation'] as String);
    }
    catch(e) {
      AppLog.logMessage("Error parsing elevation for nav: $e");
    }

    NavDestination d = NavDestination(
      locationID: maps['LocationID'] as String,
      type: maps['Type'] as String,
      facilityName: maps['FacilityName'] as String,
      coordinate: LatLng(
          maps['ARPLatitude'] as double, maps['ARPLongitude'] as double),
      hiwas: maps['Hiwas'] as String,
      class_: maps['Class'] as String,
    );
    d.elevation = elevation;
    return d;
  }
}

class FixDestination extends Destination {
  FixDestination({
    required super.locationID,
    required super.type,
    required super.facilityName,
    required super.coordinate,});

  factory FixDestination.fromMap(Map<String, dynamic> maps) {
    return FixDestination(
        locationID: maps['LocationID'] as String,
        facilityName: maps['FacilityName'] as String,
        type: maps['Type'] as String,
        coordinate: LatLng(maps['ARPLatitude'] as double, maps['ARPLongitude'] as double));
  }

}

class GpsDestination extends Destination {
  GpsDestination({
    required super.locationID,
    required super.type,
    required super.facilityName,
    required super.coordinate,});
}

class AirportDestination extends Destination {

  final List<Map<String, dynamic>> frequencies;
  final List<Map<String, dynamic>> runways;
  final List<Map<String, dynamic>> awos;
  final String unicom;
  final String ctaf;

  AirportDestination({
    required super.locationID,
    required super.type,
    required super.facilityName,
    required super.coordinate,
    required this.frequencies,
    required this.awos,
    required this.runways,
    required this.unicom,
    required this.ctaf
  });

  factory AirportDestination.fromMap(Map<String, dynamic> maps,
      List<Map<String, dynamic>> mapsFreq,
      List<Map<String, dynamic>> mapsAwos,
      List<Map<String, dynamic>> mapsRunways) {

    double elevation = 0;
    try {
      elevation = double.parse(maps['ARPElevation'] as String);
    }
    catch(e) {
      AppLog.logMessage("Error parsing elevation for airport: $e");
    }

    AirportDestination d = AirportDestination(
        locationID: maps['LocationID'] as String,
        facilityName: maps['FacilityName'] as String,
        coordinate: LatLng(maps['ARPLatitude'] as double, maps['ARPLongitude'] as double),
        type: maps['Type'] as String,
        ctaf: maps['CTAFFrequency'] as String,
        unicom: maps['UNICOMFrequencies'] as String,
        frequencies: mapsFreq,
        awos: mapsAwos,
        runways: mapsRunways
    );
    d.elevation = elevation;
    return d;
  }

}

class AirwayDestination extends Destination {

  List<Destination> points; // this has many waypoints

  AirwayDestination({
    required super.locationID,
    required super.type,
    required super.facilityName,
    required super.coordinate,
    required this.points
  });

  factory AirwayDestination.fromMap(String name, List<Map<String, dynamic>> maps) {

    // airway has multiple entries for sequences
    List<Destination> ret = List.generate(maps.length, (i) {
      Destination d = Destination(
        locationID: maps[i]['name'] as String,
        facilityName: maps[i]['name'] as String,
        type: Destination.typeAirway,
        coordinate: LatLng(maps[i]['Latitude'] as double, maps[i]['Longitude'] as double),
      );
      d.secondaryName = maps[i]['sequence'] as String; // this will be overwritten after airway is created
      return d;
    });

    return AirwayDestination(
        locationID: name,
        type: ret[0].type,
        facilityName: name,
        coordinate: ret[0].coordinate,
        points: ret);
  }
}


class ProcedureDestination extends Destination {

  List<Destination> points; // this has many waypoints

  ProcedureDestination({
    required super.locationID,
    required super.type,
    required super.facilityName,
    required super.coordinate,
    required this.points
  });

  factory ProcedureDestination.fromMap(String name, List<Map<String, dynamic>> maps) {

    // airway has multiple entries for sequences
    List<Destination> ret = List.generate(maps.length, (i) {
      return Destination(
        locationID: (maps[i]['fix_identifier'] as String).trim(),
        facilityName: (maps[i]['fix_identifier'] as String).trim(),
        type: Destination.typeProcedure,
        coordinate: LatLng(maps[i]['Latitude'] as double, maps[i]['Longitude'] as double),
      );
    });

    return ProcedureDestination(
        locationID: name,
        type: ret[0].type,
        facilityName: name,
        coordinate: ret[0].coordinate,
        points: ret);
  }
}

class DestinationFactory {

  // make a destination from a generic destination through db query.
  static Future<Destination> make(Destination d) async {

    String type = d.type;
    Destination ret = d;

    if (Destination.isNav(type)) {
      NavDestination? destination = await MainDatabaseHelper.db.findNav(d.locationID);
      ret = destination ?? d;
    }
    else if (Destination.isAirport(type)) {
      AirportDestination? destination = await MainDatabaseHelper.db.findAirport(d.locationID);
      ret = destination ?? d;
    }
    else if (Destination.isFix(type)) {
      FixDestination? destination = await MainDatabaseHelper.db.findFix(d.locationID);
      ret = destination ?? d;
    }
    else if (Destination.isAirway(type)) {
      AirwayDestination? destination = await MainDatabaseHelper.db.findAirway(d.locationID);
      ret = destination ?? d;
    }
    else if (Destination.isProcedure(type)) {
      ProcedureDestination? destination = await MainDatabaseHelper.db.findProcedure(d.locationID);
      ret = destination ?? d;
    }
    else if (Destination.isGps(type)) {
      ret = GpsDestination(locationID: d.locationID, type: d.type, facilityName: d.facilityName, coordinate: d.coordinate);
    }

    return ret;
  }

  static Widget getIcon(String type, Color color) {
    if(Destination.isNav(type)) {
      return Transform.rotate(angle: 90 * pi / 180, child: Icon(MdiIcons.hexagonOutline, color: color,)); // hexagon rotated looks like a vor
    }
    else if(Destination.isAirport(type)) {
      return Icon(MdiIcons.circleOutline, color: color);
    }
    else if(Destination.isFix(type)) {
      return Icon(MdiIcons.triangleOutline, color: color);
    }
    else if(Destination.isGps(type)) {
      return Icon(MdiIcons.crosshairsGps, color: color);
    }
    else if(Destination.isAirway(type)) {
      return Icon(MdiIcons.rayStartVertexEnd, color: color);
    }
    else if(Destination.isProcedure(type)) {
      return Icon(MdiIcons.mapMarkerPath, color: color);
    }
    return Icon(MdiIcons.help, color: color);
  }

}
