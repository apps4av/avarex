import 'dart:convert';

import 'package:avaremp/weather/weather.dart';
import 'package:latlong2/latlong.dart';

class Tfr extends Weather {
  final List<LatLng> coordinates;
  final String upperAltitude;
  final String lowerAltitude;
  final int msEffective;
  final int msExpires;
  final int labelCoordinate;

  Tfr(super.station, super.expires, super.recieved, super.source, this.coordinates, this.upperAltitude, this.lowerAltitude, this.msEffective, this.msExpires, this.labelCoordinate);

  @override
  String toString() {
    return
      "${super.toString()}Top $upperAltitude\nLow $lowerAltitude\n${DateTime.fromMillisecondsSinceEpoch(msEffective).toString().replaceAll(":00.000", "Z")} to\n${DateTime.fromMillisecondsSinceEpoch(msExpires).toString().replaceAll(":00.000", "Z")}";
  }

  bool isInEffect() {
    int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    return (now >= msEffective && now <= msExpires);
  }

  /// Ceiling over floor, e.g. "4999 AGL/SFC" or "FL180/9000".
  String altitudeLabel() {
    return "$upperAltitude/$lowerAltitude";
  }

  /// For a TFR that has not started yet: how long until it does, e.g.
  /// "in 45 min", "in 3.5 hrs", "in 27 hrs", "in 4 days". Empty once it is
  /// in effect or expired.
  String activeInLabel([DateTime? now]) {
    final int nowMs = (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
    return formatActiveIn(msEffective - nowMs);
  }

  static String formatActiveIn(int millisUntilEffective) {
    if (millisUntilEffective <= 0) {
      return "";
    }
    final double hours = millisUntilEffective / Duration.millisecondsPerHour;
    if (hours < 1) {
      final int minutes = (millisUntilEffective / Duration.millisecondsPerMinute).ceil();
      return "in $minutes min";
    }
    if (hours < 10) {
      return "in ${hours.toStringAsFixed(1)} hrs";
    }
    if (hours < 96) {
      return "in ${hours.round()} hrs";
    }
    return "in ${(hours / 24).round()} days";
  }

  /// Turns the FAA XML vertical limit triple into sectional-style text.
  ///
  /// [uom] is FT or FL; [code] is HEI (height above ground, i.e. AGL) or
  /// ALT (altitude, i.e. MSL). MSL values print bare, AGL values are
  /// suffixed, zero is SFC, flight levels are FLxxx, and the FAA's
  /// "FL 9999" placeholder for no ceiling is UNL.
  static String formatAltitude(String value, String uom, String code) {
    final int? feet = int.tryParse(value.trim());
    if (feet == null) {
      return value;
    }
    if (uom.trim().toUpperCase() == "FL") {
      return feet >= 999 ? "UNL" : "FL$feet";
    }
    if (feet == 0) {
      return "SFC";
    }
    if (code.trim().toUpperCase() == "HEI") {
      return "$feet AGL";
    }
    return "$feet";
  }


  bool isRelevant() {
    return DateTime.now().toUtc().millisecondsSinceEpoch < msExpires;
  }

  int getLabelCoordinate() {
    return labelCoordinate;
  }


  Map<String, Object?> toMap() {

    List<List<double>> ll = [];
    for(LatLng c in coordinates) {
      ll.add([c.latitude, c.longitude]);
    }

    Map<String, Object?> map  = {
      "station": station,
      "utcMs": expires.millisecondsSinceEpoch,
      "receivedMs": received.millisecondsSinceEpoch,
      "source": source,
      "coordinates": jsonEncode(ll),
      "upperAltitude": upperAltitude,
      "lowerAltitude": lowerAltitude,
      "msEffective": msEffective,
      "msExpires": msExpires,
      "labelCoordinate": labelCoordinate
    };
    return map;
  }

  factory Tfr.fromMap(Map<String, dynamic> maps) {

    List<LatLng> ll = [];
    List<dynamic> coordinates = jsonDecode(maps['coordinates'] as String);
    for(dynamic coordinate in coordinates) {
      ll.add(LatLng(coordinate[0], coordinate[1]));
    }

    return Tfr(
      maps['station'] as String,
      DateTime.fromMillisecondsSinceEpoch(maps['utcMs'] as int),
      DateTime.fromMillisecondsSinceEpoch(maps['receivedMs'] as int),
      maps['source'] as String,
      ll,
      maps['upperAltitude'] as String,
      maps['lowerAltitude'] as String,
      maps['msEffective'] as int,
      maps['msExpires'] as int,
      maps['labelCoordinate'] as int
    );
  }

}

