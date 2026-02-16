import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

/// Ground Proximity Warning System (GPWS) alerts
/// Monitors AGL (Above Ground Level) and plays audible warnings when altitude is critically low
class GpwsAlerts {
  static GpwsAlerts? _instance;

  // Audio assets for GPWS alerts
  final AssetSource _pullUpAudio = AssetSource("gpws_pull_up.mp3");

  // GPWS configuration
  static const double warningAltitudeFeet = 100.0; // AGL threshold in feet
  static const int warningSpeed = 30;

  bool _isRunning = false;
  bool _isPlaying = false;

  final AudioPlayer _audioPlayer = AudioPlayer();
  static AudioCache? _cache;

  final Completer<GpwsAlerts> _startupCompleter = Completer();

  GpwsAlerts._privateConstructor();

  /// Get or create the GPWS alerts singleton instance
  static Future<GpwsAlerts?> getAndStartGpwsAlerts() async {
    if (_instance == null) {
      _instance = GpwsAlerts._privateConstructor();
      await _instance?._loadAudio();
      _instance?._isRunning = true;
      _instance?._startupCompleter.complete(_instance);
    }
    return _instance?._startupCompleter.future;
  }

  /// Stop GPWS alerts
  static Future<void> stopGpwsAlerts() async {
    if (_instance != null) {
      _instance?._isRunning = false;
      _instance?._isPlaying = false;
      await _instance?._audioPlayer.stop();
      _instance = null;
    }
  }

  Future<void> _loadAudio() async {
    _cache ??= AudioCache(prefix: "assets/audio/gpws/");
    _audioPlayer.audioCache = _cache!;
    _audioPlayer.setReleaseMode(ReleaseMode.stop);

    // Pre-cache the audio asset
    try {
      await _cache!.load(_pullUpAudio.path);
    } catch (e) {
      // Audio file may not exist yet - user needs to add it
    }
  }

  /// Check altitude and trigger GPWS alert if needed
  /// Called periodically from the main timer loop
  ///
  /// [gpsAltitudeFeet] - Current GPS altitude in feet (MSL, geoid corrected)
  /// [groundElevationFeet] - Ground elevation at current position in feet
  /// [groundSpeed] - Ground speed in knots (to avoid alerts when stationary)
  void checkAltitude({
    required double gpsAltitudeFeet,
    required double? groundElevationFeet,
    required double groundSpeed,
  }) {
    if (!_isRunning) {
      return;
    }

    // Don't alert if moving slowly (likely on ground)
    if (groundSpeed < warningSpeed) {
      return;
    }

    // Need valid ground elevation to calculate AGL
    if (groundElevationFeet == null) {
      return;
    }

    // Calculate AGL (Above Ground Level)
    final double aglFeet = gpsAltitudeFeet - groundElevationFeet;

    // Check if below warning threshold
    if (aglFeet < warningAltitudeFeet) {
      _triggerPullUpAlert();
    }
  }

  void _triggerPullUpAlert() {
    if (_isPlaying) {
      return;
    }

    _isPlaying = true;

    _audioPlayer.play(_pullUpAudio).then((_) {
      // Wait for completion
      _audioPlayer.onPlayerComplete.first.then((_) {
        _isPlaying = false;
      });
    }).catchError((e) {
      _isPlaying = false;
    });
  }

  /// Check if GPWS is currently running
  bool get isRunning => _isRunning;
}
