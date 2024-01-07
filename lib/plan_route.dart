
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

  void _update() {

    if(_waypoints.isNotEmpty) {
      _next ??= _waypoints[0];
    }

    if(_waypoints.length < 2) {
      _points = [];
      return;
    }

    GeoCalculations calc = GeoCalculations();
    //2 at a time
    _points = [];
    for(int index = 0; index < _waypoints.length - 1; index++) {
      LatLng d1 = _waypoints[index].coordinate;
      LatLng d2 = _waypoints[index + 1].coordinate;
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

  void insertDirectTo(Destination waypoint) {
    _waypoints.insert(0, waypoint);
    _next = _waypoints[0]; // go here
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