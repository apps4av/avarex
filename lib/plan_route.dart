
import 'package:avaremp/geo_calculations.dart';
import 'package:latlong2/latlong.dart';

import 'destination.dart';

class PlanRoute {

  PlanRoute(this.currentLocation);

  // all segments
  final List<Destination> _segments = [];
  LatLng currentLocation;
  int nextIndex = 0;

  void addWaypoint(Destination waypoint) {
    _segments.add(waypoint);
  }

  // complete route of all segments
  List<LatLng> getRoute() {
    List<LatLng> route = [];
    GeoCalculations calc = GeoCalculations();
    //2 at a time
    List<LatLng> values = [currentLocation];
    values.addAll(_segments.map((e) => e.coordinate));
    for(int index = 0; index < values.length - 1; index++) {
      LatLng d1 = values[index];
      LatLng d2 = values[index + 1];
      List<LatLng> routeIntermediate = calc.findPoints(d1, d2);
      route.addAll(routeIntermediate);
    }
    return route;
  }

  void startFromFirstWaypoint() {
    if(_segments.isNotEmpty) {
      currentLocation = _segments[0].coordinate;
    }
  }

  Destination? getNextWaypoint() {
    if(_segments.isEmpty) {
      return null;
    }
    return _segments[nextIndex];
  }

}