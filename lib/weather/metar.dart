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

  static String getCategory(String report) {
    List<String> tokens = report.split(" ");
    String? integer;
    String? fraction;
    String? height;
    String? cover;
    double visSM = 6;
    double cloudFt = 12000;
    String category = "VFR";

    for(String token in tokens.reversed) { // run reversed as the first cloud layer is the lowest layer
      final RegExp visibility = RegExp(
          r'^((?<vis>\d{4}|//\//)'
          r'(?<dir>[NSEW]([EW])?)?|'
          r'(M|P)?(?<integer>\d{1,2})?_?'
          r'(?<fraction>\d/\d)?'
          r'(?<units>SM|KM|M|U)|'
          r'(?<cavok>CAVOK))$');

      final RegExp cloud =
      RegExp(
          r'^(?<cover>VV|CLR|SKC|NSC|NCD|BKN|SCT|FEW|OVC|///)'
          r'(?<height>\d{3}|///)?'
          r'(?<type>TCU|CB|///)?$');

      var vis = visibility.firstMatch(token);
      if(vis != null) {
        integer = vis.namedGroup("integer");
        fraction = vis.namedGroup("fraction");
        if(null != integer) {
          try {
            visSM = double.parse(integer);
          }
          catch(e) {}
        }
        else if(null != fraction) {
          visSM = 0.5; // less than 1
        }
      }
      var cld = cloud.firstMatch(token);
      if(cld != null) {
        cover = cld.namedGroup("cover");
        height = cld.namedGroup("height");
        if(height != null && cover != null) {
          if(cover == "OVC" || cover == "BKN") {
            try {
              cloudFt = double.parse(height) * 100;
            }
            catch (e){}
          }
        }
      }
    }

    // find flight category
    // VFR: > 3000 ft AND > 5SM
    // MVFR: >= 1000 ft AND / OR > 3 SM
    // IFR: >= 500 ft AND / OR >= 1 SM
    // LIFR < 500 ft AND / OR < 1 SM
    if(cloudFt < 500 || visSM < 1) {
      category = "LIFR";
    }
    else if(cloudFt < 1000 || visSM < 1) {
      category = "IFR";
    }
    else if(cloudFt <= 3000 || visSM <= 3) {
      category = "MVFR";
    }
    return category;
  }
}

