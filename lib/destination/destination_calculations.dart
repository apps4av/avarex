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

  double distance = 0;
  double course = 0;
  double time = 0;
  double fuel = 0;
  double groundSpeed = 0;

  DestinationCalculations(this._from, this._to, this._speed, this._fuelBurn, this._wd, this._ws);

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

    double variation1 = _to.geoVariation?? 0;
    double variation2 = _from.geoVariation?? 0;

    double ws = _ws?? 0;
    double wd = _wd?? 0;

    double variation = (variation1 + variation2) / 2.0; // avg of two variation
    groundSpeed = sqrt(ws * ws + _speed * _speed - 2 * ws * _speed * cos((heading - wd) * pi / 180.0));
    double windCorrectionAngle = -GeoCalculations.toDegrees(atan2(ws * sin((heading - wd) * pi / 180.0), _speed - ws * cos((heading - wd) * pi / 180.0)));
    course = GeoCalculations.getMagneticHeading(heading + windCorrectionAngle, variation);

    time = 3600 * distance / groundSpeed; //sec
    fuel = _fuelBurn * time / 3600; // gallon per hour use
  }

}