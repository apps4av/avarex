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
  });

  final MapController mapController;
  final Color color;
  final int forecastHours;

  @override
  State<WindVectorLayer> createState() => _WindVectorLayerState();
}

class _WindVectorLayerState extends State<WindVectorLayer>
    with TickerProviderStateMixin {
  static const double _speedScale = 6.0;
  static const double _minAgeSeconds = 2.5;
  static const double _maxAgeSeconds = 6.5;
  static const int _minParticles = 80;
  static const int _maxParticles = 360;

  final math.Random _random = math.Random();
  final GeoCalculations _geo = GeoCalculations();
  final List<_WindParticle> _particles = [];
  late final AnimationController _ticker;
  LatLngBounds? _bounds;
  Size? _viewSize;
  double _lastTickSeconds = 0;
  LatLng? _lastCenter;
  double? _lastZoom;
  bool _needsReset = true;

  @override
  void initState() {
    super.initState();
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(days: 365),
    )
      ..addListener(_onTick)
      ..forward();
    Storage().winds.change.addListener(_onWindsChanged);
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

  void _onTick() {
    final elapsed = _ticker.lastElapsedDuration;
    if (elapsed == null) {
      return;
    }
    final now = elapsed.inMilliseconds / 1000.0;
    final dt = now - _lastTickSeconds;
    if (dt <= 0) {
      return;
    }
    _lastTickSeconds = now;
    _advanceParticles(dt);
  }

  void _advanceParticles(double dt) {
    if (_viewSize == null) {
      return;
    }
    final camera = widget.mapController.camera;
    if (_bounds == null || _cameraChanged(camera)) {
      _needsReset = true;
    }
    if (_needsReset) {
      _resetParticles(camera);
      _needsReset = false;
    }

    final altitude =
        GeoCalculations.convertAltitude(Storage().position.altitude);
    for (final particle in _particles) {
      particle.age += dt;
      if (particle.age >= particle.maxAge ||
          !_bounds!.contains(particle.position)) {
        _resetParticle(particle, altitude);
        continue;
      }

      final speedUnits = particle.speed * Storage().units.knotsTo;
      if (speedUnits <= 0) {
        particle.previous = particle.position;
        continue;
      }

      final distance = speedUnits * dt / 3600.0 * _speedScale;
      if (distance <= 0) {
        particle.previous = particle.position;
        continue;
      }

      particle.previous = particle.position;
      final heading = (particle.direction + 180.0) % 360.0;
      particle.position =
          _geo.calculateOffset(particle.position, distance, heading);
    }
  }

  bool _cameraChanged(MapCamera camera) {
    final center = camera.center;
    final zoom = camera.zoom;
    if (_lastCenter == null || _lastZoom == null) {
      _lastCenter = center;
      _lastZoom = zoom;
      return true;
    }
    final moved = (center.latitude - _lastCenter!.latitude).abs() > 0.02 ||
        (center.longitude - _lastCenter!.longitude).abs() > 0.02 ||
        (zoom - _lastZoom!).abs() > 0.1;
    if (moved) {
      _lastCenter = center;
      _lastZoom = zoom;
    }
    return moved;
  }

  void _resetParticles(MapCamera camera) {
    final size = _viewSize;
    if (size == null) {
      return;
    }
    _bounds = _calculateBounds(camera, size);
    final targetCount = _particleTarget(size);
    if (_particles.length != targetCount) {
      _particles
        ..clear()
        ..addAll(List.generate(targetCount, (_) => _WindParticle.empty()));
    }
    final altitude =
        GeoCalculations.convertAltitude(Storage().position.altitude);
    for (final particle in _particles) {
      _resetParticle(particle, altitude);
    }
  }

  LatLngBounds _calculateBounds(MapCamera camera, Size size) {
    final topLeft = camera.screenOffsetToLatLng(const Offset(0, 0));
    final topRight = camera.screenOffsetToLatLng(Offset(size.width, 0));
    final bottomLeft = camera.screenOffsetToLatLng(Offset(0, size.height));
    final bottomRight =
        camera.screenOffsetToLatLng(Offset(size.width, size.height));
    return LatLngBounds.fromPoints(
      [topLeft, topRight, bottomLeft, bottomRight],
    );
  }

  int _particleTarget(Size size) {
    final area = size.width * size.height;
    final target = (area / 7000).round();
    if (target < _minParticles) {
      return _minParticles;
    }
    if (target > _maxParticles) {
      return _maxParticles;
    }
    return target;
  }

  void _resetParticle(_WindParticle particle, double altitude) {
    final bounds = _bounds;
    if (bounds == null) {
      return;
    }
    final lat = _randomRange(bounds.south, bounds.north);
    final lon = _randomLongitude(bounds.west, bounds.east);
    final position = LatLng(lat, lon);
    final (dir, speed) =
        WindsCache.getWindsAt(position, altitude, widget.forecastHours);
    particle
      ..position = position
      ..previous = position
      ..direction = dir ?? _random.nextDouble() * 360.0
      ..speed = speed ?? 0.0
      ..age = 0.0
      ..maxAge = _randomAge();
  }

  double _randomRange(double min, double max) {
    return min + _random.nextDouble() * (max - min);
  }

  double _randomLongitude(double west, double east) {
    if (west <= east) {
      return _randomRange(west, east);
    }
    // Dateline wrap.
    final span = (180 - west) + (east + 180);
    final offset = _random.nextDouble() * span;
    final lon = west + offset;
    return lon > 180 ? lon - 360 : lon;
  }

  double _randomAge() {
    return _minAgeSeconds +
        _random.nextDouble() * (_maxAgeSeconds - _minAgeSeconds);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (_viewSize == null || _viewSize != size) {
          _viewSize = size;
          _needsReset = true;
        }
        return CustomPaint(
          painter: _WindVectorPainter(
            particles: _particles,
            mapController: widget.mapController,
            color: widget.color,
            repaint: _ticker!,
          ),
          size: size,
          isComplex: true,
          willChange: true,
        );
      },
    );
  }
}

