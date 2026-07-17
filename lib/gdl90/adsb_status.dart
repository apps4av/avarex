import 'package:avaremp/gdl90/ground_station_cache.dart';
import 'package:avaremp/gdl90/heartbeat_message.dart';
import 'package:avaremp/gdl90/traffic_report_message.dart';
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
  final TrafficFilter filter; // why a traffic report was dropped (none if shown)
  AdsbLogEntry(this.time, this.typeId, this.type, this.summary, this.decoded, this.raw, {this.filter = TrafficFilter.none});
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
  bool maintRequired = false;
  bool gpsBatteryLow = false;

  // --- Quality/diagnostics counters (help debug ADS-B reception issues) ---
  int totalMessages = 0;               // good GDL90 frames decoded since start/reset
  int crcErrors = 0;                   // frames dropped on CRC check
  int frameErrors = 0;                 // frames too short / malformed before decode
  int parseErrors = 0;                 // exceptions while parsing a decoded frame
  final Map<int, int> typeCounts = {}; // per-message-type received counts
  int filteredOwnshipCount = 0;        // traffic dropped as ownship match
  int filteredRangeCount = 0;          // traffic dropped for being out of range
  int lastUplinkCount = 0;             // uplink msg count from last heartbeat
  int lastTrafficCount = 0;            // traffic msg count from last heartbeat
  int _diagStartMs = DateTime.now().millisecondsSinceEpoch; // for average rate
  int _lastMsTraffic = 0;              // last traffic/basic/long report
  int _lastMsOwnship = 0;              // last ownship report

  // connected when a heartbeat arrived recently enough
  bool get connected => _lastMsHeartbeat != 0 &&
      (DateTime.now().millisecondsSinceEpoch - _lastMsHeartbeat) < _staleMs;

  // ground stations (towers) currently being received
  int get towerCount => _groundStations.count();

  // details of the ground stations currently being received
  List<GroundStation> groundStations() => _groundStations.getStations();

  // seconds since a given event, or -1 if it has never happened.
  int _secondsSince(int ms) => ms == 0
      ? -1
      : ((DateTime.now().millisecondsSinceEpoch - ms) / 1000).floor();
  int get secondsSinceHeartbeat => _secondsSince(_lastMsHeartbeat);
  int get secondsSinceTraffic => _secondsSince(_lastMsTraffic);
  int get secondsSinceOwnship => _secondsSince(_lastMsOwnship);

  // average decoded-message rate since counters were last reset
  double get messagesPerSecond {
    final int elapsedMs = DateTime.now().millisecondsSinceEpoch - _diagStartMs;
    return elapsedMs <= 0 ? 0 : totalMessages * 1000.0 / elapsedMs;
  }

  int typeCount(int typeId) => typeCounts[typeId] ?? 0;

  // Traffic reports across all encodings (traffic + UAT basic/long).
  int get trafficMessageCount =>
      typeCount(0x14) + typeCount(0x1E) + typeCount(0x1F);

  // Zero all diagnostics counters (does not clear the message log).
  void resetDiagnostics() {
    totalMessages = 0;
    crcErrors = 0;
    frameErrors = 0;
    parseErrors = 0;
    typeCounts.clear();
    filteredOwnshipCount = 0;
    filteredRangeCount = 0;
    _diagStartMs = DateTime.now().millisecondsSinceEpoch;
    change.value++;
  }

  void setHeartbeat(HeartbeatMessage m) {
    _lastMsHeartbeat = DateTime.now().millisecondsSinceEpoch;
    gpsValid = m.gpsValid;
    utcOk = m.utcOk;
    uatInitialized = m.uatInitialized;
    maintRequired = m.maintRequired;
    gpsBatteryLow = m.gpsBatteryLow;
    lastUplinkCount = m.uplinkCount;
    lastTrafficCount = m.trafficCount;
    change.value++;
  }

  // Count a CRC failure (frame received but failed integrity check).
  void recordCrcError() {
    crcErrors++;
    change.value++;
  }

  // Count a malformed/short frame that could not be decoded.
  void recordFrameError() {
    frameErrors++;
    change.value++;
  }

  // Count an exception thrown while parsing a decoded frame.
  void recordParseError() {
    parseErrors++;
    change.value++;
  }

  void reportGroundStation(LatLng coordinates, {int slotId = 0, int tisbSiteId = 0}) {
    if(_groundStations.put(coordinates, slotId: slotId, tisbSiteId: tisbSiteId)) {
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
  void logMessage(int typeId, String type, String summary, String decoded, String raw, {TrafficFilter filter = TrafficFilter.none}) {
    // Count every decoded frame for diagnostics, regardless of the display
    // filter/pause (so counters reflect actual reception, not what's shown).
    totalMessages++;
    typeCounts[typeId] = (typeCounts[typeId] ?? 0) + 1;
    final int now = DateTime.now().millisecondsSinceEpoch;
    if(typeId == 0x0A) {
      _lastMsOwnship = now;
    }
    else if(typeId == 0x14 || typeId == 0x1E || typeId == 0x1F) {
      _lastMsTraffic = now;
    }
    if(filter == TrafficFilter.ownship) {
      filteredOwnshipCount++;
    }
    else if(filter == TrafficFilter.range) {
      filteredRangeCount++;
    }

    if(logPaused || !_typeShown(typeId)) {
      return;
    }
    _log.add(AdsbLogEntry(DateTime.now(), typeId, type, summary, decoded, raw, filter: filter));
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
