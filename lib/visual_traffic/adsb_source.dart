import 'package:avaremp/gdl90/traffic_cache.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/visual_traffic/adsb_matcher.dart';

/// This aircraft's GPS fix and the ADS-B traffic around it, as the app has
/// them right now.
class AdsbSnapshot {
  const AdsbSnapshot({required this.ownship, required this.traffic});

  static const AdsbSnapshot none = AdsbSnapshot(ownship: null, traffic: []);

  final OwnshipFix? ownship;
  final List<AdsbTarget> traffic;
}

/// Reads the app's GPS position and traffic list. Kept apart from
/// [AdsbMatcher] so that the matching can be tested without the app.
class AdsbSource {
  static const double _metersToFeet = 3.28084;
  static const double _mpsToKnots = 1.94384;

  static AdsbSnapshot read() {
    try {
      final storage = Storage();
      final position = storage.position;
      final bool hasTrack = position.speed > 0 && !position.heading.isNaN;
      final OwnshipFix ownship = OwnshipFix(
        latitude: position.latitude,
        longitude: position.longitude,
        altitudeFt: position.altitude * _metersToFeet,
        speedKnots: position.speed * _mpsToKnots,
        trackDegrees: hasTrack ? position.heading : null,
      );
      final List<AdsbTarget> traffic = [];
      for (final Traffic t in storage.trafficCache.getTraffic()) {
        final String callSign = t.message.callSign.trim();
        traffic.add(AdsbTarget(
          label: callSign.isNotEmpty
              ? callSign
              : t.message.icao.toRadixString(16).toUpperCase().padLeft(6, '0'),
          latitude: t.message.coordinates.latitude,
          longitude: t.message.coordinates.longitude,
          altitudeFt: t.message.altitude,
          airborne: t.message.airborne,
        ));
      }
      return AdsbSnapshot(ownship: ownship, traffic: traffic);
    } catch (_) {
      // Storage is not ready, or there is no fix yet.
      return AdsbSnapshot.none;
    }
  }
}
