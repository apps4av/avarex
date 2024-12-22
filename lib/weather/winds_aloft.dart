import 'dart:math';

import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/weather.dart';
import 'package:flutter/material.dart';

class WindsAloft extends Weather {
  String w0k; // this optionally comes from metar.
  String w3k;
  String w6k;
  String w9k;
  String w12k;
  String w18k;
  String w24k;
  String w30k;
  String w34k;
  String w39k;

  static String windZero = "0000";

  WindsAloft(super.station, super.expires, this.w0k, this.w3k, this.w6k, this.w9k, this.w12k, this.w18k, this.w24k, this.w30k, this.w34k, this.w39k);

  static (int?, int?) decodeWind(String wind) {

    if(wind.length < 4) {
      return (null, null);
    }

    int dir;
    int speed;
    try {
      dir = int.parse(wind.substring(0, 2)) * 10;
      speed = int.parse(wind.substring(2, 4));
    }
    catch(e) {
      return (null, null);
    }

    if(dir == 990 && speed == 0) {
      return (0, 0); // light and variable
    }
    if(dir >= 510) {
      dir -= 500;
      speed += 100;
    }

    return(dir, (speed.toDouble() * Storage().units.knotsTo).round());
  }

  (double?, double?) getWindAtAltitude(double altitude) { // dir, speed
    String wHigher;
    String wLower;
    double higherAltitude;
    double lowerAltitude;

    // slope of line, wind at y and altitude at x, y = mx + b
    // slope = (wind_at_higher_altitude - wind_at_lower_altitude) / (higher_altitude - lower_altitude)
    // wind =  slope * altitude + wind_intercept
    // wind_intercept = wind_at_lower_altitude - slope * lower_altitude

    // fill missing wind from higher altitude
    w34k = w34k.isEmpty ? w39k : w34k;
    w30k = w30k.isEmpty ? w34k : w30k;
    w24k = w24k.isEmpty ? w30k : w24k;
    w18k = w18k.isEmpty ? w24k : w18k;
    w12k = w12k.isEmpty ? w18k : w12k;
    w9k = w9k.isEmpty ? w12k : w9k;
    w6k = w6k.isEmpty ? w9k : w6k;
    w3k = w3k.isEmpty ? w6k : w3k;
    w0k = w0k.isEmpty ? w3k : w0k;

    if (altitude < 0) {
      return (0, 0);
    }
    else if (altitude >= 0 && altitude < 3000) {
      higherAltitude = 3000;
      lowerAltitude = 0;
      wHigher = w3k;
      wLower = w0k;
    }
    else if (altitude >= 3000 && altitude < 6000) {
      higherAltitude = 6000;
      lowerAltitude = 3000;
      wHigher = w6k;
      wLower = w3k;
    }
    else if (altitude >= 6000 && altitude < 9000) {
      higherAltitude = 9000;
      lowerAltitude = 6000;
      wHigher = w9k;
      wLower = w6k;
    }
    else if (altitude >= 9000 && altitude < 12000) {
      higherAltitude = 12000;
      lowerAltitude = 9000;
      wHigher = w12k;
      wLower = w9k;
    }
    else if (altitude >= 12000 && altitude < 18000) {
      higherAltitude = 18000;
      lowerAltitude = 12000;
      wHigher = w18k;
      wLower = w12k;
    }
    else if (altitude >= 18000 && altitude < 24000) {
      higherAltitude = 24000;
      lowerAltitude = 18000;
      wHigher = w24k;
      wLower = w18k;
    }
    else if (altitude >= 24000 && altitude < 30000) {
      higherAltitude = 30000;
      lowerAltitude = 24000;
      wHigher = w30k;
      wLower = w24k;
    }
    else if (altitude >= 30000 && altitude < 34000) {
      higherAltitude = 34000;
      lowerAltitude = 30000;
      wHigher = w34k;
      wLower = w30k;
    }
    else {
      higherAltitude = 39000;
      lowerAltitude = 34000;
      wHigher = w39k;
      wLower = w34k;
    }

    try {
      int? higherWindDir, lowerWindDir;
      int? higherWindSpeed, lowerWindSpeed;

      (higherWindDir, higherWindSpeed) = decodeWind(wHigher);
      (lowerWindDir, lowerWindSpeed) = decodeWind(wLower);
      if(higherWindSpeed == null ||  higherWindDir == null || lowerWindSpeed == null ||  lowerWindDir == null) {
        return (null, null);
      }
      double slope = ((higherWindSpeed - lowerWindSpeed) /
          (higherAltitude - lowerAltitude));
      double intercept = lowerWindSpeed - slope * lowerAltitude;
      double speed = slope * altitude + intercept;

      slope = ((higherWindDir - lowerWindDir) / (higherAltitude - lowerAltitude));
      intercept = lowerWindDir - slope * lowerAltitude;
      double dir = slope * altitude + intercept;

      return (dir, speed);
    }
    catch (e) {}

    return (null, null);
  }

