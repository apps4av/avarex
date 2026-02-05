import 'package:avaremp/nmea/packet.dart';

class RTEPacket extends Packet {
  RTEPacket(int totalSentences, int sentenceNumber, String routeId, List<String> waypoints) {
    packet = '\$GPRTE,$totalSentences,$sentenceNumber,c,$routeId';
    for (final waypoint in waypoints) {
      packet += ',$waypoint';
    }
    assemble();
  }
}
