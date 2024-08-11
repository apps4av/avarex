
import 'dart:convert';

import 'package:avaremp/airway.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/faa_dates.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/passage.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/waypoint.dart';
import 'package:avaremp/weather/winds_aloft.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:flutter/cupertino.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';
import 'package:http/http.dart' as http;

import 'destination.dart';
import 'destination_calculations.dart';
import 'gps.dart';

class PlanRoute {

  // all segments
  final List<Waypoint> _waypoints = [];
  List<LatLng> _pointsPassed = [];
  List<LatLng> _pointsCurrent = [];
  List<LatLng> _pointsNext = [];
  List<LatLng> _pointsNextHighResolution = [];
  Waypoint? _current; // current one we are flying to
  String name;
  final change = ValueNotifier<int>(0);
  String altitude = "3000";
  Passage? _passage;
  List<Destination> _allDestinations = [];

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

  List<LatLng> _makePathPoints(List<Destination> path, {bool fine = false}) {
    GeoCalculations calc = GeoCalculations();
    List<LatLng> points = [];
    if(path.length < 2) {
      return [];
    }
    // geo segments
    for(int index = 0; index < path.length - 1; index++) {
      LatLng destination1 = path[index].coordinate;
      LatLng destination2 = path[index + 1].coordinate;
      List<LatLng> routeIntermediate;
      // 1 mile segments if fine points
      routeIntermediate = fine ? calc.findPoints(destination1, destination2, 1) : calc.findPoints(destination1, destination2);
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
      _pointsNextHighResolution = [];
      _pointsNext = [];
      _allDestinations = [];
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
    _allDestinations = [];
    _allDestinations.addAll(destinationsPassed);
    _allDestinations.addAll(destinationsCurrent);
    _allDestinations.addAll(destinationsNext);

    // calculate plan
    for(int index = 0; index < _allDestinations.length - 1; index++) {
      _allDestinations[0].calculations = null;
      double? ws;
      double? wd;
      String? station = WindsCache.locateNearestStation(_allDestinations[index].coordinate);
      WindsAloft? wa = Storage().winds.get(station) != null ? Storage().winds.get(station) as WindsAloft : null;
      (wd, ws) = WindsCache.getWindAtAltitude(double.parse(altitude), wa);

      DestinationCalculations calc;
      // calculate total from current position to active route
      if(current.destination == _allDestinations[index + 1]) {
        calc = DestinationCalculations(
          Destination.fromLatLng(Gps.toLatLng(Storage().position)),
          _allDestinations[index + 1],
          Storage().settings.getTas().toDouble(),
          Storage().settings.getFuelBurn().toDouble(), wd, ws);
      }
      else {
        calc = DestinationCalculations(
            _allDestinations[index], _allDestinations[index + 1],
            Storage().settings.getTas().toDouble(),
            Storage().settings.getFuelBurn().toDouble(), wd, ws);
      }
      calc.calculateTo();
      _allDestinations[index + 1].calculations = calc;
    }

    // calculate passage
    Passage? p = _passage;
    if(null == p && _current != null) {
      p = Passage(_current!.destination.coordinate);
      _passage = p;
    }
    if(null != p) {
      if (p.update(Gps.toLatLng(Storage().position))) {
        // passed
        advance();
        _passage = null;
      }
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
      totalCalculations = _allDestinations[_allDestinations.length - 1].calculations;
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
        totalCalculations!.groundSpeed = total == 0 ? speed : speed / total; // div by 0
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
    _pointsNextHighResolution = _makePathPoints(destinationsNext, fine: true);

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
        _setCurrent(_waypoints[index]);
      }
      if (index >= _waypoints.length) {
        _setCurrent(_waypoints[0]); // done, go back
      }
      update();
    }
  }

  void update() {
    _update(false);
  }

  Waypoint removeWaypointAt(int index) {
    Waypoint waypoint = _waypoints.removeAt(index);
    _setCurrent((waypoint == _current) ? null : _current); // clear next its removed
    _update(true);
    return(waypoint);
  }

