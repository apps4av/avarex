part of 'airspace_3d_view.dart';

/// Colored winds-aloft streaks in the same 3D box as the airspace.
class _AirspaceWindLayer extends StatefulWidget {
  final LatLng center;
  final double radiusNm;
  final double maxAltitudeFt;
  final double pitch;
  final double yaw;
  final double zoom;
  final double panX;
  final double panY;
  final _AirspaceTerrain? terrain;

  const _AirspaceWindLayer({
    required this.center,
    required this.radiusNm,
    required this.maxAltitudeFt,
    required this.pitch,
    required this.yaw,
    required this.zoom,
    required this.panX,
    required this.panY,
    required this.terrain,
  });

  @override
  State<_AirspaceWindLayer> createState() => _AirspaceWindLayerState();
}

class _AirspaceWindLayerState extends State<_AirspaceWindLayer>
    with SingleTickerProviderStateMixin {
  final math.Random _random = math.Random();
  final List<WindFlowParticle> _particles = [];
  List<WindFlowStreak> _streaks = const [];
  WindFlowField? _field;
  String _fieldKey = '';
  bool _listening = false;
  bool _downloadRequested = false;
  int _generation = 0;
  DateTime _last = DateTime.now();
  late final AnimationController _ticker;

  @override
  void initState() {
    super.initState();
    _listen();
    _reload(resetParticles: true);
    _ticker = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..addListener(_onTick)
      ..repeat();
  }

  @override
  void didUpdateWidget(covariant _AirspaceWindLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final moved = oldWidget.center.latitude != widget.center.latitude ||
        oldWidget.center.longitude != widget.center.longitude;
    final grew = (oldWidget.maxAltitudeFt - widget.maxAltitudeFt).abs() > 200 ||
        (oldWidget.radiusNm - widget.radiusNm).abs() > 0.1;
    if (moved || grew) {
      _reload(resetParticles: true);
    }
  }

  @override
  void dispose() {
    if (_listening) {
      try {
        Storage().winds.change.removeListener(_onWinds);
      } catch (_) {}
    }
    _ticker.dispose();
    super.dispose();
  }

  void _listen() {
    try {
      Storage().winds.change.addListener(_onWinds);
      _listening = true;
    } catch (_) {
      _listening = false;
    }
  }

  void _onWinds() {
    _reload(resetParticles: false);
    if (mounted) {
      setState(() {});
    }
  }

  String get _key =>
      '${widget.center.latitude.toStringAsFixed(3)},${widget.center.longitude.toStringAsFixed(3)},${widget.radiusNm.toStringAsFixed(1)},${widget.maxAltitudeFt.round()}';

  void _reload({required bool resetParticles}) {
    _fieldKey = _key;
    try {
      final winds = Storage().winds;
      if (winds.getAll().isEmpty && !_downloadRequested) {
        _downloadRequested = true;
        winds.download();
      }
      _field = loadCachedWindFlowField(
        center: widget.center,
        radiusNm: widget.radiusNm,
        maxAltitudeFt: widget.maxAltitudeFt,
      );
    } catch (_) {
      _field = null;
    }
    final field = _field;
    if (field == null) {
      _particles.clear();
      _streaks = const [];
      return;
    }
    if (resetParticles || _particles.isEmpty) {
      _particles
        ..clear()
        ..addAll(seedWindParticles(
          random: _random,
          radiusNm: widget.radiusNm,
          maxAltitudeFt: widget.maxAltitudeFt,
        ));
    }
    _collect(field);
  }

  void _collect(WindFlowField field) {
    if (!field.hasWind) {
      _streaks = const [];
      return;
    }
    final streaks = <WindFlowStreak>[];
    for (final particle in _particles) {
      final streak = windFlowStreak(particle, field);
      if (streak != null && streak.alpha > 0.04) {
        streaks.add(streak);
      }
    }
    _streaks = streaks;
  }

  void _onTick() {
    final now = DateTime.now();
    final dt = now.difference(_last).inMicroseconds / 1000000.0;
    _last = now;
    if (_fieldKey != _key || _field == null) {
      _reload(resetParticles: _particles.isEmpty);
    }
    final field = _field;
    if (field == null || !field.hasWind || _particles.isEmpty || dt <= 0) {
      return;
    }
    advanceWindFlow(
      particles: _particles,
      field: field,
      random: _random,
      dtSeconds: dt,
      radiusNm: widget.radiusNm,
      maxAltitudeFt: widget.maxAltitudeFt,
    );
    _collect(field);
    _generation++;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _AirspaceWindPainter(
          streaks: _streaks,
          radiusNm: widget.radiusNm,
          maxAltitudeFt: widget.maxAltitudeFt,
          pitch: widget.pitch,
          yaw: widget.yaw,
          zoom: widget.zoom,
          panX: widget.panX,
          panY: widget.panY,
          generation: _generation,
          terrain: widget.terrain,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _WindMark {
  final double depth;
  final Offset tail;
  final Offset head;
  final Color color;
  final double alpha;

  const _WindMark(this.depth, this.tail, this.head, this.color, this.alpha);
}

class _AirspaceWindPainter extends CustomPainter {
  final List<WindFlowStreak> streaks;
  final double radiusNm;
  final double maxAltitudeFt;
  final double pitch;
  final double yaw;
  final double zoom;
  final double panX;
  final double panY;
  final int generation;
  final _AirspaceTerrain? terrain;

  _AirspaceWindPainter({
    required this.streaks,
    required this.radiusNm,
    required this.maxAltitudeFt,
    required this.pitch,
    required this.yaw,
    required this.zoom,
    required this.panX,
    required this.panY,
    required this.generation,
    required this.terrain,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final marks = <_WindMark>[];
    for (final streak in streaks) {
      final tailPoint = windStreakAboveGround(
        headEast: streak.headEast,
        headNorth: streak.headNorth,
        tailEast: streak.tailEast,
        tailNorth: streak.tailNorth,
        altitudeFt: streak.altitudeFt,
        groundFt: _groundFt,
      );
      if (tailPoint == null) {
        continue;
      }
      final head =
          _project(size, streak.headEast, streak.headNorth, streak.altitudeFt);
      final tail =
          _project(size, tailPoint.east, tailPoint.north, streak.altitudeFt);
      if (head.depth < -2.6 || tail.depth < -2.6) {
        continue;
      }
      final span = (head.o - tail.o).distance;
      if (span < 2) {
        continue;
      }
      marks.add(_WindMark(
        (head.depth + tail.depth) / 2,
        tail.o,
        head.o,
        windSpeedColor(streak.speedKt),
        streak.alpha,
      ));
    }
    marks.sort((a, b) => b.depth.compareTo(a.depth));
    for (final mark in marks) {
      _drawStreak(canvas, mark);
    }
  }

  double? _groundFt(double east, double north) {
    final mesh = terrain;
    if (mesh == null) {
      return null;
    }
    return sampleTerrainFt(
        mesh.elevFt, mesh.cols, mesh.rows, east, north, radiusNm);
  }

  _Proj _project(Size size, double east, double north, double altitudeFt) {
    return _projectView(
      size,
      east,
      north,
      altitudeFt,
      radius: radiusNm,
      maxAlt: maxAltitudeFt <= 0 ? 4000 : maxAltitudeFt,
      pitch: pitch,
      yaw: yaw,
      zoom: zoom,
      panX: panX,
      panY: panY,
    );
  }

  void _drawStreak(Canvas canvas, _WindMark mark) {
    final delta = mark.head - mark.tail;
    final len = delta.distance;
    final direction = delta / len;
    final side = Offset(-direction.dy, direction.dx);
    final color = mark.color.withValues(alpha: mark.alpha.clamp(0.0, 1.0));
    final shade = Paint()
      ..color = const Color(0xFF000000).withValues(alpha: mark.alpha * 0.55)
      ..strokeWidth = 4.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(mark.tail, mark.head, shade);
    canvas.drawLine(mark.tail, mark.head, paint);
    final wing = 5.0;
    final left = mark.head - direction * wing * 1.15 + side * (wing * 0.48);
    final right = mark.head - direction * wing * 1.15 - side * (wing * 0.48);
    canvas.drawLine(mark.head, left, paint);
    canvas.drawLine(mark.head, right, paint);
  }

  @override
  bool shouldRepaint(covariant _AirspaceWindPainter oldDelegate) {
    return oldDelegate.generation != generation ||
        oldDelegate.pitch != pitch ||
        oldDelegate.yaw != yaw ||
        oldDelegate.zoom != zoom ||
        oldDelegate.panX != panX ||
        oldDelegate.panY != panY ||
        oldDelegate.maxAltitudeFt != maxAltitudeFt ||
        oldDelegate.radiusNm != radiusNm ||
        oldDelegate.terrain != terrain;
  }
}

/// Wind speed key for the 3D Weather screen, from the same colors the streaks use.
class _WindLegend extends StatelessWidget {
  const _WindLegend();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final top = windSpeedColors.last.knots;
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: scheme.surface.withAlpha(190),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Winds aloft',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface)),
            const SizedBox(height: 3),
            Container(
              width: 120,
              height: 8,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  for (final stop in windSpeedColors) stop.color,
                ], stops: [
                  for (final stop in windSpeedColors) stop.knots / top,
                ]),
              ),
            ),
            SizedBox(
              width: 120,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final label in ['0', '24', '48', '60+ kt'])
                    Text(label,
                        style: TextStyle(fontSize: 9, color: scheme.outline)),
                ],
              ),
            ),
            Text('arrow points downwind',
                style: TextStyle(fontSize: 9, color: scheme.outline)),
          ],
        ),
      ),
    );
  }
}
