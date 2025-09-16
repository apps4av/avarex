import 'package:avaremp/nmea/nmea_message.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class RTMMessage extends NmeaMessage {
  RTMMessage(super.type);

  int icao = 0;
  LatLng coordinate = const LatLng(0, 0);
  int altitude = -100;
  int speed = 0;
  int track = 0;

  @override
  void parse(String data) {

    List<String> tokens = data.split(",");

    if (tokens.length < 10) {
      return;
    }

    double tmp;
    double tmp1;
    try {
      
      icao = int.parse(tokens[2]);
      
      tmp = double.parse(tokens[3]);
      tmp1 = (tmp.toInt() ~/ 100).toDouble();
      double lat = (tmp - (tmp1 * 100.0)) / 60 + tmp1;
      if (tokens[4] == "S") {
        lat = -lat;
      }

      tmp = double.parse(tokens[5]);
      tmp1 = (tmp.toInt() ~/ 100).toDouble();
      double lon = (tmp - (tmp1 * 100.0)) / 60 + tmp1;
      if (tokens[6] == "W") {
        lon = -lon;
      }

      coordinate = LatLng(lat, lon);

      altitude = double.parse(tokens[7]).round();
      track = double.parse(tokens[8]).round();
      speed = (double.parse(tokens[9]) * Storage().units.toMps).round();

    }
    catch (e) {
      debugPrint("RTMMessage: invalid data $data");
    }

  }

}