import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:avaremp/place/elevation_cache.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:latlong2/latlong.dart';

/// Ground Proximity Warning System (GPWS) alerts
/// Monitors terrain ahead in direction of flight and predicts collisions
/// if current trajectory is maintained for a specified lookahead time
class GpwsAlerts {
  static GpwsAlerts? _instance;

  // Audio assets for GPWS alerts
  final AssetSource _pullUpAudio = AssetSource("gpws_pull_up.mp3");
  final AssetSource _terrainAudio = AssetSource("gpws_terrain.mp3");

  // GPWS configuration (units from GeoCalculations conversion functions)
  static const double warningAltitude = 100.0; // AGL threshold (immediate proximity)
  static const double terrainBuffer = 500.0; // Buffer above terrain for collision prediction
  static const int warningSpeed = 30; // Minimum ground speed to trigger alerts
  static const double lookaheadMinutes = 3.0; // How far ahead to look for terrain conflicts
  static const int samplePoints = 12; // Number of points to sample along projected path

  bool _isRunning = false;
  bool _isPlaying = false;
  bool _isCheckingTerrain = false; // Prevent concurrent terrain checks

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
      _instance?._isCheckingTerrain = false;
      await _instance?._audioPlayer.stop();
      _instance = null;
    }
  }

  Future<void> _loadAudio() async {
    _cache ??= AudioCache(prefix: "assets/audio/gpws/");
    _audioPlayer.audioCache = _cache!;
    _audioPlayer.setReleaseMode(ReleaseMode.stop);

    // Pre-cache the audio assets
    try {
      await _cache!.load(_pullUpAudio.path);
      await _cache!.load(_terrainAudio.path);
    } catch (e) {
      // Audio files may not exist yet - user needs to add them
    }
  }

  /// Check altitude and terrain ahead, trigger GPWS alert if needed
  /// Called periodically from the main timer loop
  ///
  /// [currentPosition] - Current aircraft position (lat/lng)
  /// [altitude] - Current GPS altitude (converted via GeoCalculations)
  /// [groundElevation] - Ground elevation at current position (converted via GeoCalculations)
  /// [groundSpeed] - Ground speed (converted via GeoCalculations)
  /// [heading] - Current track/heading in degrees true
  Future<void> checkTerrainAhead({
    required LatLng currentPosition,
    required double altitude,
    required double? groundElevation,
    required double groundSpeed,
    required double heading,
  }) async {
    if (!_isRunning) {
      return;
    }

    // Don't alert if moving slowly (likely on ground or taxiing)
    if (groundSpeed < warningSpeed) {
      return;
    }

    // Check immediate proximity first (original GPWS behavior)
    if (groundElevation != null) {
      final double agl = altitude - groundElevation;
      if (agl < warningAltitude) {
        _triggerPullUpAlert();
        return;
      }
    }

    // Prevent concurrent terrain checks (they're async and could pile up)
    if (_isCheckingTerrain) {
      return;
    }
    _isCheckingTerrain = true;

    try {
      // Check terrain ahead in direction of flight
      final bool collisionPredicted = await _checkForwardTerrain(
        currentPosition: currentPosition,
        altitude: altitude,
        groundSpeed: groundSpeed,
        heading: heading,
      );

      if (collisionPredicted) {
        _triggerTerrainAlert();
      }
    } finally {
      _isCheckingTerrain = false;
    }
  }

  /// Project aircraft position forward and check for terrain conflicts
  /// Returns true if terrain collision is predicted within lookahead time
  /// Assumes constant altitude (current altitude maintained throughout)
  Future<bool> _checkForwardTerrain({
    required LatLng currentPosition,
    required double altitude,
    required double groundSpeed,
    required double heading,
  }) async {
    final GeoCalculations geo = GeoCalculations();

    // Calculate total distance covered in lookahead time
    // Speed is in user's preferred units per hour, time is in minutes
    final double totalDistance = groundSpeed * (lookaheadMinutes / 60.0);

    // Generate sample points along the projected flight path
    final List<LatLng> samplePositions = [];

    for (int i = 1; i <= samplePoints; i++) {
      // Distance to this sample point
      final double distance = (totalDistance / samplePoints) * i;

      // Calculate projected position (GeoCalculations handles unit conversion)
      final LatLng projectedPosition = geo.calculateOffset(
        currentPosition,
        distance,
        heading,
      );
      samplePositions.add(projectedPosition);
    }

    // Get terrain elevations at all sample points
    final List<double?> terrainElevations =
        await ElevationCache.getElevationOfPoints(samplePositions);

    // Check each sample point for terrain conflict
    double? previousTerrainElevation;
    for (int i = 0; i < samplePoints; i++) {
      final double? terrainElevation = terrainElevations[i];
      if (terrainElevation == null) {
        previousTerrainElevation = null;
        continue;
      }

      // Check if terrain is rising in direction of flight
      final bool terrainRising = previousTerrainElevation != null &&
          terrainElevation > previousTerrainElevation;

      // Calculate clearance above terrain (assuming constant altitude)
      final double clearance = altitude - terrainElevation;

      // Alert if:
      // 1. Terrain is rising ahead AND we'll be below the safety buffer, OR
      // 2. We'll collide with terrain (clearance <= 0)
      if (clearance <= 0 || (terrainRising && clearance < terrainBuffer)) {
        return true; // Collision predicted
      }

      previousTerrainElevation = terrainElevation;
    }

    return false; // No collision predicted
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

  void _triggerTerrainAlert() {
    if (_isPlaying) {
      return;
    }

    _isPlaying = true;

    _audioPlayer.play(_terrainAudio).then((_) {
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
