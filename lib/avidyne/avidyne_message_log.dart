import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// A single WiFiCrChannel (or discovery) message for the transfer-screen log.
class AvidyneLogEntry {
  final DateTime time;
  final bool outbound; // true = app → IFD, false = IFD → app
  final String type; // e.g. "Request-Upload (0x00)"
  final String summary; // short one-line label (may be "")
  final String raw; // raw bytes as hex
  AvidyneLogEntry(this.time, this.outbound, this.type, this.summary, this.raw);

  String get directionLabel => outbound ? "TX" : "RX";
}

/// Holds the scrolling hex message log shown on the Avidyne transfer screen.
///
/// [AvidyneWifiChannel] posts every TCP send/receive here (the same way GDL90
/// posts to [AdsbStatus]). Discovery traffic is not logged — the AVISDK
/// trigger repeats every few seconds and would crowd out transfer traffic.
class AvidyneMessageLog {
  static final AvidyneMessageLog _instance = AvidyneMessageLog._();
  factory AvidyneMessageLog() => _instance;
  AvidyneMessageLog._();

  static const int _maxLog = 50;

  final ValueNotifier<int> logChange = ValueNotifier<int>(0);

  final List<AvidyneLogEntry> _log = [];
  bool logPaused = false;

  List<AvidyneLogEntry> messages() => _log.reversed.toList();

  void logMessage(bool outbound, Uint8List bytes) {
    if (logPaused || bytes.isEmpty) {
      return;
    }
    _log.add(AvidyneLogEntry(
      DateTime.now(),
      outbound,
      describeCommand(bytes[0]),
      summarizePacket(bytes),
      toHex(bytes),
    ));
    if (_log.length > _maxLog) {
      _log.removeAt(0);
    }
    logChange.value++;
  }

  void clear() {
    _log.clear();
    logChange.value++;
  }

  void toggleLogPaused() {
    logPaused = !logPaused;
    logChange.value++;
  }

  static String toHex(Uint8List bytes) {
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < bytes.length; i++) {
      sb.write((bytes[i] & 0xFF).toRadixString(16).padLeft(2, '0'));
      if (i != bytes.length - 1) {
        sb.write(' ');
      }
    }
    return sb.toString();
  }

  static String describeCommand(int cmd) {
    switch (cmd & 0xFF) {
      case 0x00:
        return "Request-Upload (0x00)";
      case 0x01:
        return "Request-Download (0x01)";
      case 0x04:
        return "Start-Download (0x04)";
      case 0x40:
        return "Upload-Data (0x40)";
      case 0x41:
        return "Download-Data (0x41)";
      case 0x80:
        return "Ready (0x80)";
      case 0x83:
        return "Done (0x83)";
      case 0x84:
        return "ACK (0x84)";
      case 0x85:
        return "NAK (0x85)";
      default:
        return "0x${(cmd & 0xFF).toRadixString(16).padLeft(2, '0')}";
    }
  }

  /// Short one-line context for the collapsed row (file length, packet id, …).
  static String summarizePacket(Uint8List data) {
    if (data.isEmpty) {
      return "";
    }
    final int cmd = data[0] & 0xFF;
    switch (cmd) {
      case 0x00: // Request-Upload: dataset + file length
        if (data.length >= 10) {
          final int len =
              (data[6] << 24) | (data[7] << 16) | (data[8] << 8) | data[9];
          return "dataset ${data[5]}, $len bytes";
        }
        break;
      case 0x01: // Request-Download: dataset
        if (data.length >= 6) {
          return "dataset ${data[5]}";
        }
        break;
      case 0x04: // Start-Download: uid
        if (data.length >= 6) {
          return "uid ${data[5]}";
        }
        break;
      case 0x40: // Upload-Data: uid, packet id, payload size
        if (data.length >= 8) {
          return "uid ${data[5]}, pkt ${data[6]}, ${data.length - 8} bytes";
        }
        break;
      case 0x41: // Download-Data: uid, packet id, payload size
        if (data.length >= 8) {
          return "uid ${data[5]}, pkt ${data[6]}, ${data.length - 8} bytes";
        }
        break;
      case 0x80: // Ready: upload uses byte 5 as uid; download adds length
        if (data.length >= 11) {
          final int len =
              (data[6] << 24) | (data[7] << 16) | (data[8] << 8) | data[9];
          return "uid ${data[5]}, $len bytes";
        }
        if (data.length >= 6) {
          return "uid ${data[5]}";
        }
        break;
      case 0x84: // ACK: packet id in byte 6
      case 0x85: // NAK
        if (data.length >= 7) {
          return "pkt ${data[6]}";
        }
        break;
    }
    return "${data.length} bytes";
  }
}
