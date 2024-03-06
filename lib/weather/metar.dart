import 'package:avaremp/weather/weather.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class Metar extends Weather {
  String text;
  String category;
  LatLng coordinate;

  Metar(super.station, super.expires, this.text, this.category, this.coordinate);

  Map<String, Object?> toMap() {
    Map<String, Object?> map  = {
      "station": station,
      "utcMs": expires.millisecondsSinceEpoch,
      "raw": text,
      "category": category,
      "ARPLatitude": coordinate.latitude,
      "ARPLongitude": coordinate.longitude,
    };
    return map;
  }

  factory Metar.fromMap(Map<String, dynamic> maps) {
    LatLng ll = const LatLng(0, 0);

    try {
      ll = LatLng(maps["ARPLatitude"] as double, maps["ARPLongitude"] as double);
    }
    catch(e) {}

    return Metar(
      maps["station"] as String,
      DateTime.fromMillisecondsSinceEpoch(maps["utcMs"] as int),
      maps["raw"] as String,
      maps["category"] as String,
      ll,
    );
  }

  Color getColor() {
    switch(category) {
      case "VFR":
        return const Color(0xAA00FF00);
      case "MVFR":
        return const Color(0xAA0000FF);
      case "IFR":
        return const Color(0xAAFF0000);
      case "LIFR":
        return const Color(0xAA673AB7);
    }

    return const Color(0xAAFFFFFF);
  }

  Icon getIcon() {
    switch (category) {
      case "VFR":
        return const Icon(Icons.circle, color: Color(0x8000FF00), shadows: [Shadow(offset: Offset(1, 1), color: Color(0x80000000))],);
      case "MVFR":
        return const Icon(Icons.circle, color: Color(0x800000FF), shadows: [Shadow(offset: Offset(1, 1), color: Color(0x80000000))],);
      case "IFR":
        return const Icon(Icons.circle, color: Color(0x80FF0000), shadows: [Shadow(offset: Offset(1, 1), color: Color(0x80000000))],);
      case "LIFR":
        return const Icon(Icons.circle, color: Color(0x80673AB7), shadows: [Shadow(offset: Offset(1, 1), color: Color(0x80000000))],);
    }

    return const Icon(Icons.circle, color: Color(0x80FFFFFF), shadows: [Shadow(offset: Offset(1, 1), color: Color(0x80000000))],);
  }

  @override
  String toString() {
    return text;
  }

}

