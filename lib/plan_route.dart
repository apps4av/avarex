
import 'dart:convert';

import 'package:avaremp/airway.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/passage.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/waypoint.dart';
import 'package:avaremp/weather/winds_aloft.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:flutter/cupertino.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'destination.dart';
import 'destination_calculations.dart';
import 'gps.dart';

class PlanRoute {

  // all segments
  final List<Waypoint> _waypoints = [];
  List<LatLng> _pointsPassed = [];
  List<LatLng> _pointsCurrent = [];
  List<LatLng> _pointsNext = [];
  Waypoint? _current; // current one we are flying to
  String name;
  final change = ValueNotifier<int>(0);
  String altitude = "3000";
  Passage? _passage;

  DestinationCalculations? totalCalculations;

  int get length => _waypoints.length;
  bool get isNotEmpty => _waypoints.isNotEmpty;


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
      if(Destination.isAirway(destination.type)) {
        // skip empty airways
        if(waypoints[index].airwayDestinationsOnRoute.isEmpty) {
          continue;
        }
        destinationsExpanded.addAll(waypoints[index].airwayDestinationsOnRoute);
      }
      else {
        destinationsExpanded.add(destination);
      }
    }
    return destinationsExpanded;
  }

  // connect d0 to d1, modify d1, last destination of d0 goes as first of d1
  void _connect(List<Destination> d0, List<Destination> d1) {
    if (d0.isEmpty) {
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
      totalCalculations = null;
      change.value++;
      return;
    }

    // On change in path, adjust airway
    if(changeInPath) {
      for (int index = 0; index < _waypoints.length; index++) {
        Destination destination = _waypoints[index].destination;
        if (Destination.isAirway(destination.type)) {
          _airwayAdjust(_waypoints[index]); // add all airways
        }
      }
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

    // everything in plan needs to be calculated in plan
    List<Destination> allDestinations = [];
    allDestinations.addAll(destinationsPassed);
    allDestinations.addAll(destinationsCurrent);
    allDestinations.addAll(destinationsNext);

    // calculate plan
    for(int index = 0; index < allDestinations.length - 1; index++) {
      allDestinations[0].calculations = null;
      double? ws;
      double? wd;
      String? station = WindsCache.locateNearestStation(allDestinations[index].coordinate);
      WindsAloft? wa = Storage().winds.get(station) != null ? Storage().winds.get(station) as WindsAloft : null;
      (wd, ws) = WindsCache.getWindAtAltitude(double.parse(altitude), wa);

      DestinationCalculations calc;
      // calculate total from current position to active route
      if(current.destination == allDestinations[index + 1]) {
        calc = DestinationCalculations(
          Destination.fromLatLng(Gps.toLatLng(Storage().position)),
          allDestinations[index + 1],
          Storage().settings.getTas().toDouble(),
          Storage().settings.getFuelBurn().toDouble(), wd, ws);
        // calculate passage
        Passage? p = _passage;
        if(null == p) {
          p = Passage(allDestinations[index + 1].coordinate);
          _passage = p;
        }
        if(p.update(Gps.toLatLng(Storage().position))) {
          // passed
          advance();
          _passage = null;
        }
      }
      else {
        calc = DestinationCalculations(
            allDestinations[index], allDestinations[index + 1],
            Storage().settings.getTas().toDouble(),
            Storage().settings.getFuelBurn().toDouble(), wd, ws);
      }
      calc.calculateTo();
      allDestinations[index + 1].calculations = calc;
    }

    //make connections to paths
    _connect(destinationsPassed, destinationsCurrent); // current now has last passed
    _connect(destinationsCurrent, destinationsNext); // next has now current

    // do total calculations
    double speed = 0;
    double distance = 0;
    double time = 0;
    double fuel = 0;
    double total = 0;

    if(destinationsNext.isEmpty) {
      // last leg
      totalCalculations = allDestinations[allDestinations.length - 1].calculations;
    }
    // sum
    else {
      for (int index = 0; index < destinationsNext.length; index++) {
        if (destinationsNext[index].calculations != null) {
          total++;
          totalCalculations ??= destinationsNext[index].calculations;
          speed += destinationsNext[index].calculations!.groundSpeed;
          distance += destinationsNext[index].calculations!.distance;
          time += destinationsNext[index].calculations!.time;
          fuel += destinationsNext[index].calculations!.fuel;
        }
      }
      if(totalCalculations != null) {
        totalCalculations!.groundSpeed = speed / total;
        totalCalculations!.distance = distance;
        totalCalculations!.time = time;
        totalCalculations!.fuel = fuel;
        totalCalculations!.course = _current != null && _current!.destination.calculations != null ? _current!.destination.calculations!.course : 0;
      }
    }

    // make paths
    _pointsPassed = _makePathPoints(destinationsPassed);
    _pointsNext = _makePathPoints(destinationsNext);
    _pointsCurrent = _makePathPoints(destinationsCurrent);

    change.value++;
  }

  void advance() {
    if(_current != null) {
      if(Destination.isAirway(_current!.destination.type)) {
        if(_current!.currentAirwayDestinationIndex < _current!.airwayDestinationsOnRoute.length - 1) {
          // flying on airway and not done
          _current!.currentAirwayDestinationIndex++;
          update();
          return;
        }
      }
      int index = _waypoints.indexOf(_current!);
      index++;
      if (index < _waypoints.length) {
        _current = _waypoints[index];
      }
      if (index >= _waypoints.length) {
        _current = _waypoints[0]; // done, go back
      }
      update();
    }
  }

  void update() {
    _update(false);
  }

  Waypoint removeWaypointAt(int index) {
    Waypoint waypoint = _waypoints.removeAt(index);
    _current = (waypoint == _current) ? null : _current; // clear next its removed
    _update(true);
    return(waypoint);
  }

  void addDirectTo(Waypoint waypoint) {
    addWaypoint(waypoint);
    _current = _waypoints[_waypoints.indexOf(waypoint)]; // go here
    _update(true);
  }

  void addWaypoint(Waypoint waypoint) {
    _waypoints.add(waypoint);
    _update(true);
  }

  void moveWaypoint(int from, int to) {
    Waypoint waypoint = _waypoints.removeAt(from);
    _waypoints.insert(to, waypoint);
    _update(true);
  }

  void setCurrentWaypointWithWaypoint(Waypoint waypoint) {
    _current = _waypoints[_waypoints.indexOf(waypoint)];
    update();
  }

  void setCurrentWaypoint(int index) {
    _current = _waypoints[index];
    update();
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

  Waypoint? getLastWaypoint() {
    // if no route then destination
    if(_current != null) {
      int index = _waypoints.indexOf(_current!) - 1;
      if(index >= 0) {
        return _waypoints[index];
      }
    }
    return null;
  }

  bool isCurrent(int index) {
    if(_current == null) {
      return false;
    }
    return _waypoints.indexOf(_current!) == index;
  }

  // convert route to json
  Map<String, Object?> toMap(String name) {

    // put all destinations in json
    List<Map<String, Object?>> maps = _waypoints.map((e) => e.destination.toMap()).toList();
    String json = jsonEncode(maps);

    Map<String, Object?> jsonMap = {'name' : name, 'route' : json};

    return jsonMap;
  }

  // default constructor creates empty route
  PlanRoute(this.name);

  // copy a plan into this
  void copyFrom(PlanRoute other) {
    name = other.name;
    _current = null;
    _waypoints.removeRange(0, _waypoints.length);
    for(Waypoint w in other._waypoints) {
      addWaypoint(w);
    }
  }

  // convert json to Route
  static Future<PlanRoute> fromMap(Map<String, Object?> maps, bool reverse) async {
    PlanRoute route = PlanRoute(maps['name'] as String);
    String json = maps['route'] as String;
    List<dynamic> decoded = jsonDecode(json);
    List<Destination> destinations = decoded.map((e) => Destination.fromMap(e)).toList();

    if(reverse) {
      destinations = destinations.reversed.toList();
    }
    for (Destination d in destinations) {
      Destination expanded = await DestinationFactory.make(d);
      Waypoint w = Waypoint(expanded);
      route.addWaypoint(w);
    }
    return route;
  }

  @override
  String toString() {
    return _waypoints.map((e) => e.destination.locationID).toList().join("->");
  }
}
