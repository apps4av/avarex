import 'dart:math' as math;

import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class WindVectorLayer extends StatefulWidget {
  const WindVectorLayer({
    super.key,
    required this.mapController,
    required this.color,
    this.forecastHours = 6,
    this.speedMultiplier = 1.0,
    this.lengthMultiplier = 1.0,
    this.altitudeFt,
    this.colorBySpeed = true,
  });

  final MapController mapController;
  final Color color;
  final int forecastHours;
  final double speedMultiplier;
  final double lengthMultiplier;
  final double? altitudeFt;
  final bool colorBySpeed;

  @override
  State<WindVectorLayer> createState() => _WindVectorLayerState();
}

class _WindVectorLayerState extends State<WindVectorLayer>
    with TickerProviderStateMixin {
  static const double _minSpeedKnots = 0.5;
  static const double _maxSpeedKnots = 60;
  static const double _altitudeResetFt = 2000;
  static const double _minAgeSeconds = 2.5;
  static const double _maxAgeSeconds = 6.5;
  static const int _minParticles = 120;
  static const int _maxParticles = 420;
  static const double _pixelsPerSecondPerUnit = 12.0;
  static const double _baseStrokeWidth = 1.8;
  static const double _baseLengthPixels = 16.0;
  static const double _baseAlpha = 0.7;
  static const double _avoidRadiusPixels = 18.0;
  static const double _curlAngleDegrees = 30.0;

  final List<_WindParticle> _particles = [];
  final GeoCalculations _geo = GeoCalculations();
  final math.Random _random = math.Random();

  late final AnimationController _ticker;
  DateTime _lastUpdate = DateTime.now();
  Size _lastSize = Size.zero;
  double _lastAltitudeFt = 0;
  bool _needsReset = true;
  bool _downloadRequested = false;

  @override
  void initState() {
    super.initState();
    _lastAltitudeFt = _effectiveAltitudeFt();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )
      ..addListener(_onTick)
      ..repeat();
    Storage().winds.change.addListener(_onWindsChanged);
  }

  @override
  void didUpdateWidget(covariant WindVectorLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speedMultiplier != widget.speedMultiplier ||
        oldWidget.lengthMultiplier != widget.lengthMultiplier ||
        oldWidget.altitudeFt != widget.altitudeFt ||
        oldWidget.colorBySpeed != widget.colorBySpeed) {
      _needsReset = true;
    }
  }

  @override
  void dispose() {
    Storage().winds.change.removeListener(_onWindsChanged);
    _ticker.dispose();
    super.dispose();
  }

  void _onWindsChanged() {
    _needsReset = true;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      if (size != _lastSize && size.width > 0 && size.height > 0) {
        _lastSize = size;
        _needsReset = true;
      }
      return SizedBox.expand(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: PolylineLayer(
              polylines: _buildPolylines(),
            ),
          ),
        ),
      );
    });
  }

  void _onTick() {
    final now = DateTime.now();
    final dt = now.difference(_lastUpdate).inMilliseconds / 1000.0;
    if (dt <= 0) {
      return;
    }
    _lastUpdate = now;
    if (_lastSize == Size.zero) {
      return;
    }
    if (!_downloadRequested && Storage().winds.getAll().isEmpty) {
      _downloadRequested = true;
      Storage().winds.download();
    }

    final altitudeFt = _effectiveAltitudeFt();
    final bounds = _calculateBounds(_lastSize);

    if (_needsReset ||
        ((altitudeFt - _lastAltitudeFt).abs() >= _altitudeResetFt &&
            _particles.isNotEmpty)) {
      _lastAltitudeFt = altitudeFt;
      _resetParticles(bounds, altitudeFt);
      _needsReset = false;
      setState(() {});
      return;
    }

    _advanceParticles(bounds, altitudeFt, dt);
    setState(() {});
  }

  List<Polyline> _buildPolylines() {
    if (_particles.isEmpty) {
      return const [];
    }
    final unitsPerPixel = _unitsPerPixel();
    final lengthUnits = unitsPerPixel *
        _baseLengthPixels *
        widget.lengthMultiplier.clamp(0.3, 4.0);
    if (lengthUnits <= 0) {
      return const [];
    }
    final List<Polyline> polylines = [];
    for (final particle in _particles) {
      if (particle.speed < _minSpeedKnots) {
        continue;
      }
      final fade = (1.0 - (particle.age / particle.maxAge)).clamp(0.0, 1.0);
      final alpha = (_baseAlpha * fade).clamp(0.1, 1.0);
      final tail = _geo.calculateOffset(
        particle.position,
        lengthUnits,
        (particle.heading + 180) % 360,
      );
      polylines.add(Polyline(
        points: [tail, particle.position],
        strokeWidth: _baseStrokeWidth,
        strokeCap: StrokeCap.round,
        color: particle.baseColor.withValues(alpha: alpha),
      ));
    }
    return polylines;
  }

  void _advanceParticles(LatLngBounds bounds, double altitudeFt, double dt) {
    final unitsPerPixel = _unitsPerPixel();
    final speedMultiplier = widget.speedMultiplier.clamp(0.2, 4.0);
    final avoidRadiusUnits = _avoidRadiusPixels * unitsPerPixel;
    final grid = <int, List<_WindParticle>>{};
    final (cellLatDeg, cellLonDeg) = _gridMetrics(bounds, avoidRadiusUnits);
    for (final particle in _particles) {
      particle.age += dt;
      if (particle.age >= particle.maxAge ||
          !_boundsContains(bounds, particle.position)) {
        _resetParticle(particle, bounds, altitudeFt);
        continue;
      }

      final neighbor = _findNeighbor(
        grid,
        particle.position,
        bounds,
        cellLatDeg,
        cellLonDeg,
        avoidRadiusUnits,
      );
      final heading = _applyCurlHeading(
        particle,
        neighbor,
        avoidRadiusUnits,
      );
      particle.heading = heading;
      final pixelDistance =
          particle.speed * _pixelsPerSecondPerUnit * speedMultiplier * dt;
      final distanceUnits = pixelDistance * unitsPerPixel;
      if (distanceUnits <= 0) {
        particle.age = particle.maxAge;
        continue;
      }
      particle.previousPosition = particle.position;
      particle.position =
          _geo.calculateOffset(particle.position, distanceUnits, heading);
      if (neighbor != null &&
          _geo.calculateDistance(particle.position, neighbor.position) <
              (avoidRadiusUnits * 0.6)) {
        final bearing =
            _geo.calculateBearing(neighbor.position, particle.position);
        final tangent =
            (bearing + (particle.curlBias * 90.0)) % 360.0;
        particle.position = _geo.calculateOffset(
          particle.position,
          avoidRadiusUnits * 0.4,
          tangent,
        );
      }
      if (!_boundsContains(bounds, particle.position)) {
        _resetParticle(particle, bounds, altitudeFt);
      }
      _insertInGrid(
        grid,
        particle,
        bounds,
        cellLatDeg,
        cellLonDeg,
      );
    }
  }

  void _resetParticles(LatLngBounds bounds, double altitudeFt) {
    _particles.clear();
    final targetCount = _targetParticleCount(_lastSize);
    for (int i = 0; i < targetCount; i++) {
      _particles.add(_createParticle(bounds, altitudeFt));
    }
  }

  _WindParticle _createParticle(LatLngBounds bounds, double altitudeFt) {
    final particle = _WindParticle.empty();
    _resetParticle(particle, bounds, altitudeFt);
    return particle;
  }

  void _resetParticle(
    _WindParticle particle,
    LatLngBounds bounds,
    double altitudeFt,
  ) {
    final position = _randomPosition(bounds);
    final sample = _sampleWind(position, altitudeFt);
    final lengthMultiplier = widget.lengthMultiplier.clamp(0.3, 4.0);
    particle
      ..position = position
      ..previousPosition = position
      ..speed = sample.speed
      ..direction = sample.direction
      ..windHeading = (sample.direction + 180) % 360
      ..heading = (sample.direction + 180) % 360
      ..age = 0
      ..maxAge = _lerp(_minAgeSeconds, _maxAgeSeconds, _random.nextDouble()) *
          lengthMultiplier
      ..baseColor = _colorForSpeed(sample.speed)
      ..curlBias = _random.nextBool() ? 1 : -1;
  }

  _WindSample _sampleWind(LatLng position, double altitudeFt) {
    final (wd, ws) =
        WindsCache.getWindsAt(position, altitudeFt, widget.forecastHours);
    if (wd == null || ws == null) {
      return const _WindSample(0, 0);
    }
    return _WindSample(wd, ws);
  }

  LatLngBounds _calculateBounds(Size size) {
    final camera = widget.mapController.camera;
    final topLeft = camera.screenOffsetToLatLng(const Offset(0, 0));
    final topRight = camera.screenOffsetToLatLng(Offset(size.width, 0));
    final bottomLeft = camera.screenOffsetToLatLng(Offset(0, size.height));
    final bottomRight =
        camera.screenOffsetToLatLng(Offset(size.width, size.height));
    final bounds = LatLngBounds(topLeft, bottomRight);
    bounds.extend(topRight);
    bounds.extend(bottomLeft);
    return bounds;
  }

  int _targetParticleCount(Size size) {
    final area = size.width * size.height;
    final count = (area / 8000).round();
    if (count < _minParticles) {
      return _minParticles;
    }
    if (count > _maxParticles) {
      return _maxParticles;
    }
    return count;
  }

  LatLng _randomPosition(LatLngBounds bounds) {
    final lat = _lerp(bounds.south, bounds.north, _random.nextDouble());
    final lon = _randomLongitude(bounds.west, bounds.east);
    return LatLng(lat, lon);
  }

  double _randomLongitude(double west, double east) {
    if (west <= east) {
      return _lerp(west, east, _random.nextDouble());
    }
    final lon = _lerp(west, east + 360, _random.nextDouble());
    return lon > 180 ? lon - 360 : lon;
  }

  bool _boundsContains(LatLngBounds bounds, LatLng position) {
    return position.latitude >= bounds.south &&
        position.latitude <= bounds.north &&
        _longitudeWithin(bounds, position.longitude);
  }

  bool _longitudeWithin(LatLngBounds bounds, double longitude) {
    final west = bounds.west;
    final east = bounds.east;
    if (west <= east) {
      return longitude >= west && longitude <= east;
    }
    return longitude >= west || longitude <= east;
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  Color _colorForSpeed(double speed) {
    if (!widget.colorBySpeed) {
      return widget.color;
    }
    final t = (speed / _maxSpeedKnots).clamp(0.0, 1.0);
    return Color.lerp(Colors.lightBlueAccent, Colors.deepOrangeAccent, t) ??
        widget.color;
  }

  double _effectiveAltitudeFt() {
    final fixedAltitude = widget.altitudeFt;
    if (fixedAltitude != null && fixedAltitude > 0) {
      return fixedAltitude;
    }
    return GeoCalculations.convertAltitude(Storage().position.altitude);
  }

  double _unitsPerPixel() {
    final camera = widget.mapController.camera;
    final center = Offset(_lastSize.width / 2, _lastSize.height / 2);
    final centerLatLng = camera.screenOffsetToLatLng(center);
    final rightLatLng =
        camera.screenOffsetToLatLng(Offset(center.dx + 1, center.dy));
    final units = _geo.calculateDistance(centerLatLng, rightLatLng);
    if (units <= 0) {
      return 0.0001;
    }
    return units;
  }

  (double, double) _gridMetrics(
    LatLngBounds bounds,
    double avoidRadiusUnits,
  ) {
    final centerLat = (bounds.north + bounds.south) / 2;
    final centerLon = _normalizedLongitude(
      (bounds.west + bounds.east) / 2,
      bounds.west,
      bounds.east,
    );
    final center = LatLng(centerLat, centerLon);
    final unitsPerDegLat =
        _geo.calculateDistance(center, LatLng(centerLat + 1, centerLon));
    final unitsPerDegLon =
        _geo.calculateDistance(center, LatLng(centerLat, centerLon + 1));
    final cellLatDeg = (avoidRadiusUnits / (unitsPerDegLat == 0 ? 1 : unitsPerDegLat))
        .clamp(0.01, 5.0);
    final cellLonDeg = (avoidRadiusUnits / (unitsPerDegLon == 0 ? 1 : unitsPerDegLon))
        .clamp(0.01, 5.0);
    return (cellLatDeg, cellLonDeg);
  }

  _WindParticle? _findNeighbor(
    Map<int, List<_WindParticle>> grid,
    LatLng position,
    LatLngBounds bounds,
    double cellLatDeg,
    double cellLonDeg,
    double avoidRadiusUnits,
  ) {
    final cell = _gridCell(position, bounds, cellLatDeg, cellLonDeg);
    _WindParticle? nearest;
    double nearestDistance = double.maxFinite;
    for (int dx = -1; dx <= 1; dx++) {
      for (int dy = -1; dy <= 1; dy++) {
        final key = _gridKey(cell.$1 + dx, cell.$2 + dy);
        final bucket = grid[key];
        if (bucket == null) {
          continue;
        }
        for (final other in bucket) {
          final distance = _geo.calculateDistance(position, other.position);
          if (distance < avoidRadiusUnits && distance < nearestDistance) {
            nearestDistance = distance;
            nearest = other;
          }
        }
      }
    }
    return nearest;
  }

  double _applyCurlHeading(
    _WindParticle particle,
    _WindParticle? neighbor,
    double avoidRadiusUnits,
  ) {
    final baseHeading = particle.windHeading;
    if (neighbor == null) {
      return baseHeading;
    }
    final distance =
        _geo.calculateDistance(particle.position, neighbor.position);
    final factor = (1.0 - (distance / avoidRadiusUnits)).clamp(0.0, 1.0);
    if (factor <= 0) {
      return baseHeading;
    }
    final bearing =
        _geo.calculateBearing(neighbor.position, particle.position);
    final tangent = (bearing + (particle.curlBias * 90.0)) % 360.0;
    final curlHeading = _lerpAngle(baseHeading, tangent, factor);
    final finalHeading =
        (curlHeading + particle.curlBias * _curlAngleDegrees * factor) % 360.0;
    return finalHeading < 0 ? finalHeading + 360.0 : finalHeading;
  }

  void _insertInGrid(
    Map<int, List<_WindParticle>> grid,
    _WindParticle particle,
    LatLngBounds bounds,
    double cellLatDeg,
    double cellLonDeg,
  ) {
    final cell =
        _gridCell(particle.position, bounds, cellLatDeg, cellLonDeg);
    final key = _gridKey(cell.$1, cell.$2);
    final bucket = grid.putIfAbsent(key, () => <_WindParticle>[]);
    bucket.add(particle);
  }

  (int, int) _gridCell(
    LatLng position,
    LatLngBounds bounds,
    double cellLatDeg,
    double cellLonDeg,
  ) {
    final lat = position.latitude;
    final lon = _normalizedLongitude(position.longitude, bounds.west, bounds.east);
    final westNorm = bounds.west;
    final latIndex = ((lat - bounds.south) / cellLatDeg).floor();
    final lonIndex = ((lon - westNorm) / cellLonDeg).floor();
    return (latIndex, lonIndex);
  }

  double _normalizedLongitude(double lon, double west, double east) {
    if (west <= east) {
      return lon;
    }
    if (lon < west) {
      return lon + 360;
    }
    return lon;
  }

  int _gridKey(int x, int y) {
    return (x * 73856093) ^ (y * 19349663);
  }

  double _lerpAngle(double a, double b, double t) {
    final diff = ((b - a + 540) % 360) - 180;
    return (a + diff * t + 360) % 360;
  }
}

class _WindParticle {
  _WindParticle.empty()
      : position = const LatLng(0, 0),
        previousPosition = const LatLng(0, 0),
        speed = 0,
        direction = 0,
        windHeading = 0,
        heading = 0,
        curlBias = 1,
        age = 0,
        maxAge = 1,
        baseColor = Colors.lightBlueAccent;

  LatLng position;
  LatLng previousPosition;
  double speed;
  double direction;
  double windHeading;
  double heading;
  int curlBias;
  double age;
  double maxAge;
  Color baseColor;
}

class _WindSample {
  const _WindSample(this.direction, this.speed);

  final double direction;
  final double speed;
}
