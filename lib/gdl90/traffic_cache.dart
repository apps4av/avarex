import 'dart:core';
import 'package:avaremp/gdl90/traffic_report_message.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../gps.dart';

class Traffic {

  final TrafficReportMessage message;

  Traffic(this.message);

  bool isOld() {
    // old if more than 1 min
    return DateTime.now().difference(message.time).inMinutes > 0;
  }

  Widget getIcon() {
    return Transform.rotate(angle: message.heading * pi / 180,
        child: Container(
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color: const Color.fromARGB(128, 255, 0, 0)),
          child:const Icon(Icons.arrow_upward_rounded, color: Colors.black,)));
  }

  LatLng getCoordinates() {
    return message.coordinates;
  }

  @override
  String toString() {
    return "${message.callSign}\n${message.altitude.toInt()} ft\n"
    "${(message.velocity * 1.94384).toInt()} knots\n"
    "${(message.verticalSpeed * 3.28).toInt()} fpm";
  }

}




class TrafficCache {
  static const int maxEntries = 20;
  final List<Traffic?> _traffic = List.filled(maxEntries + 1, null); // +1 is the empty slot where new traffic is added

  double findDistance(LatLng coordinate, double altitude) {
    // find 3d distance between current position and airplane
    // treat 1 mile of horizontal distance as 500 feet of vertical distance (C182 120kts, 1000 fpm)
    LatLng current = Gps.toLatLng(Storage().position);
    double horizontalDistance = GeoCalculations().calculateDistance(current, coordinate) * 500;
    double verticalDistance   = (Storage().position.altitude * 3.28084 - altitude).abs();
    double fac = horizontalDistance + verticalDistance;
    return fac;
  }

  void putTraffic(TrafficReportMessage message) {

    // filter own report
    if(message.icao == Storage().myIcao) {
      // do not add ourselves
      return;
    }

    for(Traffic? traffic in _traffic) {
      int index = _traffic.indexOf(traffic);
      if(traffic == null) {
        continue;
      }
      if(traffic.isOld()) {
        _traffic[index] = null;
        // purge old
        continue;
      }

      // update
      if(traffic.message.icao == message.icao) {
        // call sign not available. use last one
        if(message.callSign.isEmpty) {
          message.callSign = traffic.message.callSign;
        }
        final Traffic trafficNew = Traffic(message);
        _traffic[index] = trafficNew;
        return;
      }
    }

    // put it in the end
    final Traffic trafficNew = Traffic(message);
    _traffic[maxEntries] = trafficNew;

    // sort
    _traffic.sort(_trafficSort);

  }

  int _trafficSort(Traffic? left, Traffic? right) {
    if(null == left && null != right) {
      return 1;
    }
    if(null != left && null == right) {
      return -1;
    }
    if(null == left && null == right) {
      return 0;
    }
    if(null != left && null != right) {
      double l = findDistance(left.message.coordinates, left.message.altitude);
      double r = findDistance(right.message.coordinates, right.message.altitude);
      if(l > r) {
        return 1;
      }
      if(l < r) {
        return -1;
      }
    }
    return 0;
  }

  List<Traffic> getTraffic() {
    List<Traffic> ret = [];

    for(Traffic? check in _traffic) {
      if(null != check) {
        ret.add(check);
      }
    }
    return ret;
  }
}