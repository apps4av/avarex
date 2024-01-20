import 'dart:math';

import 'package:avaremp/destination.dart';
import 'package:geomag/geomag.dart';
import 'package:latlong2/latlong.dart';

import 'geo_calculations.dart';

class DestinationCalculations {

  final Destination _from;
  final Destination _to;
  final double _speed;
  final double _fuelBurn;
  final double _ws;
  final double _wd;

  double distance = 0;
  double course = 0;
  double time = 0;
  double fuel = 0;
  double groundSpeed = 0;

  DestinationCalculations(this._from, this._to, this._speed, this._fuelBurn, this._ws, this._wd);

  // calculate all params like dist, bearing, time, altitude and fuel
  void calculateTo() {

    GeoCalculations calculations = GeoCalculations();
    List<LatLng> points = calculations.findPoints(_from.coordinate, _to.coordinate);
    // take initial bearing only
    if(points.length < 2) {
      return;
    }
    double heading = calculations.calculateBearing(points[0], points[1]);
    distance = 0;
    for(int index = 0; index < points.length - 1; index++) {
      distance = distance + calculations.calculateDistance(points[index], points[index + 1]);
    }

    GeoMag geoMag = GeoMag();
    double variation1 = geoMag.calculate(_to.coordinate.latitude, _to.coordinate.longitude).dec;
    double variation2 = geoMag.calculate(_from.coordinate.latitude, _from.coordinate.longitude).dec;

    double variation = (variation1 + variation2) / 2.0; // avg of two variation
    groundSpeed = sqrt(_ws * _ws + _speed * _speed - 2 * _ws * _speed * cos((heading - _wd) * pi / 180.0));
    double windCorrectionAngle = -GeoCalculations.toDegrees(atan2(_ws * sin((heading - _wd) * pi / 180.0), _speed - _ws * cos((heading - _wd) * pi / 180.0)));
    course = (heading + windCorrectionAngle + variation + 360) % 360;

    time = 3600 * distance / groundSpeed; //sec
    fuel = _fuelBurn * time / 3600; // gallon per hour use
  }

  // sum 2 destination calculations and return a new object
  DestinationCalculations sum(DestinationCalculations other) {
    DestinationCalculations calc = DestinationCalculations(_from, _to, _speed, _fuelBurn, _ws, _wd);
    calc.distance = other.distance + distance;
    calc.time = other.time + time;
    calc.fuel = other.fuel + fuel;
    return calc;
  }

}