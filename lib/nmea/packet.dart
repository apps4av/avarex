import 'dart:convert';

class Packet {
  String packet = '';

  void assemble() {
    // Checksum
    packet += '*';

    int xor = _checksum(utf8.encode(packet));
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

  int _checksum(List<int> bytes) {
    int xor = 0;
    for (int byte in bytes) {
      xor ^= byte;
    }
    return xor;
  }
}