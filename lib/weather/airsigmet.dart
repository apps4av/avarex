import 'dart:convert';

import 'package:avaremp/weather/weather.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class AirSigmet extends Weather {
  String text;
  List<LatLng> coordinates;
  String hazard;
  String severity;
  String type;
  bool showShape = false; // reduce clutter on screen

  AirSigmet(super.station, super.expires, this.text, this.coordinates, this.hazard, this.severity, this.type);


  Map<String, Object?> toMap() {

    List<List<double>> ll = [];
    for(LatLng c in coordinates) {
      ll.add([c.latitude, c.longitude]);
    }

    Map<String, Object?> map  = {
      "station": station,
      "utcMs": expires.millisecondsSinceEpoch,
      "raw": text,
      "coordinates" : jsonEncode(ll),
      "hazard": hazard,
      "severity": severity,
      "type": type
    };
    return map;
  }

  factory AirSigmet.fromMap(Map<String, dynamic> maps) {
    List<LatLng> ll = [];
    List<dynamic> coordinates = jsonDecode(maps['coordinates'] as String);
    for(dynamic coordinate in coordinates) {
      ll.add(LatLng(coordinate[0], coordinate[1]));
    }

    return AirSigmet(
      maps['station'] as String,
      DateTime.fromMillisecondsSinceEpoch(maps['utcMs'] as int),
      maps['raw'] as String,
      ll,
      maps['hazard'] as String,
      maps['severity'] as String,
      maps['type'] as String,
    );
  }

  Color getColor() {
    if(hazard == "TURB") {
      return Colors.deepOrangeAccent;
    }
    if(hazard == "IFR") {
      return Colors.purpleAccent;
    }
    if(hazard == "ICE") {
      return Colors.blueAccent;
    }
    if(hazard == "MTN OBSCN") {
      return Colors.greenAccent;
    }
    return Colors.black;

  }
  @override
  String toString() {
    return text.replaceAll(RegExp(r'[^\w\s]+'),' ');
  }

}

