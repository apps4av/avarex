
import 'package:avaremp/destination/destination.dart';

class Waypoint {

  final Destination _destination;
  List<Destination> destinationsOnRoute = [];
  int currentDestinationIndex = 0;

  Waypoint(this._destination);

  /// Waypoint as entered in the plan. An airway or procedure stays that
  /// airway or procedure, not the fix currently being flown along it.
  Destination get planDestination => _destination;

  Destination get destination {
    return destinationsOnRoute.isNotEmpty ?
    destinationsOnRoute[currentDestinationIndex] : _destination;
  }

  // return points passed, current, next
  List<Destination> getDestinationsNext() {
    if(destinationsOnRoute.isNotEmpty) {
      return currentDestinationIndex == (destinationsOnRoute.length - 1) ?
      [] : destinationsOnRoute.sublist(currentDestinationIndex + 1, destinationsOnRoute.length);
    }
    return [];
  }

  // return points passed, current, next
  List<Destination> getDestinationsPassed() {
    if(destinationsOnRoute.isNotEmpty) {
      return currentDestinationIndex == 0 ?
      [] : destinationsOnRoute.sublist(0, currentDestinationIndex);
    }
    return [];
  }

  // return points passed, current, next
  List<Destination> getDestinationsCurrent() {
    if(destinationsOnRoute.isNotEmpty) {
      return [destinationsOnRoute[currentDestinationIndex]];
    }
    return [];
  }

}