  String getWindAtAltitudeRaw(int altitude) { // dir, speed

    if (altitude == 0) {
      return w0k;
    }
    if (altitude == 3000) {
      return w3k;
    }
    else if (altitude == 6000) {
      return w6k;
    }
    else if (altitude == 9000) {
      return w9k;
    }
    else if (altitude == 12000) {
      return w12k;
    }
    else if (altitude == 18000) {
      return w18k;
    }
    else if (altitude == 24000) {
      return w24k;
    }
    else if (altitude == 30000) {
      return w30k;
    }
    else if (altitude == 34000) {
      return w34k;
    }
    else if (altitude == 39000) {
      return w39k;
    }
    return "N/A";
  }


  Map<String, Object?> toMap() {
    Map<String, Object?> map  = {
      "station": station,
      "utcMs": expires.millisecondsSinceEpoch,
      "w0k": w0k,
      "w3k": w3k,
      "w6k": w6k,
      "w9k": w9k,
      "w12k": w12k,
      "w18k": w18k,
      "w24k": w24k,
      "w30k": w30k,
      "w34k": w34k,
      "w39k": w39k,
    };
    return map;
  }

  factory WindsAloft.fromMap(Map<String, dynamic> maps) {

    return WindsAloft(
      maps['station'] as String,
      DateTime.fromMillisecondsSinceEpoch(maps['utcMs'] as int),
      maps['w0k'] as String,
      maps['w3k'] as String,
      maps['w6k'] as String,
      maps['w9k'] as String,
      maps['w12k'] as String,
      maps['w18k'] as String,
      maps['w24k'] as String,
      maps['w30k'] as String,
      maps['w34k'] as String,
      maps['w39k'] as String,
    );
  }


  List<(String, String)> toList() {
    List<(String, String)> winds = [];
    for(double altitude = 0; altitude < 42000; altitude += 3000) {
      double? speed;
      double? dir;
      (dir, speed) = getWindAtAltitude(altitude);
      // show dir, speed, and actual string for every 3000ft
      winds.add(((altitude.round().toString().toString().padLeft(5, "0")), "${dir == null ? "" : "${dir.round().toString().padLeft(3, "0")}\u00b0"} ${speed == null ? "" : "@${speed.round()}"} (${getWindAtAltitudeRaw(altitude.round())})"));
    }
    return winds;
  }


  @override
  toString() {
    DateTime zulu = expires.toUtc(); // winds in Zulu time
    // boilerplate
    String wind = "Winds - $station (Temps negative above 24000)\nValid till ${zulu.day .toString().padLeft(2, "0")}${zulu.hour.toString().padLeft(2, "0")}00Z";
    return wind;
  }
}

class WindBarbPainter extends CustomPainter {
  final double speed;
  final double direction;

  WindBarbPainter(this.speed, this.direction);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Draw the main arrow line
    double x = size.width / 2;
    double y = size.height / 2;
    double length = size.width;
    double angle = (direction - 90) * pi / 180;
    double x2 = x + length * cos(angle);
    double y2 = y + length * sin(angle);
    canvas.drawLine(Offset(x, y), Offset(x2, y2), paint);

    // Draw barbs for wind speed
    double barbLength = 15;
    double barbSpacing = size.width / 8;
    int fullBarbs = (speed / 10).floor();
    int halfBarbs = ((speed % 10) / 5).round();

    for (int i = 0; i < fullBarbs; i++) {
      double barbX = x2 - (i) * barbSpacing * cos(angle);
      double barbY = y2 - (i) * barbSpacing * sin(angle);
      double barbX2 = barbX - barbLength * cos(angle + pi / 2);
      double barbY2 = barbY - barbLength * sin(angle + pi / 2);
      canvas.drawLine(Offset(barbX, barbY), Offset(barbX2, barbY2), paint);
    }

    if (halfBarbs > 0) {
      double barbX = x2 - (fullBarbs) * barbSpacing * cos(angle);
      double barbY = y2 - (fullBarbs) * barbSpacing * sin(angle);
      double barbX2 = barbX - (barbLength / 2) * cos(angle + pi / 2);
      double barbY2 = barbY - (barbLength / 2) * sin(angle + pi / 2);
      canvas.drawLine(Offset(barbX, barbY), Offset(barbX2, barbY2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

class NorthPainter extends CustomPainter {
  NorthPainter(this.variation);
  double variation;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    // Draw the main arrow line
    double x = size.width / 2;
    double y = size.height / 2;
    double length = size.width;
    double angle = (variation - 90) * pi / 180;
    double x2 = x + length * cos(angle);
    double y2 = y + length * sin(angle);
    canvas.drawLine(Offset(x, y), Offset(x2, y2), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

