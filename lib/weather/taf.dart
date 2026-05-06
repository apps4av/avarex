import 'package:avaremp/utils/app_log.dart';
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
      AppLog.logMessage("Error parsing TAF coordinate: $e");
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
        r'^((?<vis>\d{4}|////)'
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

    // Normalise the raw text so each FM / BECMG / TEMPO change group starts
    // on its own line (the cache layer does this for AWC TAFs but ADS-B/GDL90
    // TAFs reach us as a single line), and so "N N/N SM" mixed numerics get
    // joined into one token the visibility regex above can match.
    final String normalized = text
        .replaceAll(RegExp(r'\s+(?=FM\d)'), '\n')
        .replaceAll(RegExp(r'\s+(?=BECMG\b)'), '\n')
        .replaceAll(RegExp(r'\s+(?=TEMPO\b)'), '\n')
        .replaceAllMapped(
            RegExp(r'(?<![\d/])(\d{1,2})\s+(\d/\d)(SM|KM)\b'),
            (m) => '${m.group(1)}_${m.group(2)}${m.group(3)}');

    List<String> lines = normalized.split("\n");
    String? validTillHours;
    String? validTillDate;
    bool headerFound = false;
    // Carry visibility/ceiling forward to BECMG/TEMPO/FM groups that don't
    // restate them, since change groups in TAFs only mention what changes.
    double? lastVisSM;
    double? lastCloudFt;

    for (String line in lines) {
      List<String> tokens = line.split(" ");
      String? validFromHours;
      String? validFromDate;
      double? visSM;
      double? cloudFt;
      bool sawCloud = false;
      String category;

      if(!headerFound) {
        var head = header.firstMatch(line);
        if(head == null) {
          // Skip stand-alone "TAF" / blank lines until the real header is found.
          continue;
        }
        headerFound = true;
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

      // Find the lowest BKN/OVC/VV layer for the ceiling. Iterating in any
      // single direction with a plain "last write wins" pattern is wrong
      // because non-ceiling layers (SCT/FEW/CLR) below or above a real
      // ceiling can clobber it.
      double? minCeilingFt;
      for (String token in tokens) {
        var vis = visibility.firstMatch(token);
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
              catch (e) { AppLog.logMessage("Error parsing visibility integer: $e"); }
            }
            if (fraction != null) {
              final parts = fraction.split('/');
              if (parts.length == 2) {
                try {
                  final num = double.parse(parts[0]);
                  final den = double.parse(parts[1]);
                  if (den != 0) parsed += num / den;
                }
                catch (e) { AppLog.logMessage("Error parsing visibility fraction: $e"); }
              }
            }
            visSM = parsed;
          }
          else if (visibilityMeters != null && visibilityMeters != "////") {
            try {
              visSM = (double.parse(visibilityMeters) / 1000) * 0.621371;
            }
            catch (e) {
              AppLog.logMessage("Error parsing visibility meters: $e");
            }
          }
        }

        var cld = cloud.firstMatch(token);
        if (cld != null) {
          sawCloud = true;
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
                AppLog.logMessage("Error parsing cloud height: $e");
              }
            }
          }
        }
      }

      if (sawCloud) {
        cloudFt = minCeilingFt ?? 12000; // sky reported but no ceiling layer ⇒ unlimited
      }

      visSM ??= lastVisSM;
      cloudFt ??= lastCloudFt;

      if(null == cloudFt || null == visSM) {
        continue;
      }

      // FAA flight categories:
      //   VFR  - ceiling > 3000 ft AND vis > 5 SM
      //   MVFR - ceiling 1000-3000 ft AND/OR vis 3-5 SM
      //   IFR  - ceiling 500-999 ft AND/OR vis 1 to <3 SM
      //   LIFR - ceiling < 500 ft AND/OR vis < 1 SM
      if (cloudFt < 500 || visSM < 1) {
        category = "LIFR";
      }
      else if (cloudFt < 1000 || visSM < 3) {
        category = "IFR";
      }
      else if (cloudFt <= 3000 || visSM <= 5) {
        category = "MVFR";
      }
      else {
        category = "VFR";
      }

      lastVisSM = visSM;
      lastCloudFt = cloudFt;

      times.add(_utcAtDayHour(date, hours));
      colors.add(getColor(category));
    }

    if(null != validTillDate && null != validTillHours) {
      int? hours = int.tryParse(validTillHours);
      int? date = int.tryParse(validTillDate);
      if (null == hours || null == date) {
        return;
      }
      times.add(_utcAtDayHour(date, hours));
      if(colors.isNotEmpty) {
        colors.add(colors.last);
      }
      else {
        colors.add(Colors.black);
      }
    }
  }

  // Build a UTC DateTime for the given TAF day-of-month and hour, choosing
  // the calendar month that puts the date closest to "now" in UTC. Handles
  // both forward (e.g. today is the 31st, TAF says day 1) and backward
  // (today is the 1st, TAF says day 31) month rollovers.
  static DateTime _utcAtDayHour(int date, int hours) {
    final DateTime nowUtc = DateTime.now().toUtc();
    final int dayDiff = date - nowUtc.day;
    int monthOffset = 0;
    if (dayDiff < -10) {
      monthOffset = 1;  // forecast wraps into next month
    } else if (dayDiff > 20) {
      monthOffset = -1; // header was issued in the previous month
    }
    return DateTime.utc(nowUtc.year, nowUtc.month + monthOffset, date, hours);
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

