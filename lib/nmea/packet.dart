import 'dart:convert';

import 'nmea_message_factory.dart' show NmeaMessageFactory;

class Packet {
  String packet = '';

  void assemble() {
    // Checksum
    packet += '*';

    int xor = NmeaMessageFactory.checkSum(utf8.encode(packet));
    String ma = xor.toRadixString(16).toUpperCase();
    if (ma.length < 2) {
      packet += '0';
    }
    packet += ma;
    packet += '\r\n';
  }

  String getPacket() {
    return packet;
  }
}