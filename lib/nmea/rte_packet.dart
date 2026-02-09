import 'package:avaremp/nmea/packet.dart';

class RTEPacket extends Packet {
  static const String _tag = '\$GPRTE';

  RTEPacket({
    required int totalSentences,
    required int sentenceNumber,
    required bool isComplete,
    required String routeName,
    required List<String> waypoints,
  }) {
    packet = '$_tag,';
    packet += '$totalSentences,';
    packet += '$sentenceNumber,';
    packet += isComplete ? 'c' : 'w';
    packet += ',';
    packet += routeName;
    for (final waypoint in waypoints) {
      packet += ',';
      packet += waypoint;
    }
    assemble();
  }
}