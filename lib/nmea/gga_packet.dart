import 'package:avaremp/nmea/packet.dart';
import 'package:intl/intl.dart';

class GGAPacket extends Packet {
  static const String TAG = '\$GPGGA';
  static const String TAGN = '\$GNGGA';
  static const int HD = 8;
  static const int ALT = 9;
  static const int GEOID = 11;

  GGAPacket(int time, double latitude, double longitude, double altitude, int satCount, double geoid, double horDil) {
    packet = '$TAG,';

    // Convert to UTC system time, and format to hhmmss as in NMEA
    DateTime date = DateTime.fromMillisecondsSinceEpoch(time, isUtc: true);
    DateFormat sdf = DateFormat('HHmmss');
    packet += '${sdf.format(date)},';

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

    // A true GPS fix
    packet += '1,';

    // How many satellites used in this fix.
    packet += '${satCount.toString().padLeft(2, '0')},';

    // Horizontal dilution
    packet += '${horDil.toStringAsFixed(1)},';

    // Put altitude in METERS
    packet += '${altitude.toStringAsFixed(1)},M,';

    // GEOID and a couple of empty fields
    packet += '${geoid.toStringAsFixed(1)},M,,';

    assemble();
  }
}