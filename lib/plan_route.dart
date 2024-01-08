
import 'package:avaremp/airway.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:flutter/cupertino.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'destination.dart';

class PlanRoute {

  // all segments
  final List<Waypoint> _waypoints = [];
  List<LatLng> _pointsPassed = [];
  List<LatLng> _pointsCurrent = [];
  List<LatLng> _pointsNext = [];
  Waypoint? _current;
  final change = ValueNotifier<int>(0);

  void _airwayAdjust(Waypoint d) {

    d.adjustedPoints = [];

    // adjust airways, nothing to do when airway is not in the middle of points
    int index = _waypoints.indexOf(d);
    // need a start and end
    if(index == 0 || index == _waypoints.length - 1) {
      return;
    }

    // replace the airway with the new airway with the right points
    List<Destination> points = Airway.find(
        _waypoints[index - 1].destination,
        _waypoints[index].destination as AirwayDestination,
        _waypoints[index + 1].destination);
    if(points.isNotEmpty) {
      d.adjustedPoints = points;
    }
  }

  void _update() {

    if(_waypoints.isNotEmpty) {
      _current ??= _waypoints[0];
    }

    if(_waypoints.length < 2) {
      _pointsPassed = [];
      _pointsCurrent = [];
      _pointsNext = [];
      return;
    }

    // find path
    List<Destination> path = [];
    List<int> status = [];
    int cIndex = _current == null ? 0 : _waypoints.indexOf(_current!);
    for(int index = 0; index < _waypoints.length; index++) {
      Destination d = _waypoints[index].destination;
      if(Destination.isAirway(d.type)) {
        _airwayAdjust(_waypoints[index]); // add all airways
        path.addAll(_waypoints[index].adjustedPoints);
        index == cIndex ? status.addAll(_waypoints[index].adjustedPoints.map((e) => 0)) : {};
        index > cIndex ? status.addAll(_waypoints[index].adjustedPoints.map((e) => 1)) : {};
        index < cIndex ? status.addAll(_waypoints[index].adjustedPoints.map((e) => -1)) : {};
      }
      else {
        path.add(d);
        index == cIndex ? status.add(0) : {};
        index > cIndex ? status.add(1) : {};
        index < cIndex ? status.add(-1) : {};
      }
    }

    GeoCalculations calc = GeoCalculations();
    //2 at a time
    _pointsPassed = [];
    _pointsCurrent = [];
    _pointsNext = [];
    for(int index = 0; index < path.length - 1; index++) {
      LatLng d1 = path[index].coordinate;
      LatLng d2 = path[index + 1].coordinate;
      List<LatLng> routeIntermediate = calc.findPoints(d1, d2);
      (status[index] == 0) ? _pointsCurrent.addAll(routeIntermediate) : {};
      (status[index] == 1) ? _pointsNext.addAll(routeIntermediate) : {};
      (status[index] == -1) ? _pointsPassed.addAll(routeIntermediate) : {};
    }
  }

  Waypoint removeWaypointAt(int index) {
    Waypoint d = _waypoints.removeAt(index);
    _current = (d == _current) ? null : _current; // clear next its removed
    _update();
    change.value++;
    return(d);
  }

  void addDirectTo(Waypoint waypoint) {
    addWaypoint(waypoint);
    _current = _waypoints[_waypoints.indexOf(waypoint)]; // go here
    _update();
    change.value++;
  }

  void addWaypoint(Waypoint waypoint) {
    _waypoints.add(waypoint);
    _update();
    change.value++;
  }

  void moveWaypoint(int from, int to) {
    Waypoint d = _waypoints.removeAt(from);
    _waypoints.insert(to, d);
    _update();
    change.value++;
  }


  void setNextWithWaypoint(Waypoint waypoint) {
    _current = _waypoints[_waypoints.indexOf(waypoint)];
    _update();
    change.value++;
  }

  void setNext(int index) {
    _current = _waypoints[index];
    _update();
    change.value++;
  }

  Waypoint getWaypointAt(int index) {
    return _waypoints[index];
  }

  List<LatLng> getPathPassed() {
    return _pointsPassed;
  }

  List<LatLng> getPathCurrent() {
    return _pointsCurrent;
  }

  List<LatLng> getPathNext() {
    return _pointsNext;
  }

  List<LatLng> getPathFromLocation(Position position) {
    Destination? d = getCurrentWaypoint()?.destination;
    if(d == null) {
      return [];
    }
    LatLng d1 = LatLng(position.latitude, position.longitude);
    LatLng d2 = d.coordinate;
    List<LatLng> points = GeoCalculations().findPoints(d1, d2);
    return points;
  }

  Waypoint? getCurrentWaypoint() {
    // if no route then destination
    return _current;
  }

  bool isNext(int index) {
    if(_current == null) {
      return false;
    }
    return _waypoints.indexOf(_current!) == index;
  }

  int get length => _waypoints.length;

}


class Waypoint {

  final Destination _destination;
  List<Destination> adjustedPoints = [];
  int next = 0;

  Waypoint(this._destination);

  Destination get destination {
    return adjustedPoints.isNotEmpty ? adjustedPoints[next] : _destination;
  }

}