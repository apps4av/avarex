import 'dart:async';
import 'dart:typed_data';

import 'package:avaremp/utils/app_log.dart';
import 'package:universal_io/io.dart';

/// Describes an Avidyne IFD discovered on the local Wi-Fi network.
///
/// Parsed from the 32 byte `AviWifiInfo` capability datagram the IFD
/// broadcasts. See the AviSDK `AviWifiInfo` class for the field layout.
class AvidyneDevice {
  final String ipAddress;
  final int chassisId;
  final int sdkVersion;
  final int hwCaps;
  final int swCaps;
  final int swCaps2;
  final int cfgCaps;
  final List<int> swVersion; // product family, major, minor, FMS
  DateTime lastSeen;

  AvidyneDevice({
    required this.ipAddress,
    required this.chassisId,
    required this.sdkVersion,
    required this.hwCaps,
    required this.swCaps,
    required this.swCaps2,
    required this.cfgCaps,
    required this.swVersion,
    required this.lastSeen,
  });

  // SwCaps bit 0: IFD can accept input flight plans ("stored routes").
  bool get acceptsFlightPlans => (swCaps & (1 << 0)) != 0;

  // SwCaps bit 3: IFD can accept user waypoints.
  bool get acceptsUserWaypoints => (swCaps & (1 << 3)) != 0;

  String get versionLabel {
    if (swVersion.length >= 4 && swVersion.any((v) => v != 0)) {
      return "${swVersion[0]}.${swVersion[1]}.${swVersion[2]}.${swVersion[3]}";
    }
    return "unknown";
  }

  String get label => "Avidyne IFD ($ipAddress)";

  static AvidyneDevice? parse(Uint8List data, DateTime now) {
    if (data.length < 16) {
      return null;
    }
    final String ip = "${data[1]}.${data[2]}.${data[3]}.${data[4]}";
    // A zeroed address means the packet is not (yet) a usable capability report.
    if (ip == "0.0.0.0") {
      return null;
    }
    return AvidyneDevice(
      ipAddress: ip,
      swVersion: [data[5], data[6], data[7], data[8]],
      sdkVersion: data[9],
      hwCaps: data[10],
      swCaps: data[11],
      cfgCaps: data[12],
      chassisId: data[13],
      swCaps2: data[15],
      lastSeen: now,
    );
  }
}

/// Handles the UDP discovery handshake with Avidyne IFDs:
///   - listens for capability datagrams on port 5679, and
///   - periodically broadcasts the "AVISDK" trigger on port 5686 that prompts
///     the IFD to report its capabilities.
class AvidyneDiscovery {
  static const int capabilitiesPort = 5679; // IFD -> app
  static const int broadcastPort = 5686; // app -> IFD
  static const Duration _broadcastInterval = Duration(seconds: 5);

  RawDatagramSocket? _listenSocket;
  RawDatagramSocket? _sendSocket;
  Timer? _broadcastTimer;
  bool _running = false;

  final void Function(AvidyneDevice device) onDevice;

  AvidyneDiscovery({required this.onDevice});

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) {
      return;
    }
    _running = true;
    try {
      _listenSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4, capabilitiesPort,
          reuseAddress: true, reusePort: true);
      _listenSocket!.listen(_onData);

      _sendSocket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _sendSocket!.broadcastEnabled = true;

      _sendTrigger();
      _broadcastTimer =
          Timer.periodic(_broadcastInterval, (_) => _sendTrigger());
    } catch (e) {
      AppLog.logMessage("Avidyne discovery start error: $e");
      await stop();
    }
  }

  void _onData(RawSocketEvent event) {
    if (event != RawSocketEvent.read) {
      return;
    }
    final RawDatagramSocket? socket = _listenSocket;
    if (socket == null) {
      return;
    }
    while (true) {
      final Datagram? dg = socket.receive();
      if (dg == null) {
        break;
      }
      final AvidyneDevice? device =
          AvidyneDevice.parse(dg.data, DateTime.now());
      if (device != null) {
        onDevice(device);
      }
    }
  }

  void _sendTrigger() {
    try {
      _sendSocket?.send(_triggerMessage, InternetAddress("255.255.255.255"),
          broadcastPort);
    } catch (e) {
      AppLog.logMessage("Avidyne discovery broadcast error: $e");
    }
  }

  static final Uint8List _triggerMessage =
      Uint8List.fromList("AVISDK".codeUnits);

  Future<void> stop() async {
    _running = false;
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _listenSocket?.close();
    _listenSocket = null;
    _sendSocket?.close();
    _sendSocket = null;
  }
}
