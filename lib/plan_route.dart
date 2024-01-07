
import 'package:avaremp/airway.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:flutter/cupertino.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'destination.dart';

class PlanRoute {

  // all segments
  final List<Destination> _waypoints = [];
  List<LatLng> _points = [];
  Destination? _next;
  final change = ValueNotifier<int>(0);

  void _airwayAdjust(AirwayDestination d) {

    // adjust airways, nothing to do when airway is not in the middle of points
    int index = _waypoints.indexOf(d);
    // need a start and end
    d.adjustedPoints = [];
    if(index == 0 || index == _waypoints.length - 1) {
      return;
    }

    // replace the airway with the new airway with the right points
    List<Destination> points = Airway.find(_waypoints[index - 1], d, _waypoints[index + 1]);
    if(points.isNotEmpty) {
      d.adjustedPoints = points;
    }
  }

  void _update() {

    if(_waypoints.isNotEmpty) {
      _next ??= _waypoints[0];
    }

    if(_waypoints.length < 2) {
      _points = [];
      return;
    }

    // find path
    List<Destination> path = [];
    for(int index = 0; index < _waypoints.length; index++) {
      Destination d = _waypoints[index];
      if(d is AirwayDestination) {
        _airwayAdjust(d); // add all V ways
        path.addAll(d.adjustedPoints);
      }
      else {
        path.add(d);
      }

    }

    GeoCalculations calc = GeoCalculations();
    //2 at a time
    _points = [];
    for(int index = 0; index < path.length - 1; index++) {
      LatLng d1 = path[index].coordinate;
      LatLng d2 = path[index + 1].coordinate;
      List<LatLng> routeIntermediate = calc.findPoints(d1, d2);
      _points.addAll(routeIntermediate);
    }
  }

  Destination removeWaypointAt(int index) {
    Destination d = _waypoints.removeAt(index);
    _next = (d == _next) ? null : _next; // clear next its removed
    _update();
    change.value++;
    return(d);
  }

  void addDirectTo(Destination waypoint) {
    addWaypoint(waypoint);
    _next = _waypoints[_waypoints.indexOf(waypoint)]; // go here
    _update();
    change.value++;
  }

  void addWaypoint(Destination waypoint) {
    _waypoints.add(waypoint);
    _update();
    change.value++;
  }

  void moveWaypoint(int from, int to) {
    Destination d = _waypoints.removeAt(from);
    _waypoints.insert(to, d);
    _update();
    change.value++;
  }

  void setNext(int index) {
    _next = _waypoints[index];
    _update();
    change.value++;
  }

  Destination? get next => _next;

  Destination getWaypointAt(int index) {
    return _waypoints[index];
  }

  List<LatLng> getPath() {
    return _points;
  }

  List<LatLng> getPathFromLocation(Position position) {
    Destination? d = getNextWaypoint();
    if(d == null) {
      return [];
    }
    LatLng d1 = LatLng(position.latitude, position.longitude);
    LatLng d2 = d.coordinate;
    List<LatLng> points = GeoCalculations().findPoints(d1, d2);
    return points;
  }

  Destination? getNextWaypoint() {
    // if no route then destination
    return _next;
  }

  List<Destination> get waypoints => _waypoints;

}