  void addDirectTo(Waypoint waypoint) {
    Storage().realmHelper.addRecent(waypoint.destination);
    addWaypoint(waypoint);
    _setCurrent(_waypoints[_waypoints.indexOf(waypoint)]); // go here
    _update(true);
  }

  void addWaypoint(Waypoint waypoint) {
    Storage().realmHelper.addRecent(waypoint.destination);
    _waypoints.add(waypoint);
    _update(true);
  }

  void moveWaypoint(int from, int to) {
    Waypoint waypoint = _waypoints.removeAt(from);
    _waypoints.insert(to, waypoint);
    _update(true);
  }

  void setCurrentWaypointWithWaypoint(Waypoint waypoint) {
    _setCurrent(_waypoints[_waypoints.indexOf(waypoint)]);
    update();
  }

  void setCurrentWaypoint(int index) {
    if(_waypoints.isNotEmpty) {
      _setCurrent(_waypoints[index]);
    }
    update();
  }

  void setCurrentWaypointFromDestinationIndex(int index) {
    if(_allDestinations.length > index) {
      Destination d = _allDestinations[index];
      setCurrentWaypointFromDestination(d);
    }
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

  List<LatLng> getPathNextHighResolution() {
    return _pointsNextHighResolution;
  }

  List<Destination> getAllDestinations() {
    return _allDestinations;
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

  // set waypoint based on destination object
  void setCurrentWaypointFromDestination(Destination d) {
    for(Waypoint w in _waypoints) {
      if(Destination.isAirway(w.destination.type)) {
        int index = w.airwayDestinationsOnRoute.indexOf(d);
        if(index >= 0) {
          _setCurrent(w);
          w.currentAirwayDestinationIndex = index;
          return;
        }
      }
      else {
        if (w.destination == d) {
          _setCurrent(w);
          return;
        }
      }
    }
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
  String toJson(String name) {

    // put all destinations in json
    List<Map<String, Object?>> maps = _waypoints.map((e) => e.destination.toMap()).toList();
    String json = jsonEncode(maps);

    return json;
  }

  // default constructor creates empty route
  PlanRoute(this.name);

  // copy a plan into this
  void copyFrom(PlanRoute other) {
    name = other.name;
    _setCurrent(null);
    _waypoints.removeRange(0, _waypoints.length);
    for(Waypoint w in other._waypoints) {
      addWaypoint(w);
    }
  }

  // convert json to Route
  static Future<PlanRoute> fromJson(String json, String name, bool reverse) async {
    PlanRoute route = PlanRoute(name);
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

  // convert json to Route
  static Future<PlanRoute> fromLine(String name, String line) async {
    PlanRoute route = PlanRoute(name);
    List<String> split = line.split(" ");

    for (String s in split) {
      List<Destination> destinations = await MainDatabaseHelper.db.findDestinations(s);
      if(destinations.isEmpty) {
        continue;
      }
      Destination expanded = await DestinationFactory.make(destinations[0]);
      Waypoint w = Waypoint(expanded);
      route.addWaypoint(w);
    }
    return route;
  }

  // convert json to Route
  static Future<PlanRoute> fromPreferred(String name, String line, String minAltitude, String maxAltitude) async {
    PlanRoute route = PlanRoute(name);
    List<String> split = line.split(" ");

    if(split.length < 2) {
      // source and dest must be present
      return route;
    }

    String? cookie;

    final responseHttp = await http.post(Uri.parse("https://rfinder.asalink.net/login.php?cmd=login&uid=apps4av&pwd=apps4av"));
    if (responseHttp.statusCode == 200) {
      try {
        cookie = responseHttp.headers['set-cookie'];
      }
      catch(e) {}
    }

    Map<String, String> params = {};
    params['id1'] = split[0];
    params['id2'] = split[1];
    params['nats'] = 'R';
    params['rnav'] = 'Y';
    params['dbid'] = FaaDates.getCurrentCycle();
    params['easet'] = 'Y';
    params['lvl'] = 'L'; // low is fine for now
    params['minalt'] = minAltitude;
    params['maxalt'] = maxAltitude;

    Map<String, String> headers = {};
    headers['Cookie'] = cookie ?? "";
    final response = await http.post(Uri.parse("https://rfinder.asalink.net/autorte_run.php"), body: params, headers: headers);
    if (response.statusCode == 200) {
      /* parse the html
        https://rfinder.asalink.net/login.php?cmd=login&uid=apps4av&pwd=apps4av
        Name/Remarks
        KBOS             0      0   N42&deg;21'46.60" W071&deg;00'23.00" GENERAL EDWARD LAWRENCE LOGAN
        WHYBE          256     19   N42&deg;15'13.82" W071&deg;24'59.53" WHYBE
        BOSOX          257     10   N42&deg;12'06.78" W071&deg;37'39.63" BOSOX
        GRIPE          258     13   N42&deg;08'08.87" W071&deg;54'32.46" GRIPE
        GRAYM          254      6   N42&deg;06'04.27" W072&deg;01'53.49" GRAYM
        DVANY          225     19   N41&deg;51'44.56" W072&deg;18'11.24" DVANY
        HFD     114.9  224     17   N41&deg;38'27.97" W072&deg;32'50.70" HARTFORD
        YALER          250     18   N41&deg;30'56.61" W072&deg;54'39.09" YALER
        SORRY          250      5   N41&deg;28'43.09" W073&deg;01'02.67" SORRY
        MERIT          228      8   N41&deg;22'55.02" W073&deg;08'14.74" MERIT
        TRUDE          228      4   N41&deg;20'01.96" W073&deg;11'48.73" TRUDE
        ANNEI          228      4   N41&deg;17'09.83" W073&deg;15'21.23" ANNEI
        VAGUS          227     10   N41&deg;09'49.86" W073&deg;24'22.27" VAGUS
        OUTTE          227      7   N41&deg;04'41.47" W073&deg;30'39.77" OUTTE
        KHPN           270      9   N41&deg;04'01.03" W073&deg;42'27.23" WESTCHESTER COUNTY
     */
      String data = response.body;
      try {
        LineSplitter ls = const LineSplitter();
        List<String> lines = ls.convert(data);

        // find lon lat in table of routes
        RegExp exp = RegExp(r'''N(?<degLat>[0-9]*)&deg;(?<minLat>[0-9]*)'(?<secLat>[0-9]*\.[0-9]*)"\s*W(?<degLon>[0-9]*)&deg;(?<minLon>[0-9]*)'(?<secLon>[0-9]*\.[0-9]*)"''');

        for(String line in lines) {
          RegExpMatch? match = exp.firstMatch(line);
          if(match != null) {
            double degLat = double.parse(match.namedGroup("degLat")!);
            double degLon = double.parse(match.namedGroup("degLon")!);
            double minLat = double.parse(match.namedGroup("minLat")!);
            double minLon = double.parse(match.namedGroup("minLon")!);
            double secLat = double.parse(match.namedGroup("secLat")!);
            double secLon = double.parse(match.namedGroup("secLon")!);

            double latitude = degLat + minLat / 60 + secLat / 3600;
            double longitude = degLon + minLon / 60 + secLon / 3600;

            LatLng ll = LatLng(latitude, -longitude);
            Destination d = await MainDatabaseHelper.db.findDestinationByCoordinates(ll);
            Waypoint w = Waypoint(d);
            route.addWaypoint(w);
          }
        }
      }

      catch (e) {}
    }

    return route;
  }

  bool isOnPath(LatLng point) {
    List<LatLng> path = getPathNext() + getPathCurrent() + getPathPassed();
    // given line with equation ax + by + c = 0, distance from point (x0, y0) is abs(ax0 + by0 + c) / sqrt(a^2 + b^2)
    for(int index = 0; index < path.length - 1; index++) {
      LatLng p1 = path[index];
      LatLng p2 = path[index + 1];
      double a = p2.latitude - p1.latitude;
      double b = p1.longitude - p2.longitude;
      double c = p1.latitude * (p2.longitude - p1.longitude) - p1.longitude * (p2.latitude - p1.latitude);
      if(a == 0 && b == 0) {
        continue;
      }
      double dist = ((a * point.longitude + b * point.latitude + c) / sqrt(a * a + b * b)).abs();
      if(dist < 0.01) {
        // on path or close enough
        return true;
      }
    }
    return false;
  }

  @override
  String toString() {
    return _waypoints.map((e) => e.destination.locationID).toList().join(" ");
  }

  double _quickDistance(LatLng ll0, LatLng ll1) {
    // there are equal comparisons on float so round to 5 digits
    return double.parse(((ll0.latitude - ll1.latitude) * (ll0.latitude - ll1.latitude) +
        (ll0.longitude - ll1.longitude) * (ll0.longitude - ll1.longitude)).toStringAsFixed(5));
  }

  // for rubber banding
  void insertWaypoint(Waypoint waypoint) {
    Storage().realmHelper.addRecent(waypoint.destination);

    if(Destination.isAirway(waypoint.destination.type) || _waypoints.isEmpty) {
      addWaypoint(waypoint); // airways cannot be added in the middle. that's confusing
      return;
    }
    else {
      // take all waypoints then two at a time, create path in between them, then find to which point in the
      // path the new waypoint is closest, then insert it there
      int selected = 0;
      double min = double.infinity;
      LatLng ll = waypoint.destination.coordinate;
      for(int index = 0; index < _waypoints.length - 1; index++) {
        Destination d0 = _waypoints[index].destination;
        Destination d1 = _waypoints[index + 1].destination;
        List<LatLng> path = _makePathPoints([d0, d1], fine: true);
        for(int index0 = 0; index0 < path.length; index0++) {
          double dist = _quickDistance(path[index0], ll);
          if(dist < min) {
            min = dist;
            selected = index;
          }
        }
      }

      Destination d0 = _waypoints[0].destination;
      Destination d1 = _waypoints[_waypoints.length - 1].destination;
      // if closets to first, insert at beginning, if closest to end, at at end, else in the middle
      double dist0 = _quickDistance(d0.coordinate, ll);
      double dist1 = _quickDistance(d1.coordinate, ll);
      if(dist0 <= min) {
        _waypoints.insert(0, waypoint);
      }
      else if(dist1 <= min) {
        _waypoints.add(waypoint);
      }
      else {
        _waypoints.insert(selected + 1, waypoint);
      }
      _setCurrent(_waypoints[0]);
      _update(true);
    }
  }


  // for rubber banding
  void replaceDestination(int index, LatLng ll) {
    if(Destination.isAirway(_waypoints[index].destination.type)) {
      return;
    }
    if(index >= 0 && index < _waypoints.length) {
      _waypoints[index] = Waypoint(Destination.fromLatLng(ll));
      _setCurrent(_waypoints[0]);
      _update(true);
    }
  }


  // also for rubber banding
  void replaceDestinationFromDb(int index, LatLng ll) {
    if(Destination.isAirway(_waypoints[index].destination.type)) {
      return;
    }
    if(index >= 0 && index < _waypoints.length) {
      MainDatabaseHelper.db.findNear(ll, factor: 0.0001).then((onValue) { // snap but not too far
        if(Destination.isAirport(onValue[0].type)) {
          MainDatabaseHelper.db.findAirport(onValue[0].locationID).then((airport) {
            _waypoints[index] = Waypoint(airport!);
            _setCurrent(_waypoints[0]);
            _update(true);
            return;
          });
        }
        _waypoints[index] = Waypoint(onValue[0]);
        _setCurrent(_waypoints[0]);
        _update(true);
      });
    }
  }


  void _setCurrent(Waypoint? w) {
    _current = w;
    _passage = null;
  }
}
