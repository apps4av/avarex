import 'package:avaremp/nmea/packet.dart';
import 'package:intl/intl.dart';

class RTMPacket extends Packet {
  RTMPacket(
      int time,
      int icaoAddress,
      double latitude,
      double longitude,
      int altitude,
      int horizVelocity,
      int vertVelocity,
      double heading,
      String callSign,
      ) {
    packet = '\$GPRTM,';

    // Convert to UTC system time, and format to hhmmss as in NMEA
    DateTime date = DateTime.fromMillisecondsSinceEpoch(time, isUtc: true);
    DateFormat sdf = DateFormat('HHmmss');
    packet += '${sdf.format(date)},';

    // icao
    packet += '$icaoAddress,';

    // Put latitude
    if (latitude > 0) {
      int lat = latitude.toInt();
      double deg = (latitude - lat) * 60.0;

      packet += lat.toString().padLeft(2, '0');
      packet += '${deg.toStringAsFixed(3).padLeft(6, '0')},N,';
    } else {
      latitude = -latitude;
      int lat = latitude.toInt();
      double deg = (latitude - lat) * 60.0;

      packet += lat.toString().padLeft(2, '0');
      packet += '${deg.toStringAsFixed(3).padLeft(6, '0')},S,';
    }

    // Put longitude
    if (longitude > 0) {
      int lon = longitude.toInt();
      double deg = (longitude - lon) * 60.0;

      packet += lon.toString().padLeft(3, '0');
      packet += '${deg.toStringAsFixed(3).padLeft(6, '0')},E,';
    } else {
      longitude = -longitude;
      int lon = longitude.toInt();
      double deg = (longitude - lon) * 60.0;

      packet += lon.toString().padLeft(3, '0');
      packet += '${deg.toStringAsFixed(3).padLeft(6, '0')},W,';
    }

    // Put altitude
    packet += '${altitude.toStringAsFixed(1)},';

    // Put heading
    packet += '${heading.toStringAsFixed(1).padLeft(5, '0')},';

    // Put speed in knots
    packet += '${horizVelocity.toStringAsFixed(1).padLeft(5, '0')},';

    // Put vert velocity in ft/min
    packet += '${vertVelocity.toStringAsFixed(1).padLeft(5, '0')},';

    // Put callsign
    packet += '$callSign,';

    assemble();
  }
}