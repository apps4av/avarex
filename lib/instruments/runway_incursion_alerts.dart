import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:latlong2/latlong.dart';

/// Runway Incursion Alert System
/// Alerts when aircraft is about to enter a runway while taxiing
class RunwayIncursionAlerts {
  static RunwayIncursionAlerts? _instance;

  final AssetSource _enteringRunwayAudio = AssetSource("approaching_runway.mp3");

  // Configuration constants
  static const double _distanceThresholdFeet = 20.0;
  static const double _feetToNauticalMiles = 1.0 / 6076.12; // 1 nm = 6076.12 feet
  static const double _distanceThresholdNm = _distanceThresholdFeet * _feetToNauticalMiles;
  
  static const double _minSpeedKnots = 2.0;   // Must be moving
  static const double _maxSpeedKnots = 20.0;  // Must be taxiing (not airborne)
  static const double _headingToleranceDeg = 60.0; // Heading must be within this angle of runway
  static const int _cooldownMs = 30000; // 30 second cooldown per runway

  bool _isRunning = false;
  bool _isPlaying = false;
  bool _isChecking = false;

  final AudioPlayer _audioPlayer = AudioPlayer();
  static AudioCache? _cache;

  final Map<String, int> _lastAlertTime = {};
  final Completer<RunwayIncursionAlerts> _startupCompleter = Completer();

  RunwayIncursionAlerts._();

  static Future<RunwayIncursionAlerts?> getAndStartRunwayIncursionAlerts() async {
    if (_instance == null) {
      _instance = RunwayIncursionAlerts._();
      await _instance?._loadAudio();
      _instance?._isRunning = true;
      _instance?._startupCompleter.complete(_instance);
    }
    return _instance?._startupCompleter.future;
  }

  static Future<void> stopRunwayIncursionAlerts() async {
    if (_instance != null) {
      _instance?._isRunning = false;
      _instance?._isPlaying = false;
      _instance?._isChecking = false;
      await _instance?._audioPlayer.stop();
      _instance = null;
    }
  }

  Future<void> _loadAudio() async {
    _cache ??= AudioCache(prefix: "assets/audio/runway_incursion/");
    _audioPlayer.audioCache = _cache!;
    _audioPlayer.setReleaseMode(ReleaseMode.stop);
    try {
      await _cache!.load(_enteringRunwayAudio.path);
    } catch (e) {
      // Audio file may not exist
    }
  }

  /// Check if aircraft is about to enter a runway
  Future<void> checkRunwayIncursion({
    required LatLng currentPosition,
    required double heading,
    required double groundSpeedMps,
    required AirportDestination? airport,
  }) async {
    if (!_isRunning || airport == null || _isChecking) {
      return;
    }

    // Convert m/s to knots
    final double speedKnots = groundSpeedMps * 1.94384;

    // Must be taxiing (moving but not airborne)
    if (speedKnots < _minSpeedKnots || speedKnots > _maxSpeedKnots) {
      return;
    }

    _isChecking = true;

    try {
      final GeoCalculations geo = GeoCalculations();

      for (final runway in airport.runways) {
        // Check both ends of runway
        _checkThreshold(geo, currentPosition, heading, runway, 'LE');
        _checkThreshold(geo, currentPosition, heading, runway, 'HE');
      }
    } finally {
      _isChecking = false;
    }
  }

  void _checkThreshold(
    GeoCalculations geo,
    LatLng position,
    double heading,
    Map<String, dynamic> runway,
    String side,
  ) {
    try {
      final String? latStr = runway['${side}Latitude'];
      final String? lonStr = runway['${side}Longitude'];
      final String? ident = runway['${side}Ident'];

      if (latStr == null || lonStr == null || ident == null) return;
      if (latStr.isEmpty || lonStr.isEmpty || ident.isEmpty) return;

      final double thresholdLat = double.parse(latStr);
      final double thresholdLon = double.parse(lonStr);
      final LatLng threshold = LatLng(thresholdLat, thresholdLon);

      // Calculate distance to threshold (in nautical miles)
      final double distanceNm = geo.calculateDistance(position, threshold);

      // Check if within 20 feet
      if (distanceNm > _distanceThresholdNm) return;

      // Get runway heading from opposite end
      final String oppSide = side == 'LE' ? 'HE' : 'LE';
      final String? oppLatStr = runway['${oppSide}Latitude'];
      final String? oppLonStr = runway['${oppSide}Longitude'];

      double runwayHeading;
      if (oppLatStr != null && oppLonStr != null && 
          oppLatStr.isNotEmpty && oppLonStr.isNotEmpty) {
        final LatLng oppEnd = LatLng(double.parse(oppLatStr), double.parse(oppLonStr));
        runwayHeading = geo.calculateBearing(threshold, oppEnd);
      } else {
        // Estimate from runway identifier
        final String numPart = ident.replaceAll(RegExp(r'[LCRW]'), '');
        runwayHeading = (double.tryParse(numPart) ?? 0) * 10;
      }

      // Check if aircraft heading is aligned with runway (entering it)
      double headingDiff = (heading - runwayHeading).abs();
      if (headingDiff > 180) headingDiff = 360 - headingDiff;
      
      if (headingDiff > _headingToleranceDeg) return;

      // Check if moving towards threshold
      final double bearingToThreshold = geo.calculateBearing(position, threshold);
      double movementDiff = (heading - bearingToThreshold).abs();
      if (movementDiff > 180) movementDiff = 360 - movementDiff;

      if (movementDiff > 90) return; // Moving away from threshold

      // All conditions met - trigger alert
      _triggerAlert(ident);

    } catch (e) {
      // Skip on parse error
    }
  }

  void _triggerAlert(String runwayIdent) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int? lastTime = _lastAlertTime[runwayIdent];

    // Check cooldown
    if (lastTime != null && (now - lastTime) < _cooldownMs) return;
    if (_isPlaying) return;

    _lastAlertTime[runwayIdent] = now;
    _isPlaying = true;

    _audioPlayer.play(_enteringRunwayAudio).then((_) {
      _audioPlayer.onPlayerComplete.first.then((_) {
        _isPlaying = false;
      });
    }).catchError((e) {
      _isPlaying = false;
    });
  }

  bool get isRunning => _isRunning;
}
