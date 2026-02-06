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
  static const double _minSpeedKnots = 2;
  static const double _maxSpeedKnots = 60;
  static const double _altitudeResetFt = 2000;
  static const double _minAgeSeconds = 2.5;
  static const double _maxAgeSeconds = 6.5;
  static const int _minParticles = 80;
  static const int _maxParticles = 320;

  final List<_WindParticle> _particles = [];
  final GeoCalculations _geo = GeoCalculations();
  final math.Random _random = math.Random();

  late final AnimationController _ticker;
  DateTime _lastUpdate = DateTime.now();
  Size _lastSize = Size.zero;
  double _lastAltitudeFt = 0;
  bool _needsReset = true;

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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      if (size != _lastSize && size.width > 0 && size.height > 0) {
        _lastSize = size;
        _needsReset = true;
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
    final List<Polyline> polylines = [];
    for (final particle in _particles) {
      if (particle.speed < _minSpeedKnots) {
        continue;
      }
      final fade = (1.0 - (particle.age / particle.maxAge)).clamp(0.0, 1.0);
      final speedFactor =
          (particle.speed / _maxSpeedKnots).clamp(0.2, 1.0);
      final alpha = (0.15 + 0.85 * fade) * speedFactor;
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

      final distanceNm = particle.speed * dt / 3600.0 * _speedScale;
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
      ..maxAge = _lerp(_minAgeSeconds, _maxAgeSeconds, _random.nextDouble())
      ..baseColor = _colorForSpeed(sample.speed)
      ..strokeWidth = _strokeForSpeed(sample.speed);
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
    final count = (area / 9000).round();
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

  double _strokeForSpeed(double speed) {
    final t = (speed / _maxSpeedKnots).clamp(0.0, 1.0);
    return 1.0 + t * 1.5;
  }

  Color _colorForSpeed(double speed) {
    final t = (speed / _maxSpeedKnots).clamp(0.0, 1.0);
    return Color.lerp(widget.color, Colors.orangeAccent, t) ?? widget.color;
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
