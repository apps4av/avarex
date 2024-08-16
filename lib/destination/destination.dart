// destination base class

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
  DestinationCalculations? calculations; // how to get there

  Destination({
    required this.locationID,
    required this.type,
    required this.facilityName,
    required this.coordinate,
  });

  @override
  toString() {
    return locationID;
  }

  static const String typeGps = "GPS";
  static const String typeAirway = "Airway";

  static bool isAirway(String type) {
    return type == typeAirway;
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

  static String formatSexagesimal(String input) {
    return input.replaceAll("'", " ").replaceAll("\"", " ").replaceAll("\u00b0", " ");
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
        locationID: ll.toSexagesimal(),
        facilityName: ll.toSexagesimal(),
        type: Destination.typeGps,
        coordinate: ll);
  }
}

class NavDestination extends Destination {

  double elevation;
  String class_;
  String hiwas;

  NavDestination({
    required super.locationID,
    required super.type,
    required super.facilityName,
    required super.coordinate,
    required this.elevation,
    required this.class_,
    required this.hiwas,});

  factory NavDestination.fromMap(Map<String, dynamic> maps) {

    double elevation = 0;
    try {
      elevation = double.parse(maps['Elevation'] as String);
    }
    catch(e) {}

    return NavDestination(
      locationID: maps['LocationID'] as String,
      type: maps['Type'] as String,
      facilityName: maps['FacilityName'] as String,
      coordinate: LatLng(
          maps['ARPLatitude'] as double, maps['ARPLongitude'] as double),
      elevation: elevation,
      hiwas: maps['Hiwas'] as String,
      class_: maps['Class'] as String,
    );
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

  final double elevation;
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
    required this.elevation,
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
    catch(e) {}

    return AirportDestination(
        locationID: maps['LocationID'] as String,
        elevation: elevation,
        facilityName: maps['FacilityName'] as String,
        coordinate: LatLng(maps['ARPLatitude'] as double, maps['ARPLongitude'] as double),
        type: maps['Type'] as String,
        ctaf: maps['CTAFFrequency'] as String,
        unicom: maps['UNICOMFrequencies'] as String,
        frequencies: mapsFreq,
        awos: mapsAwos,
        runways: mapsRunways
    );
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

  factory AirwayDestination.fromMap(List<Map<String, dynamic>> maps) {

    // airway has multiple entries for sequences
    List<Destination> ret = List.generate(maps.length, (i) {
      return Destination(
        locationID: maps[i]['name'] as String,
        facilityName: maps[i]['name'] as String,
        type: Destination.typeAirway,
        coordinate: LatLng(maps[i]['Latitude'] as double, maps[i]['Longitude'] as double),
      );
    });

    return AirwayDestination(
        locationID: ret[0].locationID,
        type: ret[0].type,
        facilityName: ret[0].facilityName,
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
    else if (Destination.isGps(type)) {
      ret = GpsDestination(locationID: d.locationID, type: d.type, facilityName: d.facilityName, coordinate: d.coordinate);
    }

    return ret;
  }

  static Widget getIcon(String type, Color? color) {
    color = color ?? Colors.white;
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
    return Icon(MdiIcons.help, color: color);
  }

}
