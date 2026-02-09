import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';

import 'package:avaremp/place/elevation_cache.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';
import 'package:universal_io/io.dart';

class SyntheticVisionQuad {
  final double leftX;
  final double rightX;
  final double nearLeftAngleDeg;
  final double nearRightAngleDeg;
  final double farRightAngleDeg;
  final double farLeftAngleDeg;
  final Color color;

  const SyntheticVisionQuad({
    required this.leftX,
    required this.rightX,
    required this.nearLeftAngleDeg,
    required this.nearRightAngleDeg,
    required this.farRightAngleDeg,
    required this.farLeftAngleDeg,
    required this.color,
  });
}

class SyntheticVisionFrame {
  final List<SyntheticVisionQuad> quads;
  final bool hasTerrain;
  final DateTime generatedAt;

  const SyntheticVisionFrame({
    required this.quads,
    required this.hasTerrain,
    required this.generatedAt,
  });

  factory SyntheticVisionFrame.empty() {
    return SyntheticVisionFrame(
      quads: const <SyntheticVisionQuad>[],
      hasTerrain: false,
      generatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class SyntheticVisionController {
  static const double _fovDegrees = 90;
  static const int _lateralBands = 20;
  static const int _minimumRefreshMs = 1200;
  static const double _movementRefreshMeters = 60;
  static const double _headingRefreshDegrees = 2.5;
  static const List<double> _distanceBandsNm = <double>[
    0.20,
    0.35,
    0.55,
    0.80,
    1.10,
    1.50,
    2.00,
    2.60,
    3.30,
    4.20,
    5.50,
    7.00,
    8.00,
  ];

  final ValueNotifier<SyntheticVisionFrame> frame = ValueNotifier<SyntheticVisionFrame>(SyntheticVisionFrame.empty());

  final _OsmTileTextureSampler _osmSampler = _OsmTileTextureSampler();
  final Distance _distance = const Distance(calculator: Haversine());

  bool _building = false;
  bool _pending = false;
  bool _disposed = false;
  Position? _pendingPosition;
  double _pendingHeadingTrue = 0;
  int _lastRefreshMs = 0;
  LatLng? _lastRefreshLatLng;
  double _lastHeadingTrue = 0;

  void dispose() {
    _disposed = true;
    frame.dispose();
    _osmSampler.dispose();
  }

  void requestRefresh({
    required Position position,
    required double gpsHeadingTrue,
    required double ahrsHeadingMagnetic,
    required double magneticVariation,
    required bool preferAhrsHeading,
  }) {
    if (_disposed) {
      return;
    }

    final double headingTrue = _resolveHeadingTrue(
      gpsHeadingTrue: gpsHeadingTrue,
      ahrsHeadingMagnetic: ahrsHeadingMagnetic,
      magneticVariation: magneticVariation,
      preferAhrsHeading: preferAhrsHeading,
    );

    final LatLng current = LatLng(position.latitude, position.longitude);
    final int now = DateTime.now().millisecondsSinceEpoch;
    final bool staleByTime = (now - _lastRefreshMs) > 5000;

    if (!staleByTime &&
        _lastRefreshLatLng != null &&
        !_isSignificantChange(
          previous: _lastRefreshLatLng!,
          current: current,
          previousHeading: _lastHeadingTrue,
          currentHeading: headingTrue,
        ) &&
        (now - _lastRefreshMs) < _minimumRefreshMs) {
      return;
    }

    _pendingPosition = position;
    _pendingHeadingTrue = headingTrue;
    if (_building) {
      _pending = true;
      return;
    }
    unawaited(_refreshNow());
  }

  bool _isSignificantChange({
    required LatLng previous,
    required LatLng current,
    required double previousHeading,
    required double currentHeading,
  }) {
    final double movementMeters = _distance(previous, current);
    final double headingDiff = _angularDifference(previousHeading, currentHeading);
    return movementMeters >= _movementRefreshMeters || headingDiff >= _headingRefreshDegrees;
  }

  double _resolveHeadingTrue({
    required double gpsHeadingTrue,
    required double ahrsHeadingMagnetic,
    required double magneticVariation,
    required bool preferAhrsHeading,
  }) {
    final double gps = _normalizeHeading(gpsHeadingTrue);
    if (!preferAhrsHeading) {
      return gps;
    }
    final double ahrsTrue = _normalizeHeading(ahrsHeadingMagnetic + magneticVariation);
    if (!ahrsTrue.isFinite) {
      return gps;
    }
    return ahrsTrue;
  }

  double _normalizeHeading(double heading) {
    double normalized = heading % 360;
    if (normalized < 0) {
      normalized += 360;
    }
    return normalized;
  }

  double _angularDifference(double first, double second) {
    final double diff = (first - second).abs();
    return diff > 180 ? 360 - diff : diff;
  }

  Future<void> _refreshNow() async {
    if (_pendingPosition == null || _disposed) {
      return;
    }
    _building = true;
    final Position workingPosition = _pendingPosition!;
    final double headingTrue = _pendingHeadingTrue;
    _pending = false;
    try {
      final SyntheticVisionFrame built = await _buildFrame(workingPosition, headingTrue);
      if (!_disposed) {
        frame.value = built;
        _lastRefreshMs = DateTime.now().millisecondsSinceEpoch;
        _lastRefreshLatLng = LatLng(workingPosition.latitude, workingPosition.longitude);
        _lastHeadingTrue = headingTrue;
      }
    } finally {
      _building = false;
      if (_pending && !_disposed) {
        unawaited(_refreshNow());
      }
    }
  }

  Future<SyntheticVisionFrame> _buildFrame(Position position, double headingTrue) async {
    final LatLng origin = LatLng(position.latitude, position.longitude);
    final double altitudeFt = position.altitude * Storage().units.mToF;
    final double maxDistanceNm = _distanceForAltitude(altitudeFt);
    final List<double> distancesNm = _distanceBandsNm.where((double d) => d < maxDistanceNm).toList();
    if (distancesNm.isEmpty || distancesNm.last < maxDistanceNm) {
      distancesNm.add(maxDistanceNm);
    }
    if (distancesNm.length < 2) {
      return SyntheticVisionFrame.empty();
    }

    final List<double> bearings = List<double>.generate(
      _lateralBands + 1,
      (int i) => (-_fovDegrees / 2) + i * (_fovDegrees / _lateralBands),
    );

    final List<LatLng> samplePoints = <LatLng>[];
    for (final double distanceNm in distancesNm) {
      for (final double relativeBearing in bearings) {
        samplePoints.add(_offset(origin, distanceNm, headingTrue + relativeBearing));
      }
    }

    final List<double?> elevations = await ElevationCache.getElevationOfPoints(samplePoints);
    final bool hasTerrain = elevations.any((double? e) => e != null);
    if (!hasTerrain) {
      return SyntheticVisionFrame.empty();
    }

    final int textureZoom = _textureZoomForAltitude(altitudeFt);
    final List<SyntheticVisionQuad> quads = <SyntheticVisionQuad>[];

    int pointIndex(int distanceIndex, int bearingIndex) {
      return distanceIndex * bearings.length + bearingIndex;
    }

    for (int distanceIndex = distancesNm.length - 2; distanceIndex >= 0; distanceIndex--) {
      final double nearDistanceNm = distancesNm[distanceIndex];
      final double farDistanceNm = distancesNm[distanceIndex + 1];
      for (int bearingIndex = 0; bearingIndex < bearings.length - 1; bearingIndex++) {
        final int nearLeftIndex = pointIndex(distanceIndex, bearingIndex);
        final int nearRightIndex = pointIndex(distanceIndex, bearingIndex + 1);
        final int farLeftIndex = pointIndex(distanceIndex + 1, bearingIndex);
        final int farRightIndex = pointIndex(distanceIndex + 1, bearingIndex + 1);

        final double nearLeftElevation = elevations[nearLeftIndex] ?? 0;
        final double nearRightElevation = elevations[nearRightIndex] ?? 0;
        final double farLeftElevation = elevations[farLeftIndex] ?? 0;
        final double farRightElevation = elevations[farRightIndex] ?? 0;

        final double nearLeftAngle = _terrainAngleDegrees(nearLeftElevation, altitudeFt, nearDistanceNm);
        final double nearRightAngle = _terrainAngleDegrees(nearRightElevation, altitudeFt, nearDistanceNm);
        final double farLeftAngle = _terrainAngleDegrees(farLeftElevation, altitudeFt, farDistanceNm);
        final double farRightAngle = _terrainAngleDegrees(farRightElevation, altitudeFt, farDistanceNm);

        final double leftX = (bearings[bearingIndex] / (_fovDegrees / 2)) * 100;
        final double rightX = (bearings[bearingIndex + 1] / (_fovDegrees / 2)) * 100;

        final double centerDistanceNm = (nearDistanceNm + farDistanceNm) / 2;
        final double centerBearing = headingTrue + (bearings[bearingIndex] + bearings[bearingIndex + 1]) / 2;
        final LatLng center = _offset(origin, centerDistanceNm, centerBearing);
        final Color? texture = await _osmSampler.sampleColor(center, textureZoom);
        final double centerElevation = (nearLeftElevation + nearRightElevation + farLeftElevation + farRightElevation) / 4;
        final double clearanceFt = altitudeFt - centerElevation;
        final Color color = _terrainColor(
          textureColor: texture,
          clearanceFt: clearanceFt,
          distanceRatio: distanceIndex / (distancesNm.length - 1),
        );

        quads.add(
          SyntheticVisionQuad(
            leftX: leftX,
            rightX: rightX,
            nearLeftAngleDeg: nearLeftAngle,
            nearRightAngleDeg: nearRightAngle,
            farRightAngleDeg: farRightAngle,
            farLeftAngleDeg: farLeftAngle,
            color: color,
          ),
        );
      }
    }

    return SyntheticVisionFrame(
      quads: quads,
      hasTerrain: hasTerrain,
      generatedAt: DateTime.now(),
    );
  }

  double _distanceForAltitude(double altitudeFt) {
    final double horizon = 1.06 * sqrt(max(altitudeFt, 0));
    return horizon.clamp(2.0, 8.0).toDouble();
  }

  int _textureZoomForAltitude(double altitudeFt) {
    if (altitudeFt < 2500) {
      return 15;
    }
    if (altitudeFt < 7000) {
      return 14;
    }
    return 13;
  }

  double _terrainAngleDegrees(double terrainFt, double altitudeFt, double distanceNm) {
    final double distanceFt = max(distanceNm * 6076.12, 250);
    final double angle = atan2(terrainFt - altitudeFt, distanceFt) * 180 / pi;
    return angle.clamp(-45.0, 20.0).toDouble();
  }

  Color _terrainColor({
    required Color? textureColor,
    required double clearanceFt,
    required double distanceRatio,
  }) {
    Color base = textureColor ?? const Color(0xFF3B2D20);
    if (base.red + base.green + base.blue < 80) {
      base = const Color(0xFF403425);
    }

    Color shaded = _shade(base, 1.0 - 0.45 * distanceRatio);
    if (clearanceFt < 500) {
      shaded = _blend(shaded, const Color(0xFFFF4040), 0.60);
    } else if (clearanceFt < 1000) {
      shaded = _blend(shaded, const Color(0xFFF7D452), 0.40);
    }
    return Color.fromARGB(224, shaded.red, shaded.green, shaded.blue);
  }

  Color _shade(Color color, double factor) {
    final double f = factor.clamp(0.3, 1.2).toDouble();
    final int r = ((color.red * f).round()).clamp(0, 255).toInt();
    final int g = ((color.green * f).round()).clamp(0, 255).toInt();
    final int b = ((color.blue * f).round()).clamp(0, 255).toInt();
    return Color.fromARGB(color.alpha, r, g, b);
  }

  Color _blend(Color a, Color b, double t) {
    final double ratio = t.clamp(0, 1).toDouble();
    final int r = ((a.red * (1 - ratio) + b.red * ratio).round()).clamp(0, 255).toInt();
    final int g = ((a.green * (1 - ratio) + b.green * ratio).round()).clamp(0, 255).toInt();
    final int blue = ((a.blue * (1 - ratio) + b.blue * ratio).round()).clamp(0, 255).toInt();
    return Color.fromARGB(a.alpha, r, g, blue);
  }

  LatLng _offset(LatLng from, double distanceNm, double headingDegrees) {
    final double normalizedHeading = headingDegrees % 360 > 180
        ? (headingDegrees % 360) - 360
        : headingDegrees % 360;
    return _distance.offset(from, distanceNm * 1852, normalizedHeading);
  }
}

class _OsmTileTextureSampler {
  static const int _tileSize = 256;
  static const int _maxCachedTiles = 96;
  static const int _retryFailureAfterMs = 2 * 60 * 1000;

  final LinkedHashMap<String, img.Image> _tileCache = LinkedHashMap<String, img.Image>();
  final Map<String, int> _failedTiles = <String, int>{};

  void dispose() {
    _tileCache.clear();
    _failedTiles.clear();
  }

  Future<Color?> sampleColor(LatLng point, int zoom) async {
    final _TileSample sample = _toTileSample(point, zoom);
    final String key = sample.key;
    img.Image? tile = _tileCache.remove(key);
    if (tile == null) {
      final int now = DateTime.now().millisecondsSinceEpoch;
      final int? failedAt = _failedTiles[key];
      if (failedAt != null && (now - failedAt) < _retryFailureAfterMs) {
        return null;
      }
      tile = await _loadTile(sample);
      if (tile == null) {
        _failedTiles[key] = now;
        return null;
      }
      _failedTiles.remove(key);
    }

    _tileCache[key] = tile;
    if (_tileCache.length > _maxCachedTiles) {
      _tileCache.remove(_tileCache.keys.first);
    }

    final img.Pixel pixel = tile.getPixel(sample.pixelX, sample.pixelY);
    return Color.fromARGB(
      (pixel.a as num).toInt(),
      (pixel.r as num).toInt(),
      (pixel.g as num).toInt(),
      (pixel.b as num).toInt(),
    );
  }

  Future<img.Image?> _loadTile(_TileSample sample) async {
    final String url = "https://tile.openstreetmap.org/${sample.zoom}/${sample.tileX}/${sample.tileY}.png";
    try {
      final FileInfo? cached = await FileCacheManager().mapCacheManager.getFileFromCache(url);
      final File file = cached?.file ?? await FileCacheManager().mapCacheManager.getSingleFile(url, key: url);
      final Uint8List bytes = await file.readAsBytes();
      return img.decodeImage(bytes);
    } catch (_) {
      return null;
    }
  }

  _TileSample _toTileSample(LatLng point, int zoom) {
    final double latitude = point.latitude.clamp(-85.05112878, 85.05112878).toDouble();
    final double longitude = point.longitude;
    final double latRadians = latitude * pi / 180;
    final int tilesPerAxis = 1 << zoom;

    final double x = ((longitude + 180) / 360) * tilesPerAxis;
    final double mercator = log(tan(pi / 4 + latRadians / 2));
    final double y = (1 - mercator / pi) / 2 * tilesPerAxis;

    int tileX = x.floor();
    int tileY = y.floor();
    tileX = tileX % tilesPerAxis;
    if (tileX < 0) {
      tileX += tilesPerAxis;
    }
    tileY = tileY.clamp(0, tilesPerAxis - 1).toInt();

    final int pixelX = ((x - x.floor()) * _tileSize).floor().clamp(0, _tileSize - 1).toInt();
    final int pixelY = ((y - y.floor()) * _tileSize).floor().clamp(0, _tileSize - 1).toInt();

    return _TileSample(
      zoom: zoom,
      tileX: tileX,
      tileY: tileY,
      pixelX: pixelX,
      pixelY: pixelY,
    );
  }
}

class _TileSample {
  final int zoom;
  final int tileX;
  final int tileY;
  final int pixelX;
  final int pixelY;

  const _TileSample({
    required this.zoom,
    required this.tileX,
    required this.tileY,
    required this.pixelX,
    required this.pixelY,
  });

  String get key => "$zoom/$tileX/$tileY";
}
