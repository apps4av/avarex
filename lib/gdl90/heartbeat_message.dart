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
  bool gpsBatteryLow = false;
  bool utcOk = false;
  bool uatInitialized = false;
  // messages received by the receiver in the previous second
  int uplinkCount = 0;
  int trafficCount = 0;
  // UTC time-of-day reconstructed from the timestamp field (seconds since 0000Z)
  int hour = 0;
  int min = 0;
  int sec = 0;

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
    gpsBatteryLow = (status1 & 0x08) != 0;
    uatInitialized = (status1 & 0x01) != 0;
    utcOk = (status2 & 0x01) != 0;

    // Timestamp: status2 bit7 is the MSb, followed by ts MSb/LSb. The value is
    // seconds since 0000Z, so convert to UTC hour:minute:second.
    if (message.length >= 4) {
      int tsLsb = message[2].toInt() & 0xFF;
      int tsMsb = message[3].toInt() & 0xFF;
      int timeStamp = ((status2 & 0x80) << 9) | (tsMsb << 8) | tsLsb;
      double hourFrac = timeStamp / 3600.0;
      hour = hourFrac.floor();
      double minuteFrac = (hourFrac - hour) * 60.0;
      min = minuteFrac.floor();
      sec = ((minuteFrac - min) * 60.0).round();
      if (sec == 60) {
        sec = 0;
        min++;
      }
      if (min == 60) {
        min = 0;
        hour++;
      }
    }

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

  static String _two(int v) => v.toString().padLeft(2, '0');

  @override
  String decode() =>
      "GPS position valid: $gpsValid\n"
      "Maintenance required: $maintRequired\n"
      "GPS battery low: $gpsBatteryLow\n"
      "UTC timing OK: $utcOk\n"
      "UAT initialized: $uatInitialized\n"
      "UTC time: ${_two(hour)}:${_two(min)}:${_two(sec)}Z\n"
      "Uplink messages: $uplinkCount\n"
      "Traffic messages: $trafficCount";
}