class _WindVectorPainter extends CustomPainter {
  _WindVectorPainter({
    required this.particles,
    required this.mapController,
    required this.color,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final List<_WindParticle> particles;
  final MapController mapController;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (particles.isEmpty) {
      return;
    }

    final camera = mapController.camera;
    final rotationRad = camera.rotation * math.pi / 180.0;
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    for (final particle in particles) {
      if (particle.speed <= 0) {
        continue;
      }
      final head = _project(camera, particle.position, center, rotationRad);
      final tail = _project(camera, particle.previous, center, rotationRad);
      if (!_isOnScreen(head, size) && !_isOnScreen(tail, size)) {
        continue;
      }
      final ageFactor =
          (1.0 - (particle.age / particle.maxAge)).clamp(0.0, 1.0);
      final speedFactor = (particle.speed / 50.0).clamp(0.2, 1.0);
      final alpha =
          (color.opacity * ageFactor * speedFactor).clamp(0.05, 1.0);
      paint.color = color.withAlpha((alpha * 255).round());
      canvas.drawLine(tail, head, paint);
    }
  }

  Offset _project(
    MapCamera camera,
    LatLng latLng,
    Offset center,
    double rotationRad,
  ) {
    final projected = camera.project(latLng);
    final origin = camera.pixelOrigin;
    final x = projected.x - origin.x;
    final y = projected.y - origin.y;
    var offset = Offset(x.toDouble(), y.toDouble());
    if (rotationRad != 0) {
      offset = _rotate(offset, rotationRad, center);
    }
    return offset;
  }

  Offset _rotate(Offset point, double radians, Offset center) {
    final sinA = math.sin(radians);
    final cosA = math.cos(radians);
    final dx = point.dx - center.dx;
    final dy = point.dy - center.dy;
    return Offset(
      center.dx + dx * cosA - dy * sinA,
      center.dy + dx * sinA + dy * cosA,
    );
  }

  bool _isOnScreen(Offset offset, Size size) {
    return offset.dx >= -10 &&
        offset.dy >= -10 &&
        offset.dx <= size.width + 10 &&
        offset.dy <= size.height + 10;
  }

  @override
  bool shouldRepaint(covariant _WindVectorPainter oldDelegate) {
    return oldDelegate.particles != particles ||
        oldDelegate.color != color ||
        oldDelegate.mapController != mapController;
  }
}

class _WindParticle {
  _WindParticle.empty();

