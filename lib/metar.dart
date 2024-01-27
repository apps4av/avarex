import 'package:avaremp/weather.dart';
import 'package:flutter/material.dart';

class Metar extends Weather {
  String text;
  String category;

  Metar(super.station, super.expires, this.text, this.category);

  Map<String, Object?> toMap() {
    Map<String, Object?> map  = {
      "station": station,
      "utcMs": expires.millisecondsSinceEpoch,
      "raw": text,
      "category": category,
    };
    return map;
  }

  factory Metar.fromMap(Map<String, dynamic> maps) {

    return Metar(
      maps['station'] as String,
      DateTime.fromMillisecondsSinceEpoch(maps['utcMs'] as int),
      maps['raw'] as String,
      maps['category'] as String,
    );
  }

  Color getColor() {
    switch(category) {
      case "VFR":
        return Colors.green;
      case "MVFR":
        return Colors.blue;
      case "IFR":
        return Colors.red;
      case "LIFR":
        return Colors.deepPurple;
    }

    return Colors.white;
  }

}

