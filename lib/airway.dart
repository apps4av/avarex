import 'package:avaremp/destination.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:latlong2/latlong.dart';


// airway calculations
class Airway {

  // Max segment length is 500NM, this is to keep airways in AK/HI separated from US48
  static const double maxSegmentLength = 500;

  static LatLng? findIntersectionOfAirways(AirwayDestination destination0, AirwayDestination destination1) {

    List<LatLng> coordinates0 = destination0.points.map((e) => e.coordinate).toList();
    List<LatLng> coordinates1 = destination1.points.map((e) => e.coordinate).toList();

    // Find the point that intersects, could be optimized.
    GeoCalculations calc = GeoCalculations();
    for (LatLng c0 in coordinates0) {
      for (LatLng c1 in coordinates1) {
        if (calc.calculateDistance(c0, c1) == 0) {
          return c0;
        }
      }
    }
    return null;
  }

  static LatLng? findPoint(Destination point, AirwayDestination airway) {

    LatLng? coordinate;

    // airway to airway
    if(point is AirwayDestination) {
      coordinate = findIntersectionOfAirways(point, airway);
    }
    else {
      // Find airway point from nav aid
      coordinate = point.coordinate;
    }
    return coordinate;
  }

  static int findIndex(AirwayDestination airway, LatLng coordinate) {
    // find index of intersection
    int i = 0;
    int index = -1;
    double minD = double.infinity;
    GeoCalculations calc = GeoCalculations();
    List<LatLng> coordinates = airway.points.map((e) => e.coordinate).toList();

    for(LatLng c in coordinates) {
      double dist = calc.calculateDistance(c, coordinate);
      if(dist < minD) {
        index = i;
        minD = dist;
      }
      i++;
    }
    return minD == 0 ? index : -1; // do not fly this airway as its disjointed
  }

  // Find all points between start and end on an airway
  static List<Destination> find(Destination start, AirwayDestination airway, Destination end) {

    List<Destination> ret = [];
    List<LatLng> coordinates = airway.points.map((e) => e.coordinate).toList();
    GeoCalculations calc = GeoCalculations();

    // Not an airway
    if(airway.points.isEmpty) {
      return ret;
    }

    // find start point
    LatLng? startCoordinate = findPoint(start, airway);
    if(startCoordinate == null) {
      return ret;
    }

    // find end point
    LatLng? endCoordinate = findPoint(end, airway);
    if(endCoordinate == null) {
      return ret;
    }

    // Now find start to end of an airway
    int startIndex = findIndex(airway, startCoordinate);
    int endIndex = findIndex(airway, endCoordinate);

    // Some sort of error
    if(startIndex < 0 || endIndex < 0 || startIndex == endIndex) {
      return ret;
    }

    // Add all points on the route, skip start and end points
    if(startIndex < endIndex) {
      startIndex++;
      endIndex--; // remove entry and exit as they are in the plan already
      LatLng lastCoordinate = coordinates[startIndex];
      for(int i = startIndex; i <= endIndex; i++) {
        LatLng c = coordinates[i];
        // Keep far away airways out
        if(calc.calculateDistance(c, lastCoordinate) > maxSegmentLength) {
          continue;
        }
        lastCoordinate = c;
        // add it
        Destination d = Destination(locationID: airway.locationID, type: airway.type, facilityName: airway.facilityName, coordinate: lastCoordinate);
        ret.add(d);
      }
    }
    else {
      startIndex--;
      endIndex++;
      LatLng lastCoordinate = coordinates[startIndex];
      // Flying it reverse
      for(int i = startIndex; i >= endIndex; i--) {
        LatLng c = coordinates[i];
        // Keep far away airways out
        if(calc.calculateDistance(c, lastCoordinate) > maxSegmentLength) {
          continue;
        }
        lastCoordinate = c;

        // add it
        Destination d = Destination(locationID: airway.locationID, type: airway.type, facilityName: airway.facilityName, coordinate: lastCoordinate);
        ret.add(d);
      }
    }

    return ret;
  }
}
