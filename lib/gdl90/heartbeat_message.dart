import 'dart:typed_data';

import 'package:avaremp/storage.dart';

import 'message.dart';

/// GDL90 Heartbeat message (type 0x00).
///
/// Emitted by the ADS-B receiver roughly once per second. It carries the
/// receiver status (GPS position valid, UTC timing valid, UAT initialized)
/// and the number of UAT uplink and traffic messages received in the previous
/// second. We use it to drive the on-screen ADS-B connection indicator.
class HeartbeatMessage extends Message {

  bool gpsValid = false;
  bool maintRequired = false;
  bool utcOk = false;
  bool uatInitialized = false;
  // messages received by the receiver in the previous second
  int uplinkCount = 0;
  int trafficCount = 0;

  HeartbeatMessage(super.type);

  @override
  void parse(Uint8List message) {
    // message has already had its type byte and trailing CRC removed.
    // Payload layout: [status1][status2][tsLsb][tsMsb][countHi][countLo]
    if (message.length < 2) {
      return;
    }

    int status1 = message[0].toInt() & 0xFF;
    int status2 = message[1].toInt() & 0xFF;

    gpsValid = (status1 & 0x80) != 0;
    maintRequired = (status1 & 0x40) != 0;
    uatInitialized = (status1 & 0x01) != 0;
    utcOk = (status2 & 0x01) != 0;

    // Message counts occupy the last two payload bytes when present.
    // Bits 15..11 = uplink message count (5 bits), bit 10 reserved,
    // bits 9..0 = basic + long (traffic) message count (10 bits).
    if (message.length >= 6) {
      int countHi = message[4].toInt() & 0xFF;
      int countLo = message[5].toInt() & 0xFF;
      uplinkCount = (countHi >> 3) & 0x1F;
      trafficCount = ((countHi & 0x03) << 8) | countLo;
    }

    Storage().adsbStatus.setHeartbeat(this);
  }
}
