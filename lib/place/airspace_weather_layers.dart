part of 'airspace_3d_view.dart';

/// Icing severity colors by code: 1 trace, 2 light, 3 moderate, 4 heavy.
final Int32List _iceColors = Int32List.fromList(const [
  0x00000000,
  0x2480DEEA,
  0x3826C6DA,
  0x667C4DFF,
  0xA6D500F9,
]);

/// Turbulence colors by eddy dissipation rate times 100: light from 0.15, moderate
/// from 0.30, severe from 0.50.
final Int32List _turbColors = Int32List.fromList([
  for (var v = 0; v <= 100; v++)
    v < 15
        ? 0x00000000
        : (v < 30 ? 0x38FFCA28 : (v < 50 ? 0x70F57C00 : 0xB3BF360C)),
]);

/// Icing thresholds in the menu: severity code, name.
const List<(int, String)> _iceLevels = [
  (1, 'Trace'),
  (2, 'Light'),
  (3, 'Moderate'),
];

/// Turbulence thresholds in the menu: EDR times 100, name, EDR.
const List<(int, String, String)> _turbLevels = [
  (15, 'Light', '0.15'),
  (30, 'Moderate', '0.30'),
  (50, 'Severe', '0.50'),
];

String _utcHm(DateTime time) {
  final t = time.toUtc();
  return '${t.hour.toString().padLeft(2, '0')}${t.minute.toString().padLeft(2, '0')}Z';
}

/// Icing or turbulence volume drawn as translucent cells inside the 3D box.
class _AirspaceHazardLayer extends StatefulWidget {
  final Hazard hazard;
  final LatLng center;
  final double radiusNm;
  final double maxAltitudeFt;
  final int minValue;
  final double pitch;
  final double yaw;
  final double zoom;
  final double panX;
  final double panY;
  final _AirspaceTerrain? terrain;

  const _AirspaceHazardLayer({
    super.key,
    required this.hazard,
    required this.center,
    required this.radiusNm,
    required this.maxAltitudeFt,
    required this.minValue,
    required this.pitch,
    required this.yaw,
    required this.zoom,
    required this.panX,
    required this.panY,
    required this.terrain,
  });

  @override
  State<_AirspaceHazardLayer> createState() => _AirspaceHazardLayerState();
}

class _AirspaceHazardLayerState extends State<_AirspaceHazardLayer> {
  DafsCache get _cache =>
      widget.hazard == Hazard.icing ? DafsCache.icing : DafsCache.turbulence;

  @override
  void initState() {
    super.initState();
    _cache.addListener(_onCache);
    _request();
  }

