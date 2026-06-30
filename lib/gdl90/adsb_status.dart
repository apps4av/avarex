import 'package:avaremp/gdl90/ground_station_cache.dart';
import 'package:avaremp/gdl90/heartbeat_message.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// A single received GDL90 message, for the on-screen message log.
class AdsbLogEntry {
  final DateTime time;
  final int typeId;     // GDL90 message type byte, e.g. 0x14
  final String type;    // e.g. "trafficReport (0x14)"
  final String summary; // short one-line label for the collapsed row (may be "")
  final String decoded; // human-readable decoded fields
  final String raw;     // raw payload bytes as hex
  AdsbLogEntry(this.time, this.typeId, this.type, this.summary, this.decoded, this.raw);
}

/// Holds live ADS-B receiver status. GDL90 heartbeat and FIS-B uplink messages
/// post to this directly (the same way traffic reports post to TrafficCache).
class AdsbStatus {

  static const int _staleMs = 5000; // no heartbeat for this long => disconnected
  static const int _maxLog = 50; // keep the last N received messages

  // GDL90 message types that can be shown/filtered in the log, with labels.
  static const Map<int, String> filterTypes = {
    0x00: "Heartbeat",
    0x07: "Uplink (FIS-B)",
    0x0A: "Ownship",
    0x0B: "Ownship geo. altitude",
    0x14: "Traffic",
    0x1E: "Basic report",
    0x1F: "Long report",
    0x4C: "AHRS",
    0x7A: "Device",
    0xCC: "Roll reverse",
  };

  static const int _ahrs = 0x4C;

  final ValueNotifier<int> change = ValueNotifier<int>(0);
  // bumped when the message log changes (separate so the list and the status
  // tiles can rebuild independently)
  final ValueNotifier<int> logChange = ValueNotifier<int>(0);
  final GroundStationCache _groundStations = GroundStationCache();

  // Message types currently shown in the log. AHRS is off by default because it
  // arrives many times per second and would crowd out everything else.
  final Set<int> enabledTypes =
      filterTypes.keys.where((t) => t != _ahrs).toSet();

  // received messages, oldest first; use messages() for newest first
  final List<AdsbLogEntry> _log = [];
  bool logPaused = false;

  int _lastMsHeartbeat = 0; // 0 => never received a heartbeat
  bool gpsValid = false;
  bool utcOk = false;
  bool uatInitialized = false;

  // connected when a heartbeat arrived recently enough
  bool get connected => _lastMsHeartbeat != 0 &&
      (DateTime.now().millisecondsSinceEpoch - _lastMsHeartbeat) < _staleMs;

  // ground stations (towers) currently being received
  int get towerCount => _groundStations.count();

  void setHeartbeat(HeartbeatMessage m) {
    _lastMsHeartbeat = DateTime.now().millisecondsSinceEpoch;
    gpsValid = m.gpsValid;
    utcOk = m.utcOk;
    uatInitialized = m.uatInitialized;
    change.value++;
  }

  void reportGroundStation(LatLng coordinates) {
    if(_groundStations.put(coordinates)) {
      change.value++; // a newly heard tower changes the displayed count
    }
  }

  // Whether a message type should be logged/shown. Unknown types (not in the
  // filter list) are always allowed; known types follow the filter selection.
  bool _typeShown(int typeId) =>
      !filterTypes.containsKey(typeId) || enabledTypes.contains(typeId);

  // Record a received GDL90 message for the log. Skipped while paused or when
  // its type is filtered out (this is what keeps frequent AHRS messages from
  // flooding the limited buffer).
  void logMessage(int typeId, String type, String summary, String decoded, String raw) {
    if(logPaused || !_typeShown(typeId)) {
      return;
    }
    _log.add(AdsbLogEntry(DateTime.now(), typeId, type, summary, decoded, raw));
    if(_log.length > _maxLog) {
      _log.removeAt(0);
    }
    logChange.value++;
  }

  // Received messages, newest first, honoring the current type filter.
  List<AdsbLogEntry> messages() =>
      _log.reversed.where((e) => _typeShown(e.typeId)).toList();

  // Enable/disable a message type in the log filter.
  void setTypeEnabled(int typeId, bool enabled) {
    if(enabled) {
      enabledTypes.add(typeId);
    }
    else {
      enabledTypes.remove(typeId);
    }
    logChange.value++;
  }

  void toggleLogPaused() {
    logPaused = !logPaused;
    logChange.value++;
  }
}
