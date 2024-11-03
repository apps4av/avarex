import 'package:avaremp/nmea/packet.dart';

class RMBPacket extends Packet {
  RMBPacket(double distance, double bearing, double longitude, double latitude, String idNext, String idOrig, double deviation, double speed, bool planComplete) {
    packet = '\$GPRMB,';

    // valid
    packet += 'A,';

    // deviation
    String dir = 'L';
    if (deviation < 0) {
      dir = 'R';
      deviation = -deviation;
    }
    if (deviation > 9.99) {
      deviation = 9.99;
    }
    packet += '${deviation.toStringAsFixed(2).padLeft(4, '0')},';
    packet += '$dir,';

    packet += '$idOrig,';
    packet += '$idNext,';

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

    // Put range
    if (distance >= 1000) {
      distance = 999.9;
    }
    packet += '${distance.toStringAsFixed(1).padLeft(5, '0')},';

    // Put bearing
    packet += '${bearing.toStringAsFixed(1).padLeft(5, '0')},';

    // Put speed
    packet += '${speed.toStringAsFixed(1).padLeft(5, '0')},';

    // Final item is whether or not we have arrived at our final destination
    packet += planComplete ? 'A' : 'V';

    assemble();
  }
}