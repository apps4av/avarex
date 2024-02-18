import 'dart:convert';

import 'package:avaremp/weather.dart';
import 'package:latlong2/latlong.dart';

class Tfr extends Weather {
  String info;
  List<LatLng> coordinates;

  Tfr(super.station, super.expires, this.info, this.coordinates);

  Map<String, Object?> toMap() {

    List<List<double>> ll = [];
    for(LatLng c in coordinates) {
      ll.add([c.latitude, c.longitude]);
    }


    Map<String, Object?> map  = {
      "station": station,
      "utcMs": expires.millisecondsSinceEpoch,
      "info": info,
      "coordinates": jsonEncode(ll)
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
      maps['info'],
      ll
    );
  }

}

