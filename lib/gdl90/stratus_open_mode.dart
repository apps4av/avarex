import 'dart:typed_data';

import 'package:avaremp/utils/app_log.dart';
import 'package:universal_io/io.dart';

/// Sends the Appareo Stratus 3 / 3i "Open ADS-B Mode" command so the receiver
/// streams standard GDL90 on UDP 4000. The device must be on the Stratus Wi-Fi
/// network (and Local Network allowed on iOS).
class StratusOpenMode {
  static const int port = 41500;

  // Same packet Horizon Pro / IFD "WIFI ADS-B Support" broadcasts.
  static final Uint8List _packet =
      Uint8List.fromList([0xC2, 0x53, 0xFF, 0x56, 0x01, 0x01, 0x6E, 0x37]);

  /// Broadcast the open-mode command once. Returns true on a successful send.
  static Future<bool> send() async {
    try {
      RawDatagramSocket socket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      int sent =
          socket.send(_packet, InternetAddress("255.255.255.255"), port);
      socket.close();
      return sent > 0;
    }
    catch(e) {
      AppLog.logMessage("Stratus open-mode send error: $e");
      return false;
    }
  }
}
