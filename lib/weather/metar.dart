import 'package:avaremp/app_log.dart';
import 'package:avaremp/weather/weather.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class Metar extends Weather {
  final String text;
  final String category;
  final LatLng coordinate;

  Metar(super.station, super.expires, super.recieved, super.source, this.text, this.category, this.coordinate);

  Map<String, Object?> toMap() {
    Map<String, Object?> map  = {
      "station": station,
      "utcMs": expires.millisecondsSinceEpoch,
      "receivedMs": received.millisecondsSinceEpoch,
      "source": source,
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
    catch(e) {
      AppLog.logMessage("Error parsing METAR coordinate: $e");
    }

    return Metar(
      maps["station"] as String,
      DateTime.fromMillisecondsSinceEpoch(maps["utcMs"] as int),
      DateTime.fromMillisecondsSinceEpoch(maps["receivedMs"] as int),
      maps["source"] as String,
      maps["raw"] as String,
      maps["category"] as String,
      ll,
    );
  }

  Color getColor() {
    return getColorStatic(category);
  }

  static Color getColorStatic(String category) {
    switch(category) {
      case "VFR":
        return const Color(0xFF00FF00);
      case "MVFR":
        return const Color(0xFF0000FF);
      case "IFR":
        return const Color(0xFFFF0000);
      case "LIFR":
        return const Color(0xFF673AB7);
    }

    return const Color(0xAAFFFFFF);
  }

  Icon getIcon() {
    switch (category) {
      case "VFR":
        return const Icon(Icons.circle, color: Color(0xFF008F00), );
      case "MVFR":
        return const Icon(Icons.circle, color: Color(0xFF0000FF), );
      case "IFR":
        return const Icon(Icons.circle, color: Color(0xFFFF0000), );
      case "LIFR":
        return const Icon(Icons.circle, color: Color(0xFF673AB7), );
    }

    return const Icon(Icons.circle, color: Color(0xFFFFFFFF), );
  }

  @override
  String toString() {
    return "${super.toString()}$text";
  }

  static (String?, String?) getWind(String report) {
    final RegExp wind = RegExp(r'^(?<dir>([0-2][0-9]|3[0-6])0|///|VRB)'
      r'P?(?<speed>\d{2,3}|//|///)'
      r'(G(P)?(?<gust>\d{2,3}))?'
      r'(?<units>KT|MPS)$');

    List<String> tokens = report.split(" ");
    for(String token in tokens) {

      var windSpeedDir = wind.firstMatch(token);
      if(windSpeedDir != null) {
        String? dir = windSpeedDir.namedGroup("dir");
        String? speed = windSpeedDir.namedGroup("speed");
        if(dir != null && speed != null) {
          if(dir == 'VRB') {
            dir = '0'; // variable wind, return 0
          }
          return (dir, speed);
        }
      }
    }
    return(null, null);
  }

  double? getWindDirection() {
    String? wd;
    (wd, _) = getWind(text);
    try {
      return double.parse(wd!);
    }
    catch (e) {
      return null;
    }
  }

  double? getWindSpeed() {
    String? ws;
    (_, ws) = getWind(text);
    try {
      return double.parse(ws!);
    }
    catch (e) {
      return null;
    }
  }

  static String getCategory(String report) {
    List<String> tokens = report.split(" ");
    String? integer;
    String? fraction;
    String? visibilityMeters;
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
        visibilityMeters = vis.namedGroup("vis");
        integer = vis.namedGroup("integer");
        fraction = vis.namedGroup("fraction");
        if(null != integer) {
          try {
            visSM = double.parse(integer);
          }
          catch(e) {
            AppLog.logMessage("Metar.getCategory: error parsing visibility integer $integer");
          }
        }
        else if(null != fraction) {
          visSM = 0.5; // less than 1
        }
        else if (null != visibilityMeters) {
          try {
            visSM = (double.parse(visibilityMeters) / 1000) * 0.621371;
          }
          catch (e) {
            AppLog.logMessage("Metar.getCategory: error parsing visibility meters $visibilityMeters");
          }
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
            catch (e) {
              AppLog.logMessage("Metar.getCategory: error parsing cloud height $height" );
            }
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

