import 'package:avaremp/gdl90/ground_station_cache.dart';
import 'package:avaremp/gdl90/heartbeat_message.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Holds live ADS-B receiver status. GDL90 heartbeat and FIS-B uplink messages
/// post to this directly (the same way traffic reports post to TrafficCache).
class AdsbStatus {

  static const int _staleMs = 5000; // no heartbeat for this long => disconnected

  final ValueNotifier<int> change = ValueNotifier<int>(0);
  final GroundStationCache _groundStations = GroundStationCache();

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
}
