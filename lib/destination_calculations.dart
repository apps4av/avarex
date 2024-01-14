import 'package:avaremp/destination.dart';
import 'package:latlong2/latlong.dart';

import 'geo_calculations.dart';

class DestinationCalculations {

  final Destination _from;
  final Destination _to;
  final double _speed;
  final double _fuelBurn;

  double bearing = 0;
  double distance = 0;
  double time = 0;
  double fuel = 0;

  DestinationCalculations(this._from, this._to, this._speed, this._fuelBurn);

  // calculate all params like dist, bearing, time, altitude and fuel
  void calculateTo() {
    GeoCalculations calculations = GeoCalculations();
    List<LatLng> points = calculations.findPoints(_from.coordinate, _to.coordinate);
    // take initial bearing only
    bearing = calculations.calculateBearing(points[0], points[1]);
    distance = 0;
    for(int index = 0; index < points.length - 1; index++) {
      distance = distance + calculations.calculateDistance(points[index], points[index + 1]);
    }
    time = 3600 * distance / _speed; //sec
    fuel = _fuelBurn * time / 3600; // gallon per hour use
  }

  // sum 2 destination calculations and return a new object
  DestinationCalculations sum(DestinationCalculations other) {
    DestinationCalculations calc = DestinationCalculations(_from, _to, _speed, _fuelBurn);
    calc.distance = other.distance + distance;
    calc.time = other.time + time;
    calc.fuel = other.fuel + fuel;
    return calc;
  }

}