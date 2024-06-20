import 'package:avaremp/weather/time_segment_pie_chart.dart';
import 'package:avaremp/weather/weather.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'metar.dart';

class Taf extends Weather {
  String text;
  LatLng? coordinate;
  List<DateTime> times = [];
  List<Color> colors = [];

  Taf(super.station, super.expires, this.text) {
    parseCategory();
  }

  Map<String, Object?> toMap() {
    Map<String, Object?> map  = {
      "station": station,
      "utcMs": expires.millisecondsSinceEpoch,
      "raw": text,
    };
    return map;
  }

  factory Taf.fromMap(Map<String, dynamic> maps) {
    return Taf(
      maps['station'] as String,
      DateTime.fromMillisecondsSinceEpoch(maps['utcMs'] as int),
      maps['raw'] as String,
    );
  }

  void parseCategory() {

    final RegExp header = RegExp(
      r'^'
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
        r'^TEMPO|BECMG'
        r'\s*(?<validFromDate>0[1-9]|[12][0-9]|3[01])'
        r'(?<validFromHours>[0-1]\d|2[0-3])'
        r'/'
        r'(?<validToDate>[1-9]|[12][0-9]|3[01])'
        r'(?<validToHours>[0-1]\d|2[0-3])'
        r'.*$'
    );

    RegExp groupFrom = RegExp(
      r'^FM'
      r'(?<validFromDate>0[1-9]|[12][0-9]|3[01])'
      r'(?<validFromHours>[0-1]\d|2[0-3])'
      r'.*$');

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
      String? height;
      String? cover;
      String? validFromHours;
      String? validFromDate;
      double visSM = 6;
      double cloudFt = 12000;
      String category = "VFR";

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
        // FM
        var grp = groupFrom.firstMatch(line);
        if(grp != null) {
          validFromHours = grp.namedGroup("validFromHours");
          validFromDate = grp.namedGroup("validFromDate");
        }

        // BECMG
        grp = group.firstMatch(line);
        if(grp != null) {
          validFromHours = grp.namedGroup("validFromHours");
          validFromDate = grp.namedGroup("validFromDate");
        }
      }

      if(null == validFromHours || null == validTillHours || null == validFromDate || null == validTillDate) {
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
          integer = vis.namedGroup("integer");
          fraction = vis.namedGroup("fraction");
          if (null != integer) {
            try {
              visSM = double.parse(integer);
            }
            catch (e) {}
          }
          else if (null != fraction) {
            visSM = 0.5; // less than 1
          }
        }
        var cld = cloud.firstMatch(token);
        if (cld != null) {
          cover = cld.namedGroup("cover");
          height = cld.namedGroup("height");
          if (height != null && cover != null) {
            if (cover == "OVC" || cover == "BKN") {
              try {
                cloudFt = double.parse(height) * 100;
              }
              catch (e) {}
            }
          }
        }
      }

      // find flight category
      // VFR: > 3000 ft AND > 5SM
      // MVFR: >= 1000 ft AND / OR > 3 SM
      // IFR: >= 500 ft AND / OR >= 1 SM
      // LIFR < 500 ft AND / OR < 1 SM
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
      if(now.day > date) {
        from = DateTime(now.year, now.month + 1, date, hours);
      }

      times.add(from);
      colors.add(Metar.getColorStatic(category));
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
      colors.add(colors.last);
    }


  }

  Widget getIcon() {
    TimeSegmentPieChart chart = TimeSegmentPieChart(timeSegments: times, colors: colors);
    return SizedBox(width: 32, height: 32, child:chart);
  }

}

