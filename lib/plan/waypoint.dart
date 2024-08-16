
import 'package:avaremp/destination/destination.dart';

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
