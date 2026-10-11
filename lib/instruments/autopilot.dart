import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/instruments/cdi_vdi.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:avaremp/nmea/bod_packet.dart';
import 'package:avaremp/nmea/gga_packet.dart';
import 'package:avaremp/nmea/rmb_packet.dart';
import 'package:avaremp/nmea/rmc_packet.dart';
import 'package:avaremp/plan/waypoint.dart';
import 'package:avaremp/storage.dart';
import 'package:latlong2/latlong.dart';
import 'package:avaremp/io/gps.dart';

class AutoPilot {
  static String apCreateSentences() {

    LatLng currentPosition = Gps.toLatLng(Storage().position);
    double speedKnots = Storage().position.speed * 1.94384; // convert m/s to knots

    // Create NMEA packet #1
    RMCPacket rmcPacket = RMCPacket(
      Storage().position.timestamp.millisecondsSinceEpoch,
      Storage().position.latitude,
      Storage().position.longitude,
      speedKnots, // convert m/s to knots
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
    Destination? prev = Storage().route.getPreviousDestination();
    final CdiLeg? leg = Cdi.resolve(
      position: currentPosition,
      current: wp?.destination,
      previous: prev,
      destinations: destinations,
    );

    if (leg != null) {
      Destination next = leg.next;
      String startID = prev?.locationID ?? (destinations.isNotEmpty ? destinations[0].locationID : "");
      String endID = next.locationID;

      // Limit our station IDs to 5 chars max so we don't exceed the 80 char
      // sentence limit. A "GPS" fix has a temp name that is quite long
      if (startID.length > 5) {
        startID = "gSRC";
      }

      if (endID.length > 5) {
        endID = "gDST";
      }

      int indexCurrent = destinations.indexWhere((element) => element == next);
      bool planComplete = indexCurrent >= 0 &&
          destinations.length == indexCurrent + 1;

      RMBPacket rmbPacket = RMBPacket(
        leg.distance,
        leg.targetBearing,
        next.coordinate.longitude,
        next.coordinate.latitude,
        endID,
        startID,
        leg.crossTrackNm,
        speedKnots,
        planComplete,
      );
      apText += rmbPacket.packet;

      BODPacket bodPacket = BODPacket(
        endID,
        startID,
        leg.courseBearing,
        GeoCalculations.getMagneticHeading(leg.courseBearing, (next.geoVariation == null ? Storage().area.variation : next.geoVariation!)),
      );
      apText += bodPacket.packet;
    }
    return apText;
  }
}
