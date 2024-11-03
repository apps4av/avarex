import 'package:avaremp/nmea/packet.dart';
import 'package:intl/intl.dart';

class RMCPacket extends Packet {

  RMCPacket(int time, double latitude, double longitude, double speed, double bearing, double dec) {
    packet = "\$GPRMC,";

    // Convert to UTC system time, and format to hhmmss as in NMEA
    DateTime date = DateTime.fromMillisecondsSinceEpoch(time, isUtc: true);
    DateFormat sdf = DateFormat("HHmmss");
    packet += "${sdf.format(date)},";

    packet += "A,";

    // Put latitude
    if (latitude > 0) {
      int lat = latitude.toInt();
      double deg = (latitude - lat) * 60.0;

      packet += lat.toString().padLeft(2, '0');
      packet += "${deg.toStringAsFixed(3).padLeft(6, '0')},N,";
    } else {
      latitude = -latitude;
      int lat = latitude.toInt();
      double deg = (latitude - lat) * 60.0;

      packet += lat.toString().padLeft(2, '0');
      packet += "${deg.toStringAsFixed(3).padLeft(6, '0')},S,";
    }

    // Put longitude
    if (longitude > 0) {
      int lon = longitude.toInt();
      double deg = (longitude - lon) * 60.0;

      packet += lon.toString().padLeft(3, '0');
      packet += "${deg.toStringAsFixed(3).padLeft(6, '0')},E,";
    } else {
      longitude = -longitude;
      int lon = longitude.toInt();
      double deg = (longitude - lon) * 60.0;

      packet += lon.toString().padLeft(3, '0');
      packet += "${deg.toStringAsFixed(3).padLeft(6, '0')},W,";
    }

    // Put speed knots
    packet += "${speed.toStringAsFixed(1).padLeft(5, '0')},";

    // Put bearing
    packet += "${bearing.toStringAsFixed(1).padLeft(5, '0')},";

    // Put date
    sdf = DateFormat("ddMMyy");
    packet += "${sdf.format(date)},";

    // Put variation
    if (dec < 0) {
      dec = -dec;
      packet += "${dec.toStringAsFixed(1).padLeft(5, '0')},E";
    } else {
      packet += "${dec.toStringAsFixed(1).padLeft(5, '0')},W";
    }

    assemble();
  }
}