import 'dart:core';
import 'package:avaremp/gdl90/traffic_report_message.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../gps.dart';

class Traffic {

  final TrafficReportMessage message;
  final Widget _paint;

  Traffic(this.message) : _paint = CustomPaint(painter: _TrafficPainter(message));

  bool isOld() {
    // old if more than 1 min
    return DateTime.now().difference(message.time).inMinutes > 0;
  }

  Widget getIcon() {
    return _paint;
  }

  LatLng getCoordinates() {
    return message.coordinates;
  }
}


class _TrafficPainter extends CustomPainter {
  final TrafficReportMessage _message;

  _TrafficPainter(this._message);

  final _paintLine = Paint()
    ..strokeWidth = 3
    ..color = Colors.black
    ..style = PaintingStyle.stroke;

  final _paintBack = Paint()
    ..color = const Color.fromARGB(64, 255, 255, 255)
    ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    // assume size 64x64
    canvas.save();
    canvas.rotate(_message.heading * pi / 180);
    canvas.drawCircle(const Offset(32, 32), 32, _paintBack);
    canvas.drawCircle(const Offset(32, 32), 8, _paintLine);
    canvas.drawLine(const Offset(32, 24), const Offset(32, 8), _paintLine);
    canvas.drawLine(const Offset(28, 32), const Offset(36, 32), _paintLine);
    if(_message.verticalSpeed > 0) {
      canvas.drawLine(const Offset(32, 28), const Offset(32, 36), _paintLine);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
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

    // XXX filter own report

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