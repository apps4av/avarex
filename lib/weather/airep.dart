import 'dart:convert';

import 'package:avaremp/weather/weather.dart';
import 'package:latlong2/latlong.dart';

class Airep extends Weather {
  String text;
  LatLng coordinates;

  Airep(super.station, super.expires, super.recieved, super.source, this.text, this.coordinates);

  Map<String, Object?> toMap() {
    Map<String, Object?> map  = {
      "station": station,
      "utcMs": expires.millisecondsSinceEpoch,
      "receivedMs": received.millisecondsSinceEpoch,
      "source": source,
      "raw": text,
      "coordinates": jsonEncode([coordinates.latitude, coordinates.longitude])
    };
    return map;
  }

  factory Airep.fromMap(Map<String, dynamic> maps) {

    dynamic coordinates = jsonDecode(maps['coordinates'] as String);

    return Airep(
      maps['station'] as String,
      DateTime.fromMillisecondsSinceEpoch(maps['utcMs'] as int),
      DateTime.fromMillisecondsSinceEpoch(maps['receivedMs'] as int),
      maps['source'] as String,
      maps['raw'] as String,
      LatLng(coordinates[0], coordinates[1])
    );
  }

  @override
  String toString() {
    return "${super.toString()}$text";
  }
}

