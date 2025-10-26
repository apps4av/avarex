import 'package:avaremp/storage.dart';

import 'destination.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:latlong2/latlong.dart';

import '../data/main_database_helper.dart';


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
      Storage().setException("Attempted Plan creation with unknown airway");
      return ret;
    }

    // find start point
    LatLng? startCoordinate = findPoint(start, airway);
    if(startCoordinate == null) {
      Storage().setException("Attempted Plan creation has an airway segment with invalid start transition point");
      return ret;
    }

    // find end point
    LatLng? endCoordinate = findPoint(end, airway);
    if(endCoordinate == null) {
      Storage().setException("Attempted Plan creation has an airway segment with invalid end transition point");
      return ret;
    }

    List<String?> sequences = airway.points.map((e) => e.secondaryName).toList();
    List<double> distances = airway.points.map((e) => calc.calculateDistance(e.coordinate, startCoordinate)).toList();
    List<int> removalIndexes = [];
    // now remove all identical sequences based on distance, remove far off identical sequences
    for(int s = 0; s < sequences.length; s++) {
      for(int t = s + 1; t < sequences.length; t++) {
        if(sequences[s] == sequences[t]) {
          // identical sequence found, remove the one that is farther away
          if(distances[s] < distances[t]) {
            // remove t
            sequences[t] = null;
            removalIndexes.add(t);
          }
          else {
            // remove s
            sequences[s] = null;
            removalIndexes.add(s);
          }
        }
      }
    }

    for(int r in removalIndexes.reversed) {
      sequences.removeAt(r);
      distances.removeAt(r);
      airway.points.removeAt(r);
    }

    // Now find start to end of an airway
    int startIndex = findIndex(airway, startCoordinate);
    int endIndex = findIndex(airway, endCoordinate);

    // Some sort of error
    if(startIndex < 0 || endIndex < 0 || startIndex == endIndex) {
      Storage().setException("Attempted Plan creation has an airway segment with invalid start/end transition points");
      return ret;
    }

    List<LatLng> selected = [];

    // Add all points on the route, skip start and end points
    if(startIndex < endIndex) {
      selected = coordinates.sublist(startIndex + 1, endIndex);
    }
    else {
      selected = coordinates.sublist(endIndex + 1, startIndex).reversed.toList();
    }

    if(selected.isEmpty) {
      Storage().setException("Attempted Plan creation has an airway segment with no points between start and end");
    }
    else {// this can be empty if there is only 2 points on v-way
      LatLng lastCoordinate = selected[0];
      for (LatLng c in selected) {
        // Keep far away airways out
        if (calc.calculateDistance(c, lastCoordinate) > maxSegmentLength) {
          continue;
        }
        lastCoordinate = c;
        // add it
        Destination d = Destination(locationID: airway.locationID,
            type: airway.type,
            facilityName: airway.facilityName,
            coordinate: lastCoordinate);
        ret.add(d);
      }
    }

    // fill up actual names of places in the airway segments, but do it in background
    void populate() async {
      for(Destination d in ret) {
        Destination destinationFound = await MainDatabaseHelper.db.findNearNavOrFixElseGps(d.coordinate);
        d.secondaryName = destinationFound.locationID;
      }
    }
    populate();

    return ret;
  }
}



