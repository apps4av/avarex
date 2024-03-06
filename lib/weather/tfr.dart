import 'dart:convert';

import 'package:avaremp/weather/weather.dart';
import 'package:latlong2/latlong.dart';

class Tfr extends Weather {
  List<LatLng> coordinates;
  String upperAltitude;
  String lowerAltitude;
  int msEffective;
  int msExpires;

  Tfr(super.station, super.expires, this.coordinates, this.upperAltitude, this.lowerAltitude, this.msEffective, this.msExpires);

  Map<String, Object?> toMap() {

    List<List<double>> ll = [];
    for(LatLng c in coordinates) {
      ll.add([c.latitude, c.longitude]);
    }

    Map<String, Object?> map  = {
      "station": station,
      "utcMs": expires.millisecondsSinceEpoch,
      "coordinates": jsonEncode(ll),
      "upperAltitude": upperAltitude,
      "lowerAltitude": lowerAltitude,
      "msEffective": msEffective,
      "msExpires": msExpires
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
      ll,
      maps['upperAltitude'] as String,
      maps['lowerAltitude'] as String,
      maps['msEffective'] as int,
      maps['msExpires'] as int,
    );
  }

  @override
  String toString() {
    return
      "Top $upperAltitude\n"
      "Low $lowerAltitude\n"
      "${DateTime.fromMillisecondsSinceEpoch(msEffective).toString().replaceAll(".000", "")} to\n"
      "${DateTime.fromMillisecondsSinceEpoch(msExpires).toString().replaceAll(".000", "")}";
  }

  bool isInEffect() {
    int now = DateTime.now().millisecondsSinceEpoch;
    return (now >= msEffective && now <= msExpires);
  }


  bool isRelevant() {
    return DateTime.now().millisecondsSinceEpoch < msExpires;
  }

}

