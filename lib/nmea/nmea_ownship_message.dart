// A class that combines RMC and GGA

import 'package:avaremp/nmea/gga_message.dart';
import 'package:avaremp/nmea/nmea_message.dart';
import 'package:avaremp/nmea/rmc_message.dart';
import 'package:avaremp/nmea/rtm_message.dart';
import 'package:latlong2/latlong.dart';

import 'nmea_message_factory.dart';

class NmeaOwnShipMessage extends NmeaMessage {

  double altitude = -100;
  LatLng coordinates = const LatLng(0, 0);
  int icao = 0;
  double velocity = 0;
  double verticalSpeed = 0;
  double heading = 0;

  NmeaOwnShipMessage(super.type);

  factory NmeaOwnShipMessage.fromGgaRmc(GGAMessage? gga, RMCMessage? rmc) {
    NmeaOwnShipMessage m = NmeaOwnShipMessage(NmeaMessageType.ownShip);
    if(gga == null && rmc == null) {
      // bug
    }
    else if(gga == null && rmc != null) {
      m.velocity = rmc.speed.toDouble();
      m.heading = rmc.track.toDouble();
      m.coordinates = rmc.coordinate;
    }
    else if(gga != null && rmc == null) {
      m.coordinates = gga.coordinate;
      m.altitude = gga.altitude.toDouble();
    }
    else if(gga != null && rmc != null) {
      Duration diff = gga.time.difference(rmc.time);
      if (diff.inMilliseconds > 0) {
        // GGA is newer
        m.coordinates = gga.coordinate;
      }
      else {
        m.coordinates = rmc.coordinate;
      }
      m.altitude = gga.altitude.toDouble();
      m.velocity = rmc.speed.toDouble();
      m.heading = rmc.track.toDouble();
    }
    return (m);
  }

  factory NmeaOwnShipMessage.fromRtm(RTMMessage rtm) {
    NmeaOwnShipMessage m = NmeaOwnShipMessage(NmeaMessageType.ownShip);
    m.coordinates = rtm.coordinate;
    m.altitude = rtm.altitude.toDouble();
    m.velocity = rtm.speed.toDouble();
    m.heading = rtm.track.toDouble();
    m.icao = rtm.icao;
    return (m);
  }

}