import 'package:avaremp/weather/time_segment_pie_chart.dart';
import 'package:avaremp/weather/weather.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class Taf extends Weather {
  final String text;
  final LatLng coordinate;
  final List<DateTime> times = [];
  final List<Color> colors = [];
  bool parsed = false;

  Taf(super.station, super.expires, super.recieved, super.source, this.text, this.coordinate);

  Map<String, Object?> toMap() {
    Map<String, Object?> map  = {
      "station": station,
      "utcMs": expires.millisecondsSinceEpoch,
      "receivedMs": received.millisecondsSinceEpoch,
      "source": source,
      "raw": text,
      "ARPLatitude": coordinate.latitude,
      "ARPLongitude": coordinate.longitude,
    };
    return map;
  }

  factory Taf.fromMap(Map<String, dynamic> maps) {
    LatLng ll = const LatLng(0, 0);

    try {
      ll = LatLng(maps["ARPLatitude"] as double, maps["ARPLongitude"] as double);
    }
    catch(e) {
      debugPrint("Error parsing TAF coordinate: $e");
    }

    return Taf(
      maps['station'] as String,
      DateTime.fromMillisecondsSinceEpoch(maps['utcMs'] as int),
      DateTime.fromMillisecondsSinceEpoch(maps['receivedMs'] as int),
      maps['source'] as String,
      maps['raw'] as String,
      ll
    );
  }

  Color getColor(String category) {
    switch(category) {
      case "VFR":
        return const Color(0xFF00FF00);
      case "MVFR":
        return const Color(0xFF0000FF);
      case "IFR":
        return const Color(0xFFFF0000);
      case "LIFR":
        return const Color(0xFFFFA0CB);
    }

    return const Color(0xAAFFFFFF);
  }

  void _parseCategories() {

    final RegExp header = RegExp(
      r'^(TAF)?\s*(AMD|COR)?\s*'
      r'(?<icaoCode>[A-Z]{4})'
      r'\s*'
      r'(?<originDate>\d{0,2})'
      r'(?<originHours>\d{0,2})'
      r'(?<originMinutes>\d{0,2})'
      r'Z?'
      r'\s*'
      r'(?<validFromDate>\d{0,2})'
      r'(?<validFromHours>\d{0,2})'
      r'/'
      r'(?<validTillDate>\d{0,2})'
      r'(?<validTillHours>\d{0,2})');

    RegExp group = RegExp(
        r'^(TEMPO|BECMG|FM)'
        r'\s*(?<validFromDate>0[1-9]|[12][0-9]|3[01])'
        r'(?<validFromHours>[0-1]\d|2[0-3])'
        r'('
        r'/'
        r'(?<validToDate>0[1-9]|[12][0-9]|3[01])'
        r'(?<validToHours>[0-1]\d|2[0-3])'
        r')?');

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

    List<String> lines = text.split("\n");
    String? validTillHours;
    String? validTillDate;
    bool firstLine = true;
    for (String line in lines) {
      List<String> tokens = line.split(" ");
      String? integer;
      String? fraction;
      String? visibilityMeters;
      String? height;
      String? cover;
      String? validFromHours;
      String? validFromDate;
      double? visSM;
      double? cloudFt;
      String? category;

      if(firstLine) {
        firstLine = false;
        var head = header.firstMatch(line);
        if(head != null) {
          try {
            validFromHours = head.namedGroup("validFromHours");
            validTillHours = head.namedGroup("validTillHours");
            validFromDate = head.namedGroup("validFromDate");
            validTillDate = head.namedGroup("validTillDate");
          }
          catch (e) {
            continue;
          }
        }
      }
      else {
        // BECMG/TEMPO/FM
        var grp = group.firstMatch(line);
        if(grp != null) {
          validFromHours = grp.namedGroup("validFromHours");
          validFromDate = grp.namedGroup("validFromDate");
        }
      }

      if(null == validFromHours  || null == validFromDate) {
        continue;
      }
      int? hours = int.tryParse(validFromHours);
      if(null == hours) {
        continue;
      }
      int? date = int.tryParse(validFromDate);
      if(null == date) {
        continue;
      }

      for (String token in tokens.reversed) { // run reversed as the first cloud layer is the lowest layer

        var vis = visibility.firstMatch(token);
        if (vis != null) {
          visibilityMeters = vis.namedGroup("vis");
          integer = vis.namedGroup("integer");
          fraction = vis.namedGroup("fraction");
          if (null != integer) {
            try {
              visSM = double.parse(integer);
            }
            catch (e) {
              debugPrint("Error parsing visibility: $e");
            }
          }
          else if (null != fraction) {
            visSM = 0.5; // less than 1
          }
          else if (null != visibilityMeters) {
            try {
              visSM = (double.parse(visibilityMeters) / 1000) * 0.621371;
            }
            catch (e) {
              debugPrint("Error parsing visibility: $e");
            }
          }
        }
        var cld = cloud.firstMatch(token);
        if (cld != null) {
          cover = cld.namedGroup("cover");
          height = cld.namedGroup("height");
          if (cover != null) {
            if (cover == "OVC" || cover == "BKN") {
              if(height != null) {
                try {
                  cloudFt = double.parse(height) * 100;
                }
                catch (e) {
                  debugPrint("Error parsing cloud height: $e" );
                }
              }
            }
            else {
              cloudFt = 12000; // VFR
            }
          }
        }
      }

      if(null == cloudFt || null == visSM) {
        continue;
      }

      // find flight category
      // VFR: > 3000 ft AND > 5SM
      // MVFR: >= 1000 ft AND / OR > 3 SM
      // IFR: >= 500 ft AND / OR >= 1 SM
      // LIFR < 500 ft AND / OR < 1 SM
      category = "VFR";
      if (cloudFt < 500 || visSM < 1) {
        category = "LIFR";
      }
      else if (cloudFt < 1000 || visSM < 1) {
        category = "IFR";
      }
      else if (cloudFt <= 3000 || visSM <= 3) {
        category = "MVFR";
      }

      DateTime now = DateTime.now();
      DateTime from = DateTime(now.year, now.month, date, hours);
      if(now.day > 26 && date < 3) { // if today is 27th, and date is 1, then it is 1st of next month
        from = DateTime(now.year, now.month + 1, date, hours);
      }

      times.add(from);
      colors.add(getColor(category));
    }

    if(null != validTillDate && null != validTillHours) {
      int? hours = int.tryParse(validTillHours);
      int? date = int.tryParse(validTillDate);
      if (null == hours || null == date) {
        return;
      }
      DateTime now = DateTime.now();
      DateTime from = DateTime(now.year, now.month, date, hours);
      if(now.day > date) {
        from = DateTime(now.year, now.month + 1, date, hours);
      }

      times.add(from);
      if(colors.isNotEmpty) {
        colors.add(colors.last);
      }
      else {
        colors.add(Colors.black);
      }
    }
  }

  Widget getIcon() {
    if(!parsed) {
      _parseCategories();
      parsed = true;
    }
    TimeSegmentPieChart chart = TimeSegmentPieChart(timeSegments: times, colors: colors);
    return SizedBox(width: 32, height: 32, child:chart);
  }

  @override
  String toString() {
    return "${super.toString()}$text";
  }
}

