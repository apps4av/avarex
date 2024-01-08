
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

  void _airwayAdjust(Waypoint waypoint) {

    waypoint.currentAirwayDestinationIndex = 0; // on change to airway, reset it
    waypoint.airwayDestinationsOnRoute = [];

    // adjust airways, nothing to do when airway is not in the middle of points
    int index = _waypoints.indexOf(waypoint);
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
      waypoint.airwayDestinationsOnRoute = points;
    }
  }

  // expand a list of waypoints with airways and return destinations in them
  // do not use it for current route as some on it may have passed and some may not
  List<Destination> _expand(List<Waypoint> waypoints) {
    List<Destination> destinationsExpanded = [];
    for(int index = 0; index < waypoints.length; index++) {
      Destination destination = waypoints[index].destination;
      // expand airways
      Destination.isAirway(destination.type) ? destinationsExpanded.addAll(waypoints[index].airwayDestinationsOnRoute) : destinationsExpanded.add(destination);
    }
    return destinationsExpanded;
  }

  // connect d0 to d1, modify d1, last destination of d0 goes as first of d1
  void _connect(List<Destination> d0, List<Destination> d1) {
    if (d1.isEmpty || d0.isEmpty) {
      return;
    }
    d1.insert(0, d0[d0.length - 1]);
  }

  List<LatLng> _makePathPoints(List<Destination> path) {
    GeoCalculations calc = GeoCalculations();
    List<LatLng> points = [];
    if(path.length < 2) {
      return [];
    }
    // geo segments
    for(int index = 0; index < path.length - 1; index++) {
      LatLng destination1 = path[index].coordinate;
      LatLng destination2 = path[index + 1].coordinate;
      List<LatLng> routeIntermediate = calc.findPoints(destination1, destination2);
      points.addAll(routeIntermediate);
    }
    return points;
  }
  
  void _update(bool changeInPath) {

    if(_waypoints.isNotEmpty) {
      _current ??= _waypoints[0];
    }

    if(_waypoints.length < 2) {
      _pointsPassed = [];
      _pointsCurrent = [];
      _pointsNext = [];
      return;
    }

    int cIndex = _current == null ? 0 : _waypoints.indexOf(_current!);
    List<Waypoint> waypointsPassed = cIndex == 0 ? [] : _waypoints.sublist(0, cIndex);
    Waypoint current = _waypoints[cIndex];
    List<Waypoint> waypointsNext = cIndex == (_waypoints.length - 1) ? [] : _waypoints.sublist(cIndex + 1, _waypoints.length);

    // passed
    List<Destination> destinationsPassed = _expand(waypointsPassed);
    // next
    List<Destination> destinationsNext = _expand(waypointsNext);
    // current
    List<Destination> destinationsCurrent = [];
    Destination destination = current.destination;
    if(Destination.isAirway(destination.type)) {
      destinationsPassed.addAll(current.getDestinationsPassed());
      destinationsNext.insertAll(0, current.getDestinationsNext());
      destinationsCurrent.addAll(current.getDestinationsCurrent());
    }
    else {
      destinationsCurrent.add(current.destination);
    }

    //make connections to paths
    _connect(destinationsPassed, destinationsCurrent); // current now has last passed
    _connect(destinationsCurrent, destinationsNext); // next has now current

    _pointsPassed = _makePathPoints(destinationsPassed);
    _pointsNext = _makePathPoints(destinationsNext);
    _pointsCurrent = _makePathPoints(destinationsCurrent);

    // On change in path, adjust airway
    if(changeInPath) {
      for (int index = 0; index < _waypoints.length; index++) {
        Destination destination = _waypoints[index].destination;
        if (Destination.isAirway(destination.type)) {
          _airwayAdjust(_waypoints[index]); // add all airways
        }
      }
    }
  }

  Waypoint removeWaypointAt(int index) {
    Waypoint waypoint = _waypoints.removeAt(index);
    _current = (waypoint == _current) ? null : _current; // clear next its removed
    _update(true);
    change.value++;
    return(waypoint);
  }

  void addDirectTo(Waypoint waypoint) {
    addWaypoint(waypoint);
    _current = _waypoints[_waypoints.indexOf(waypoint)]; // go here
    _update(true);
    change.value++;
  }

  void addWaypoint(Waypoint waypoint) {
    _waypoints.add(waypoint);
    _update(true);
    change.value++;
  }

  void moveWaypoint(int from, int to) {
    Waypoint waypoint = _waypoints.removeAt(from);
    _waypoints.insert(to, waypoint);
    _update(true);
    change.value++;
  }


  void setCurrentWaypointWithWaypoint(Waypoint waypoint) {
    _current = _waypoints[_waypoints.indexOf(waypoint)];
    _update(false);
    change.value++;
  }

  void setCurrentWaypoint(int index) {
    _current = _waypoints[index];
    _update(false);
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
    Destination? destination = getCurrentWaypoint()?.destination;
    if(destination == null) {
      return [];
    }
    LatLng destination1 = LatLng(position.latitude, position.longitude);
    LatLng destination2 = destination.coordinate;
    List<LatLng> points = GeoCalculations().findPoints(destination1, destination2);
    return points;
  }

  Waypoint? getCurrentWaypoint() {
    // if no route then destination
    return _current;
  }

  bool isCurrent(int index) {
    if(_current == null) {
      return false;
    }
    return _waypoints.indexOf(_current!) == index;
  }

  int get length => _waypoints.length;

}

class Waypoint {

  final Destination _destination;
  List<Destination> airwayDestinationsOnRoute = [];
  int currentAirwayDestinationIndex = 0;

  Waypoint(this._destination);

  Destination get destination {
    return airwayDestinationsOnRoute.isNotEmpty ?
      airwayDestinationsOnRoute[currentAirwayDestinationIndex] : _destination;
  }

  // return points passed, current, next
  List<Destination> getDestinationsNext() {
    if(airwayDestinationsOnRoute.isNotEmpty) {
      return currentAirwayDestinationIndex == (airwayDestinationsOnRoute.length - 1) ?
        [] : airwayDestinationsOnRoute.sublist(currentAirwayDestinationIndex + 1, airwayDestinationsOnRoute.length);
    }
    return [];
  }

  // return points passed, current, next
  List<Destination> getDestinationsPassed() {

    if(airwayDestinationsOnRoute.isNotEmpty) {
      return currentAirwayDestinationIndex == 0 ?
        [] : airwayDestinationsOnRoute.sublist(0, currentAirwayDestinationIndex);
    }
    return [];
  }

  // return points passed, current, next
  List<Destination> getDestinationsCurrent() {
    if(airwayDestinationsOnRoute.isNotEmpty) {
      return [airwayDestinationsOnRoute[currentAirwayDestinationIndex]];
    }
    return [];
  }

}