import 'package:avaremp/nmea/packet.dart';

class BODPacket extends Packet {
  BODPacket(String idDest, String idStart, double bearingTrue, double bearingMag) {
    packet = '\$GPBOD,';

    // Put bearingTrue
    packet += '${bearingTrue.toStringAsFixed(1).padLeft(5, '0')},T,';

    // Put bearingMag
    packet += '${bearingMag.toStringAsFixed(1).padLeft(5, '0')},M,';

    // Destination
    packet += '$idDest,';

    // Start
    packet += idStart;

    assemble();
  }
}