  LatLng position = const LatLng(0, 0);
  LatLng previous = const LatLng(0, 0);
  double direction = 0.0;
  double speed = 0.0;
  double age = 0.0;
  double maxAge = 0.0;
}
import 'dart:math';

import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class WindVectorLayer extends StatefulWidget {
  const WindVectorLayer({super.key, required this.mapController});

  final MapController mapController;

  @override
  State<WindVectorLayer> createState() => _WindVectorLayerState();
}

class _WindVectorLayerState extends State<WindVectorLayer>
    with SingleTickerProviderStateMixin {
  static const int _forecastHour = 6;
  static const double _minSpeedKnots = 2;
  static const double _maxSpeedKnots = 60;
  static const double _altitudeResetFt = 2000;

  final List<_WindParticle> _particles = [];
  final GeoCalculations _geo = GeoCalculations();
  final Random _random = Random();

  late final AnimationController _ticker;
  DateTime _lastUpdate = DateTime.now();
  Size _lastSize = Size.zero;
  double _lastAltitudeFt = 0;

  @override
  void initState() {
    super.initState();
    _lastAltitudeFt =
        GeoCalculations.convertAltitude(Storage().position.altitude);
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )
      ..addListener(_onTick)
      ..repeat();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      if (size != _lastSize) {
        _lastSize = size;
        if (size.width > 0 && size.height > 0) {
          final bounds = _calculateBounds(size);
          _resetParticles(bounds, _lastAltitudeFt);
        }
      }
      return IgnorePointer(
        child: RepaintBoundary(
          child: PolylineLayer(
            polylines: _buildPolylines(),
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

    final altitudeFt =
        GeoCalculations.convertAltitude(Storage().position.altitude);
    final bounds = _calculateBounds(_lastSize);

    if ((altitudeFt - _lastAltitudeFt).abs() >= _altitudeResetFt &&
        _particles.isNotEmpty) {
      _lastAltitudeFt = altitudeFt;
      _resetParticles(bounds, altitudeFt);
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
    final List<Polyline> polylines = [];
    for (final particle in _particles) {
      if (particle.speed < _minSpeedKnots) {
        continue;
      }
      final fade = (1.0 - (particle.age / particle.maxAge)).clamp(0.0, 1.0);
      final alpha = (0.2 + 0.8 * fade).clamp(0.0, 1.0);
      polylines.add(Polyline(
        points: [particle.previousPosition, particle.position],
        strokeWidth: particle.strokeWidth,
        strokeCap: StrokeCap.round,
        color: particle.baseColor.withValues(alpha: alpha),
      ));
    }
    return polylines;
  }

  void _advanceParticles(LatLngBounds bounds, double altitudeFt, double dt) {
    for (final particle in _particles) {
      particle.age += dt;
      if (particle.age >= particle.maxAge ||
          !_boundsContains(bounds, particle.position)) {
        _resetParticle(particle, bounds, altitudeFt);
        continue;
      }

      final distanceNm = particle.speed * dt / 3600.0;
      if (distanceNm <= 0) {
        particle.age = particle.maxAge;
        continue;
      }
      particle.previousPosition = particle.position;
      particle.position =
          _geo.calculateOffset(particle.position, distanceNm, particle.heading);
      if (!_boundsContains(bounds, particle.position)) {
        _resetParticle(particle, bounds, altitudeFt);
      }
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
    particle
      ..position = position
      ..previousPosition = position
      ..speed = sample.speed
      ..direction = sample.direction
      ..heading = (sample.direction + 180) % 360
      ..age = 0
      ..maxAge = _lerp(1.5, 4.5, _random.nextDouble())
      ..baseColor = _colorForSpeed(sample.speed)
      ..strokeWidth = _strokeForSpeed(sample.speed);
  }

  _WindSample _sampleWind(LatLng position, double altitudeFt) {
    final (wd, ws) =
        WindsCache.getWindsAt(position, altitudeFt, _forecastHour);
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
    final count = (area / 9000).round();
    return count.clamp(80, 320).toInt();
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

  double _strokeForSpeed(double speed) {
    final t = (speed / _maxSpeedKnots).clamp(0.0, 1.0);
    return 1.0 + t * 1.5;
  }

  Color _colorForSpeed(double speed) {
    final t = (speed / _maxSpeedKnots).clamp(0.0, 1.0);
    return Color.lerp(Colors.lightBlueAccent, Colors.orangeAccent, t) ??
        Colors.lightBlueAccent;
  }
}

class _WindParticle {
  _WindParticle({
    required this.position,
    required this.previousPosition,
    required this.speed,
    required this.direction,
    required this.heading,
    required this.age,
    required this.maxAge,
    required this.baseColor,
    required this.strokeWidth,
  });

  _WindParticle.empty()
      : position = const LatLng(0, 0),
        previousPosition = const LatLng(0, 0),
        speed = 0,
        direction = 0,
        heading = 0,
        age = 0,
        maxAge = 1,
        baseColor = Colors.lightBlueAccent,
        strokeWidth = 1.0;

  LatLng position;
  LatLng previousPosition;
  double speed;
  double direction;
  double heading;
  double age;
  double maxAge;
  Color baseColor;
  double strokeWidth;
}

class _WindSample {
  const _WindSample(this.direction, this.speed);

  final double direction;
  final double speed;
}
