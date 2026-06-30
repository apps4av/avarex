import 'dart:typed_data';

import 'message.dart';

/// GDL90 device report (type 0x7A), as emitted by some UAT receivers (e.g.
/// Stratux/SkyRadar). It reports the battery charge level and charging state.
class DeviceReportMessage extends Message {

  double batteryLevel = 0; // 0.0 .. 1.0
  bool charging = false;

  DeviceReportMessage(super.type);

  @override
  void parse(Uint8List message) {
    if (message.length < 5) {
      return;
    }

    int vbat = ((message[0].toInt() & 0xFF) << 8) + (message[1].toInt() & 0xFF);
    double level = (vbat - 3500) / 600.0;
    if (level > 1.0) {
      level = 1.0;
    } else if (level < 0) {
      level = 0.0;
    }
    batteryLevel = level;

    charging = (message[4].toInt() & 0x04) != 0;
  }

  @override
  String decode() =>
      "Battery: ${(batteryLevel * 100).toStringAsFixed(0)}%\n"
      "Charging: ${charging ? "yes" : "no"}";
}
