import 'package:avaremp/nmea/packet.dart';

class WPLPacket extends Packet {
  WPLPacket(double latitude, double longitude, String id) {
    packet = '\$GPWPL,';

    // Latitude in ddmm.mmm format
    if (latitude >= 0) {
      int lat = latitude.toInt();
      double minutes = (latitude - lat) * 60.0;
      packet += lat.toString().padLeft(2, '0');
      packet += '${minutes.toStringAsFixed(3).padLeft(6, '0')},N,';
    } else {
      latitude = -latitude;
      int lat = latitude.toInt();
      double minutes = (latitude - lat) * 60.0;
      packet += lat.toString().padLeft(2, '0');
      packet += '${minutes.toStringAsFixed(3).padLeft(6, '0')},S,';
    }

    // Longitude in dddmm.mmm format
    if (longitude >= 0) {
      int lon = longitude.toInt();
      double minutes = (longitude - lon) * 60.0;
      packet += lon.toString().padLeft(3, '0');
      packet += '${minutes.toStringAsFixed(3).padLeft(6, '0')},E,';
    } else {
      longitude = -longitude;
      int lon = longitude.toInt();
      double minutes = (longitude - lon) * 60.0;
      packet += lon.toString().padLeft(3, '0');
      packet += '${minutes.toStringAsFixed(3).padLeft(6, '0')},W,';
    }

    packet += id;
    assemble();
  }
}
