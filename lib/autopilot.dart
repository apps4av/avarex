import 'dart:math';

import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/nmea/bod_packet.dart';
import 'package:avaremp/nmea/gga_packet.dart';
import 'package:avaremp/nmea/rmb_packet.dart';
import 'package:avaremp/nmea/rmc_packet.dart';
import 'package:avaremp/plan/waypoint.dart';
import 'package:avaremp/storage.dart';

import 'gps.dart';

class AutoPilot {
  static String apCreateSentences() {
    // Create NMEA packet #1
    RMCPacket rmcPacket = RMCPacket(
      Storage().position.timestamp.millisecondsSinceEpoch,
      Storage().position.latitude,
      Storage().position.longitude,
      GeoCalculations.convertSpeed(Storage().position.speed),
      Storage().position.heading,
      Storage().area.variation,
    );
    String apText = rmcPacket.packet;

    // Create NMEA packet #2
    GGAPacket ggaPacket = GGAPacket(
      Storage().position.timestamp.millisecondsSinceEpoch,
      Storage().position.latitude,
      Storage().position.longitude,
      Storage().position.altitude,
      6, // just assume as no way to get
      Storage().area.geoAltitude,
      0 // just assume as no way to get
    );
    apText += ggaPacket.packet;

    List<Destination> destinations = Storage().route.getAllDestinations();
    Waypoint? wp = Storage().route.getCurrentWaypoint();

    // there is no concept of destination without plan in X.
    if (wp != null) {
      int indexCurrent = destinations.indexWhere((element) => element == wp.destination);
      if (indexCurrent > 0) {
        Destination next = destinations[indexCurrent];
        Destination prev = destinations[indexCurrent - 1];
        String startID = prev.locationID;
        String endID = next.locationID;

        // Limit our station IDs to 5 chars max so we don't exceed the 80 char
        // sentence limit. A "GPS" fix has a temp name that is quite long
        if (startID.length > 5) {
          startID = "gSRC";
        }

        if (endID.length > 5) {
          endID = "gDST";
        }

        double brgOrig = GeoCalculations().calculateBearing(
            prev.coordinate,
            next.coordinate);

        double bearing = GeoCalculations().calculateBearing(
            Gps.toLatLng(Storage().position),
            next.coordinate);

        double distance = GeoCalculations().calculateDistance(
            Gps.toLatLng(Storage().position),
            next.coordinate);

        // Calculate how many miles we are to the side of the course line
        double deviation = distance * sin(_angularDifference(brgOrig, bearing));

        // If we are to the left of the course line, then make our deviation negative.
        if (_leftOfCourseLine(bearing, brgOrig)) {
          deviation = -deviation;
        }

        // We now have all the info to create NMEA packet #3
        RMBPacket rmbPacket = RMBPacket(
          distance,
          bearing,
          next.coordinate.longitude,
          next.coordinate.latitude,
          endID,
          startID,
          deviation,
          GeoCalculations.convertSpeed(Storage().position.speed),
          destinations.length == indexCurrent + 1,
        );
        apText += rmbPacket.packet;

        // Now for the final NMEA packet
        BODPacket bodPacket = BODPacket(
          endID,
          startID,
          brgOrig,
          GeoCalculations.getMagneticHeading(brgOrig, (next.geoVariation == null ? Storage().area.variation : next.geoVariation!)),
        );
        apText += bodPacket.packet;
      }
    }
    return apText;
  }

  static double _angularDifference(double hdg, double brg) {
    double absDiff = (hdg - brg).abs();
    if (absDiff > 180) {
      return 360 - absDiff;
    }
    return absDiff;
  }

  /// Is the brgTrue to the left of the brgCourse line (extended).
  /// @param bT true bearing to destination from current location
  /// @param bC bearing on current COURSE line
  /// @return true if it is LEFT, false if RIGHT
  static bool _leftOfCourseLine(double bT, double bC) {
    if (bC <= 180) {
      return (bT >= bC && bT <= bC + 180);
    }

    // brgCourse will be > 180 at this point
    return (bT > bC || bT < bC - 180);
  }
}