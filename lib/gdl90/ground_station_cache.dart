import 'package:latlong2/latlong.dart';

/// Tracks FIS-B ground uplink stations (ADS-B "towers") that have been heard.
///
/// Each FIS-B uplink frame carries the position of the transmitting ground
/// station. We bucket stations by a coarse lat/lon key so that small position
/// jitter from the same tower is treated as one station, and we expire entries
/// that have not been heard recently so the count reflects current reception.
class GroundStation {
  final LatLng coordinates;
  int lastSeenMs;
  int slotId;      // UAT ground-station broadcast slot (0-31)
  int tisbSiteId;  // TIS-B site ID (0 = no TIS-B service from this station)
  GroundStation(this.coordinates, this.lastSeenMs, {this.slotId = 0, this.tisbSiteId = 0});
}

class GroundStationCache {

  // stations stay "received" for this long after the last frame from them
  static const int _expiryMs = 60 * 1000;
  // round position to ~0.01 deg (~0.6 NM) so the same tower keys consistently
  static const double _keyResolution = 100;

  final Map<String, GroundStation> _stations = {};

  String _keyFor(LatLng c) {
    int lat = (c.latitude * _keyResolution).round();
    int lon = (c.longitude * _keyResolution).round();
    return "$lat,$lon";
  }

  /// Record a ground station heard at [coordinates]. Returns true if this is a
  /// newly heard station (not currently in the cache).
  bool put(LatLng coordinates, {int slotId = 0, int tisbSiteId = 0}) {
    int now = DateTime.now().millisecondsSinceEpoch;
    String key = _keyFor(coordinates);
    bool isNew = !_stations.containsKey(key);
    _stations[key] =
        GroundStation(coordinates, now, slotId: slotId, tisbSiteId: tisbSiteId);
    return isNew;
  }

  void _expire() {
    int now = DateTime.now().millisecondsSinceEpoch;
    _stations.removeWhere((key, s) => (now - s.lastSeenMs) > _expiryMs);
  }

  /// Number of distinct ground stations heard within the expiry window.
  int count() {
    _expire();
    return _stations.length;
  }

  List<GroundStation> getStations() {
    _expire();
    return _stations.values.toList();
  }

  void clear() {
    _stations.clear();
  }
}
