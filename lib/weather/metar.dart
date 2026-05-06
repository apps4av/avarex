import 'package:avaremp/utils/app_log.dart';
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

  static final RegExp _visibilityRegex = RegExp(
      r'^((?<vis>\d{4}|////)'
      r'(?<dir>[NSEW]([EW])?)?|'
      r'(M|P)?(?<integer>\d{1,2})?_?'
      r'(?<fraction>\d/\d)?'
      r'(?<units>SM|KM|M|U)|'
      r'(?<cavok>CAVOK))$');

  static final RegExp _cloudRegex = RegExp(
      r'^(?<cover>VV|CLR|SKC|NSC|NCD|BKN|SCT|FEW|OVC|///)'
      r'(?<height>\d{3}|///)?'
      r'(?<type>TCU|CB|///)?$');

  static String getCategory(String report) {
    // Coalesce "N N/N SM" mixed-numeric visibility into a single token so the
    // regex (which expects integer_fraction) can match it.
    final String normalized = report.replaceAllMapped(
        RegExp(r'(?<![\d/])(\d{1,2})\s+(\d/\d)(SM|KM)\b'),
        (m) => '${m.group(1)}_${m.group(2)}${m.group(3)}');
    final List<String> tokens = normalized.split(" ");

    double visSM = 6;
    double cloudFt = 12000;
    double? minCeilingFt;

    for (final String token in tokens) {
      final vis = _visibilityRegex.firstMatch(token);
      if (vis != null) {
        final visibilityMeters = vis.namedGroup("vis");
        final integer = vis.namedGroup("integer");
        final fraction = vis.namedGroup("fraction");
        final cavok = vis.namedGroup("cavok");
        if (cavok != null) {
          visSM = 10.0; // CAVOK ⇒ at least 10 km / ~6 SM
        }
        else if (integer != null || fraction != null) {
          double parsed = 0;
          if (integer != null) {
            try { parsed += double.parse(integer); }
            catch (e) { AppLog.logMessage("Metar.getCategory: error parsing visibility integer $integer"); }
          }
          if (fraction != null) {
            final parts = fraction.split('/');
            if (parts.length == 2) {
              try {
                final num = double.parse(parts[0]);
                final den = double.parse(parts[1]);
                if (den != 0) parsed += num / den;
              }
              catch (e) { AppLog.logMessage("Metar.getCategory: error parsing visibility fraction $fraction"); }
            }
          }
          visSM = parsed;
        }
        else if (visibilityMeters != null && visibilityMeters != "////") {
          try {
            visSM = (double.parse(visibilityMeters) / 1000) * 0.621371;
          }
          catch (e) {
            AppLog.logMessage("Metar.getCategory: error parsing visibility meters $visibilityMeters");
          }
        }
      }

      final cld = _cloudRegex.firstMatch(token);
      if (cld != null) {
        final cover = cld.namedGroup("cover");
        final height = cld.namedGroup("height");
        // VV (vertical visibility / indefinite ceiling) IS a ceiling.
        if (cover == "OVC" || cover == "BKN" || cover == "VV") {
          if (height != null && height != "///") {
            try {
              final ft = double.parse(height) * 100;
              if (minCeilingFt == null || ft < minCeilingFt) {
                minCeilingFt = ft;
              }
            }
            catch (e) {
              AppLog.logMessage("Metar.getCategory: error parsing cloud height $height");
            }
          }
        }
      }
    }

    if (minCeilingFt != null) {
      cloudFt = minCeilingFt;
    }

    // FAA flight categories:
    //   VFR  - ceiling > 3000 ft AND vis > 5 SM
    //   MVFR - ceiling 1000-3000 ft AND/OR vis 3-5 SM
    //   IFR  - ceiling 500-999 ft AND/OR vis 1 to <3 SM
    //   LIFR - ceiling < 500 ft AND/OR vis < 1 SM
    if (cloudFt < 500 || visSM < 1) {
      return "LIFR";
    }
    if (cloudFt < 1000 || visSM < 3) {
      return "IFR";
    }
    if (cloudFt <= 3000 || visSM <= 5) {
      return "MVFR";
    }
    return "VFR";
  }

  static int? getCeilingFtFromReport(String report) {
    final RegExp cloud = RegExp(
        r'^(?<cover>VV|CLR|SKC|NSC|NCD|BKN|SCT|FEW|OVC|///)'
        r'(?<height>\d{3}|///)?'
        r'(?<type>TCU|CB|///)?$');
    int? ceilingFt;
    List<String> tokens = report.split(" ");
    for(String token in tokens) {
      var cld = cloud.firstMatch(token);
      if(cld == null) {
        continue;
      }
      String? cover = cld.namedGroup("cover");
      String? height = cld.namedGroup("height");
      if(cover == null || height == null || height == "///") {
        continue;
      }
      if(cover == "OVC" || cover == "BKN" || cover == "VV") {
        try {
          int ft = int.parse(height) * 100;
          if(ceilingFt == null || ft < ceilingFt) {
            ceilingFt = ft;
          }
        }
        catch (e) {
          AppLog.logMessage("Metar.getCeilingFt: error parsing cloud height $height");
        }
      }
    }
    return ceilingFt;
  }

  int? getCeilingFt() {
    return getCeilingFtFromReport(text);
  }
}