  @override
  void didUpdateWidget(covariant _AirspaceHazardLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.center.latitude != widget.center.latitude ||
            oldWidget.center.longitude != widget.center.longitude) &&
        _cache.needsRegrid(widget.center.latitude, widget.center.longitude)) {
      _request();
    }
  }

  @override
  void dispose() {
    _cache.removeListener(_onCache);
    super.dispose();
  }

  void _onCache() {
    if (mounted) {
      setState(() {});
    }
  }

  void _request() {
    final center = widget.center;
    // Not inline: the cache notifies listeners, and this can run during build.
    scheduleMicrotask(() {
      if (mounted) {
        unawaited(_cache.refresh(center.latitude, center.longitude));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final grid = _cache.grid;
    if (grid == null) {
      return const SizedBox.shrink();
    }
    final offset = ownshipOffsetNm(
        widget.center, LatLng(grid.centerLat, grid.centerLon),
        radiusNm: null);
    if (offset == null) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: CustomPaint(
        painter: _AirspaceVoxelPainter(
          values: grid.values,
          colors: grid.hazard == Hazard.icing ? _iceColors : _turbColors,
          cols: grid.cols,
          levels: grid.levels,
          cellNm: grid.cellNm,
          halfNm: grid.radiusNm,
          levelFt: grid.levelFt,
          firstLevelFt: grid.firstLevelFt,
          minValue: widget.minValue,
          offsetEast: offset.e,
          offsetNorth: offset.n,
          viewRadiusNm: widget.radiusNm,
          maxAltitudeFt: widget.maxAltitudeFt,
          pitch: widget.pitch,
          yaw: widget.yaw,
          zoom: widget.zoom,
          panX: widget.panX,
          panY: widget.panY,
          terrain: widget.terrain,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Lightning flashes drawn as bolts standing on the ground.
class _AirspaceLightningLayer extends StatefulWidget {
  final LatLng center;
  final double radiusNm;
  final double maxAltitudeFt;
  final double pitch;
  final double yaw;
  final double zoom;
  final double panX;
  final double panY;
  final _AirspaceTerrain? terrain;

  const _AirspaceLightningLayer({
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
  State<_AirspaceLightningLayer> createState() =>
      _AirspaceLightningLayerState();
}

class _AirspaceLightningLayerState extends State<_AirspaceLightningLayer> {
  final LightningCache _cache = LightningCache.instance;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _cache.addListener(_onCache);
    _request();
    // Flashes change color as they age.
    _clock = Timer.periodic(const Duration(seconds: 20), (_) => _onCache());
  }

  @override
  void didUpdateWidget(covariant _AirspaceLightningLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.center.latitude != widget.center.latitude ||
            oldWidget.center.longitude != widget.center.longitude) &&
        _cache.needsRegrid(widget.center.latitude, widget.center.longitude)) {
      _request();
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _cache.removeListener(_onCache);
    super.dispose();
  }

  void _onCache() {
    if (mounted) {
      setState(() {});
    }
  }

  void _request() {
    final center = widget.center;
    scheduleMicrotask(() {
      if (mounted) {
        unawaited(_cache.refresh(center.latitude, center.longitude));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cache.flashes.isEmpty) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: CustomPaint(
        painter: _LightningPainter(
          flashes: _cache.flashes,
          center: widget.center,
          radiusNm: widget.radiusNm,
          maxAltitudeFt: widget.maxAltitudeFt,
          pitch: widget.pitch,
          yaw: widget.yaw,
          zoom: widget.zoom,
          panX: widget.panX,
          panY: widget.panY,
          terrain: widget.terrain,
          nowMs: DateTime.now().millisecondsSinceEpoch,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _LightningPainter extends CustomPainter {
  final List<LightningFlash> flashes;
  final LatLng center;
  final double radiusNm;
  final double maxAltitudeFt;
  final double pitch;
  final double yaw;
  final double zoom;
  final double panX;
  final double panY;
  final _AirspaceTerrain? terrain;
  final int nowMs;

  const _LightningPainter({
    required this.flashes,
    required this.center,
    required this.radiusNm,
    required this.maxAltitudeFt,
    required this.pitch,
    required this.yaw,
    required this.zoom,
    required this.panX,
    required this.panY,
    required this.terrain,
    required this.nowMs,
  });

  /// The mapper gives no height. Bolts are drawn to this altitude, or the top of the box.
  static const double boltTopFt = 15000;

  @override
  void paint(Canvas canvas, Size size) {
    final maxAlt = maxAltitudeFt <= 0 ? 4000.0 : maxAltitudeFt;
    _Proj project(double east, double north, double altFt) => _projectView(
          size,
          east,
          north,
          altFt,
          radius: radiusNm,
          maxAlt: maxAlt,
          pitch: pitch,
          yaw: yaw,
          zoom: zoom,
          panX: panX,
          panY: panY,
        );
    final top = math.min(boltTopFt, maxAlt);
    final mesh = terrain;
    // Newest last, so fresh flashes draw over old ones.
    for (var i = 0; i < flashes.length; i++) {
      final flash = flashes[i];
      final at = ownshipOffsetNm(center, LatLng(flash.lat, flash.lon),
          radiusNm: radiusNm);
      if (at == null) {
        continue;
      }
      final ageMin = (nowMs - flash.time.millisecondsSinceEpoch) / 60000;
      if (ageMin > LightningCache.window.inMinutes + 1) {
        continue;
      }
      final ground = mesh == null
          ? 0.0
          : (sampleTerrainFt(
                      mesh.elevFt, mesh.cols, mesh.rows, at.e, at.n, radiusNm) ??
                  0)
              .clamp(0.0, top);
      final Color color;
      final double width;
      if (ageMin <= 2) {
        color = const Color(0xFFFFF59D);
        width = 2.4;
      } else if (ageMin <= 5) {
        color = const Color(0xFFFFD600);
        width = 1.9;
      } else {
        color = const Color(0xCCFF9100);
        width = 1.5;
      }
      // A jagged path from the ground up, the same shape for the same flash.
      final seed = (flash.lat * 1e4 + flash.lon * 1e4).round().abs();
      final path = Path();
      const steps = 6;
      var started = false;
      var any = false;
      for (var s = 0; s <= steps; s++) {
        final t = s / steps;
        final altitude = ground + (top - ground) * t;
        final jitter = s == 0 || s == steps
            ? 0.0
            : (((seed * (s + 3)) % 17) / 17 - 0.5) * 0.9;
        final p = project(at.e + jitter, at.n - jitter * 0.6, altitude);
        if (p.depth < -2.6) {
          started = false;
          continue;
        }
        any = true;
        if (!started) {
          path.moveTo(p.x, p.y);
          started = true;
        } else {
          path.lineTo(p.x, p.y);
        }
      }
      if (!any) {
        continue;
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withAlpha(70)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 3
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeJoin = StrokeJoin.round,
      );
      final foot = project(at.e, at.n, ground);
      if (foot.depth >= -2.6) {
        canvas.drawCircle(foot.o, width * 1.6, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LightningPainter old) {
    return !identical(old.flashes, flashes) ||
        old.nowMs != nowMs ||
        old.center != center ||
        old.radiusNm != radiusNm ||
        old.maxAltitudeFt != maxAltitudeFt ||
        old.pitch != pitch ||
        old.yaw != yaw ||
        old.zoom != zoom ||
        old.panX != panX ||
        old.panY != panY ||
        old.terrain != terrain;
  }
}

/// The keys for lightning, icing, and turbulence, stacked at the top right. The
/// radar has its own key at the top left, with its loop controls.
class _WeatherKeys extends StatefulWidget {
  final bool lightning;
  final bool icing;
  final bool turbulence;
  final int iceMin;
  final int turbMin;

  const _WeatherKeys({
    required this.lightning,
    required this.icing,
    required this.turbulence,
    required this.iceMin,
    required this.turbMin,
  });

  @override
  State<_WeatherKeys> createState() => _WeatherKeysState();
}

class _WeatherKeysState extends State<_WeatherKeys> {
  Timer? _clock;
  late final Listenable _caches = Listenable.merge(
      [LightningCache.instance, DafsCache.icing, DafsCache.turbulence]);

  @override
  void initState() {
    super.initState();
    _caches.addListener(_onChange);
    // So the time left counts down.
    _clock = Timer.periodic(const Duration(seconds: 20), (_) => _onChange());
  }

  @override
  void dispose() {
    _clock?.cancel();
    _caches.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (widget.lightning) _lightning(scheme),
        if (widget.icing)
          _hazard(
            scheme,
            'Icing',
            'NOAA IFI',
            DafsCache.icing,
            [
              for (final level in _iceLevels)
                if (level.$1 >= widget.iceMin)
                  (_iceColors[level.$1], level.$2),
              (_iceColors[4], 'Heavy'),
            ],
          ),
        if (widget.turbulence)
          _hazard(
            scheme,
            'Turbulence',
            'NOAA GTG',
            DafsCache.turbulence,
            [
              for (final level in _turbLevels)
                if (level.$1 >= widget.turbMin)
                  (_turbColors[level.$1], '${level.$2} ${level.$3}'),
            ],
          ),
      ],
    );
  }

  Widget _box(ColorScheme scheme, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface.withAlpha(190),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: children,
      ),
    );
  }

  Widget _title(ColorScheme scheme, String text) => Text(text,
      style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurface));

  Widget _note(ColorScheme scheme, String text) =>
      Text(text, style: TextStyle(fontSize: 10, color: scheme.outline));

  String? _builtLine(SnapshotCache cache) {
    final built = cache.builtAt;
    if (built == null) {
      return null;
    }
    final left = cache.lifeLeft ?? Duration.zero;
    return 'Built ${_utcHm(built)}  rebuild in ${(left.inSeconds / 60).ceil()} min';
  }

  Widget _swatch(ColorScheme scheme, int argb, String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Color(argb | 0xFF000000),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 9, color: scheme.outline)),
        ],
      ),
    );
  }

  Widget _lightning(ColorScheme scheme) {
    final cache = LightningCache.instance;
    final String text;
    if (cache.message != null && !cache.hasPicture) {
      text = cache.message!;
    } else if (cache.loading) {
      text = '${cache.progress ?? 'Loading'} files';
    } else if (!cache.hasPicture) {
      text = 'Lightning';
    } else {
      final count = cache.flashes.length;
      text = '${cache.satellite ?? 'GOES'}  $count '
          '${count == 1 ? 'flash' : 'flashes'}, last ${LightningCache.window.inMinutes} min';
    }
    final built = _builtLine(cache);
    return _box(scheme, [
      _title(scheme, 'Lightning'),
      _note(scheme, text),
      if (built != null) _note(scheme, built),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _swatch(scheme, 0xFFF59D, '< 2 min'),
          _swatch(scheme, 0xFFD600, '2-5'),
          _swatch(scheme, 0xFF9100, '5-10'),
        ],
      ),
      _note(scheme, 'Position only: no height'),
    ]);
  }

  Widget _hazard(ColorScheme scheme, String name, String source, DafsCache cache,
      List<(int, String)> keys) {
    final grid = cache.grid;
    final String text;
    if (cache.message != null && grid == null) {
      text = cache.message!;
    } else if (grid == null) {
      text = '${cache.progress ?? 'Loading'}...';
    } else {
      text = '$source  valid ${_utcHm(grid.validTime)}'
          '${cache.loading ? '  ${cache.progress ?? ''}' : ''}';
    }
    final built = _builtLine(cache);
    return _box(scheme, [
      _title(scheme, name),
      _note(scheme, text),
      if (built != null) _note(scheme, built),
      if (grid != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [for (final key in keys) _swatch(scheme, key.$1, key.$2)],
        ),
    ]);
  }
}

/// A volume of byte-valued cells drawn as translucent boxes in the 3D view. Radar,
/// icing and turbulence all use it, each with its own color table. Cell
/// `(level, row, col)` is `values[(level * cols + row) * cols + col]`, and
/// a cell is drawn when its value is at least [minValue].
class _AirspaceVoxelPainter extends CustomPainter {
  final Uint8List values;
  final Int32List colors;
  final int cols;
  final int levels;
  final double cellNm;
  final double halfNm;
  final double levelFt;

  /// Altitude at the center of level 0.
  final double firstLevelFt;
  final int minValue;
  final double offsetEast;
  final double offsetNorth;
  final double viewRadiusNm;
  final double maxAltitudeFt;
  final double pitch;
  final double yaw;
  final double zoom;
  final double panX;
  final double panY;
  final _AirspaceTerrain? terrain;

  _AirspaceVoxelPainter({
    required this.values,
    required this.colors,
    required this.cols,
    required this.levels,
    required this.cellNm,
    required this.halfNm,
    required this.levelFt,
    required this.firstLevelFt,
    required this.minValue,
    required this.offsetEast,
    required this.offsetNorth,
    required this.viewRadiusNm,
    required this.maxAltitudeFt,
    required this.pitch,
    required this.yaw,
    required this.zoom,
    required this.panX,
    required this.panY,
    required this.terrain,
  });

  /// Quads per draw call. Four vertices each must stay under 65536 for 16 bit indices.
  static const int _batch = 12000;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = viewRadiusNm;
    final maxAlt = maxAltitudeFt <= 0 ? 4000.0 : maxAltitudeFt;
    final altScale = radius * 0.72 / maxAlt;
    final cosY = math.cos(yaw);
    final sinY = math.sin(yaw);
    final cosP = math.cos(pitch);
    final sinP = math.sin(pitch);
    final s = math.min(size.width, size.height) * 0.36 * zoom;
    const camera = 3.2;
    final cell = cellNm;
    final half = halfNm;

    // Cells whose center is inside the 25 NM square of the view.
    int colFor(double east) => ((east - offsetEast + half) / cell).floor();
    int rowFor(double north) => ((north - offsetNorth + half) / cell).floor();
    final colMin = math.max(0, colFor(-radius));
    final colMax = math.min(cols - 1, colFor(radius));
    final rowMin = math.max(0, rowFor(-radius));
    final rowMax = math.min(cols - 1, rowFor(radius));
    if (colMin > colMax || rowMin > rowMax) {
      return;
    }

    // Farthest cell first. Depth grows with east when sinY*cosP > 0 and with
    // north when cosY*cosP > 0. Higher cells are nearer the camera.
    final eastForward = sinY * cosP > 0;
    final northForward = cosY * cosP > 0;

    final mesh = terrain;
    final vertScale = levelFt * altScale / radius * 0.5;
    final horizScale = cell / radius * 0.5;

    var positions = Float32List(_batch * 8);
    final vertexColors = Int32List(_batch * 4);
    var count = 0;
    final indices = Uint16List(_batch * 6);
    for (var q = 0; q < _batch; q++) {
      final v = q * 4;
      indices[q * 6] = v;
      indices[q * 6 + 1] = v + 1;
      indices[q * 6 + 2] = v + 2;
      indices[q * 6 + 3] = v;
      indices[q * 6 + 4] = v + 2;
      indices[q * 6 + 5] = v + 3;
    }
    final paint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..isAntiAlias = false;

    void flush() {
      if (count == 0) {
        return;
      }
      final vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        Float32List.sublistView(positions, 0, count * 8),
        colors: Int32List.sublistView(vertexColors, 0, count * 4),
        indices: Uint16List.sublistView(indices, 0, count * 6),
      );
      canvas.drawVertices(vertices, BlendMode.modulate, paint);
      vertices.dispose();
      count = 0;
    }

    final slab = cols * cols;
    for (var level = 0; level < levels; level++) {
      final altFt = firstLevelFt + level * levelFt;
      if (altFt > maxAlt) {
        break;
      }
      final y = altFt * altScale / radius;
      final base = level * slab;
      for (var ri = 0; ri <= rowMax - rowMin; ri++) {
        final row = northForward ? rowMax - ri : rowMin + ri;
        final north = -half + (row + 0.5) * cell + offsetNorth;
        final rowBase = base + row * cols;
        for (var ci = 0; ci <= colMax - colMin; ci++) {
          final col = eastForward ? colMax - ci : colMin + ci;
          final value = values[rowBase + col];
          if (value < minValue) {
            continue;
          }
          final east = -half + (col + 0.5) * cell + offsetEast;
          if (mesh != null) {
            final ground = sampleTerrainFt(
                mesh.elevFt, mesh.cols, mesh.rows, east, north, radius);
            if (ground != null && altFt + levelFt * 0.5 < ground) {
              continue;
            }
          }
          final x = east / radius;
          final z = north / radius;
          final x1 = x * cosY - z * sinY;
          final z1 = x * sinY + z * cosY;
          final y2 = y * cosP + z1 * sinP;
          final z2 = -y * sinP + z1 * cosP;
          final persp = camera / (camera + z2);
          if (persp <= 0 || z2 < -2.6) {
            continue;
          }
          final sx = size.width / 2 + x1 * s * persp + panX;
          final sy = size.height / 2 - y2 * s * persp + panY;
          final spread = cosY.abs() + sinY.abs();
          final hw = horizScale * spread * s * persp * 1.05;
          final hh = (vertScale * cosP + horizScale * spread * sinP) *
              s *
              persp *
              1.05;
          final p = count * 8;
          positions[p] = sx - hw;
          positions[p + 1] = sy - hh;
          positions[p + 2] = sx + hw;
          positions[p + 3] = sy - hh;
          positions[p + 4] = sx + hw;
          positions[p + 5] = sy + hh;
          positions[p + 6] = sx - hw;
          positions[p + 7] = sy + hh;
          final argb = colors[value];
          final c = count * 4;
          vertexColors[c] = argb;
          vertexColors[c + 1] = argb;
          vertexColors[c + 2] = argb;
          vertexColors[c + 3] = argb;
          count++;
          if (count == _batch) {
            flush();
          }
        }
      }
    }
    flush();
  }

  @override
  bool shouldRepaint(covariant _AirspaceVoxelPainter old) {
    return !identical(old.values, values) ||
        old.minValue != minValue ||
        old.offsetEast != offsetEast ||
        old.offsetNorth != offsetNorth ||
        old.viewRadiusNm != viewRadiusNm ||
        old.maxAltitudeFt != maxAltitudeFt ||
        old.pitch != pitch ||
        old.yaw != yaw ||
        old.zoom != zoom ||
        old.panX != panX ||
        old.panY != panY ||
        old.terrain != terrain;
  }
}
