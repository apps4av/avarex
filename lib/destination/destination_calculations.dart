import 'dart:math';

import 'package:avaremp/destination/destination.dart';
import 'package:latlong2/latlong.dart';

import '../geo_calculations.dart';

class DestinationCalculations {

  final Destination _from;
  final Destination _to;
  final double _speed;
  final double _fuelBurn;
  final double? _ws;
  final double? _wd;
  final double altitude;
  String wind = "";

  double distance = 0;
  double course = 0;
  double trueCourse = 0;
  double windCorrectionAngle = 0;
  double magneticCourse = 0;
  double time = 0;
  double fuel = 0;
  double groundSpeed = 0;
  double variation = 0;

  DestinationCalculations(this._from, this._to, this._speed, this._fuelBurn, this._wd, this._ws, this.altitude);

  // calculate all params like dist, bearing, time, altitude and fuel
  void calculateTo() {

    GeoCalculations calculations = GeoCalculations();
    List<LatLng> points = calculations.findPoints(_from.coordinate, _to.coordinate);
    // take initial bearing only
    if(points.length < 2) {
      return;
    }
    trueCourse = calculations.calculateBearing(points[0], points[1]);
    distance = 0;
    for(int index = 0; index < points.length - 1; index++) {
      distance = distance + calculations.calculateDistance(points[index], points[index + 1]);
    }

    double variation1 = _to.geoVariation?? 0;
    double variation2 = _from.geoVariation?? 0;

    double ws = _ws?? 0;
    double wd = _wd?? 0;
    wind = "${wd.round()}@${ws.round()}";

    variation = (variation1 + variation2) / 2.0; // avg of two variation
    groundSpeed = sqrt(ws * ws + _speed * _speed - 2 * ws * _speed * cos((trueCourse - wd) * pi / 180.0));
    windCorrectionAngle = -GeoCalculations.toDegrees(atan2(ws * sin((trueCourse - wd) * pi / 180.0), _speed - ws * cos((trueCourse - wd) * pi / 180.0)));
    magneticCourse = GeoCalculations.getMagneticHeading(trueCourse, variation);
    course = (magneticCourse + windCorrectionAngle) % 360;
    time = 3600 * distance / groundSpeed; //sec
    fuel = _fuelBurn * time / 3600; // gallon per hour use
  }

  static const List<String> labels = ["FM", "TO", "AL", "TC", "VR", "MC", "WD", "CA", "MH", "DT", "GS", "TM", "FC"];
  static int columns = labels.length;
  List<String> getLog() {
    Duration d = Duration(seconds: time.round());
    List<String> log = [];
    log.add(_from.locationID);
    log.add(_to.locationID);
    log.add(altitude.round().toString());
    log.add(trueCourse.round().toString());
    log.add(variation.round().toString());
    log.add(magneticCourse.round().toString());
    log.add(wind);
    log.add(windCorrectionAngle.round().toString());
    log.add(course.round().toString());
    log.add(distance.round().toString());
    log.add(groundSpeed.round().toString());
    log.add("${d.inHours.toString().padLeft(1, "0")}:${(d.inMinutes % 60).toString().padLeft(2, "0")}");
    log.add(fuel.toStringAsFixed(1));
    return log;
  }

}
