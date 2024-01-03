
import 'package:avaremp/geo_calculations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'destination.dart';
import 'gps.dart';

class PlanRoute {

  // all segments
  Destination? _origin;
  List<Destination>? _route;
  Destination? _destination;

  List<LatLng>? _points;
  int _next = 0;

  void update() {
    if(null == _origin || null == _destination) {
      return;
    }

    List<Destination> complete = [];

    complete.add(_origin!);
    _route != null ? complete.addAll(_route!) : {};
    complete.add(_destination!);

    GeoCalculations calc = GeoCalculations();
    //2 at a time
    _points = [];
    for(int index = 0; index < complete.length - 1; index++) {
      LatLng d1 = complete[index].coordinate;
      LatLng d2 = complete[index + 1].coordinate;
      List<LatLng> routeIntermediate = calc.findPoints(d1, d2);
      _points!.addAll(routeIntermediate);
    }
  }

  void setOrigin(Destination origin) {
    _origin = origin;
    update();
  }
  void setDestination(Destination destination) {
    _destination = destination;
    update();
  }



  void addWaypoint(Destination waypoint) {
    _route = _route ?? [];
    _route!.add(waypoint);
  }

  List<LatLng>? getPath() {
    return _points;
  }

  Destination? getNextWaypoint() {
    if(null == _origin || null == _destination) {
      return null;
      // never return origin
    }
    // if no route then destination
    if(_route == null || _route!.isEmpty) {
      return(_destination);
    }
    // otherwise route
    return _route![_next];

  }

  static PlanRoute makeFromLocation(Position start, PlanRoute? route) {
    PlanRoute r = PlanRoute();
    Destination dummy = Destination.dummy(Gps.toLatLng(start));
    r.setOrigin(dummy);
    if(route != null && route.getNextWaypoint() != null) {
      r.setDestination(route.getNextWaypoint()!);
    }
    else {
      r.setDestination(dummy);
    }
    return r;
  }

  Destination? get origin => _origin; // complete route of all segments
  List<Destination>? get route => _route;
  Destination? get destination => _destination;
}