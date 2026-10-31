part of 'airspace_3d_view.dart';

/// Reflectivity colors, whole dBZ 0 to 95. Same ramp the NWS uses for base reflectivity.
final Int32List _radarColors = _buildRadarColors();

Int32List _buildRadarColors() {
  const stops = <int, int>{
    5: 0x04E9E7,
    15: 0x019FF4,
    20: 0x0300F4,
    25: 0x02FD02,
    30: 0x01C501,
    35: 0x008E00,
    40: 0xFDF802,
    45: 0xE5BC00,
    50: 0xFD9500,
    55: 0xFD0000,
    60: 0xD40000,
    65: 0xBC0000,
    70: 0xF800FD,
    75: 0x9854C6,
  };
  final keys = stops.keys.toList()..sort();
  final out = Int32List(96);
  for (var dbz = 0; dbz < 96; dbz++) {
    final clamped = dbz.clamp(keys.first, keys.last);
    var color = stops[keys.first]!;
    for (var i = 0; i < keys.length - 1; i++) {
      if (clamped >= keys[i] && clamped <= keys[i + 1]) {
        // Hard steps like the radar legend, not a blend.
        color = stops[keys[i]]!;
        break;
      }
      color = stops[keys.last]!;
    }
    // Faint haze for light rain, nearly solid in the cores.
    final alpha = (20 + (dbz - 5) * 3.2).clamp(20.0, 215.0).round();
    out[dbz] = (alpha << 24) | color;
  }
  return out;
}

/// NEXRAD volume drawn as translucent cells inside the same 3D box as the airspace.
class _AirspaceRadarLayer extends StatefulWidget {
  final LatLng center;
  final double radiusNm;
  final double maxAltitudeFt;
  final double minDbz;
  final double pitch;
  final double yaw;
  final double zoom;
  final double panX;
  final double panY;
  final _AirspaceTerrain? terrain;

  const _AirspaceRadarLayer({
    required this.center,
    required this.radiusNm,
    required this.maxAltitudeFt,
    required this.minDbz,
    required this.pitch,
    required this.yaw,
    required this.zoom,
    required this.panX,
    required this.panY,
    required this.terrain,
  });

  @override
  State<_AirspaceRadarLayer> createState() => _AirspaceRadarLayerState();
}

class _AirspaceRadarLayerState extends State<_AirspaceRadarLayer> {
  /// Redraws the legend so the time left counts down.
  static const Duration _clock = Duration(seconds: 20);
  static const Duration _step = Duration(milliseconds: 650);

  /// Extra ticks to rest on the newest frame before the loop restarts.
  static const int _hold = 3;

  /// Kept between openings of the view.
  static bool _playing = true;

  final NexradVolumeCache _cache = NexradVolumeCache.instance;
  Timer? _timer;
  Timer? _animation;
  NexradGrid? _shown;
  int _rest = 0;

  @override
  void initState() {
    super.initState();
    _cache.addListener(_onCache);
    _request();
    _timer = Timer.periodic(_clock, (_) {
      if (mounted) {
        setState(() {});
      }
    });
    _animation = Timer.periodic(_step, (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant _AirspaceRadarLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // No background updates: a build is a snapshot. Only rebuild when the
    // aircraft has left the area the grids cover.
    if ((oldWidget.center.latitude != widget.center.latitude ||
            oldWidget.center.longitude != widget.center.longitude) &&
        _cache.needsRegrid(widget.center.latitude, widget.center.longitude)) {
      _request();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animation?.cancel();
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

  /// The frame on screen. Falls back to the newest when the shown one was dropped.
  NexradGrid? get _current {
    final frames = _cache.frames;
    if (frames.isEmpty) {
      return null;
    }
    final shown = _shown;
    return shown != null && frames.contains(shown) ? shown : frames.last;
  }

  void _tick() {
    if (!_playing || !mounted) {
      return;
    }
    final frames = _cache.frames;
    if (frames.length < 2) {
      return;
    }
    final index = frames.indexOf(_current!);
    if (index == frames.length - 1 && _rest < _hold) {
      _rest++;
      return;
    }
    _rest = 0;
    setState(() => _shown = frames[(index + 1) % frames.length]);
  }

  @override
  Widget build(BuildContext context) {
    final grid = _current;
    final offset = grid == null
        ? null
        : ownshipOffsetNm(widget.center, LatLng(grid.centerLat, grid.centerLon),
            radiusNm: null);
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (grid != null && offset != null)
          IgnorePointer(
            child: CustomPaint(
              painter: _AirspaceVoxelPainter(
                values: grid.dbz,
                colors: _radarColors,
                cols: grid.cols,
                levels: grid.levels,
                cellNm: grid.cellNm,
                halfNm: grid.radiusNm,
                levelFt: grid.levelFt,
                firstLevelFt: grid.levelFt * 0.5,
                minValue: widget.minDbz.round().clamp(NexradGrid.minDbz, 95),
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
          ),
        Positioned(
          left: 8,
          top: 6,
          child: _legend(scheme, grid),
        ),
      ],
    );
  }

  Widget _legend(ColorScheme scheme, NexradGrid? grid) {
    final frames = _cache.frames;
    final progress = _cache.loading && _cache.expectedCount > 0
        ? '  loading ${_cache.loadedCount + 1 > _cache.expectedCount ? _cache.expectedCount : _cache.loadedCount + 1} of ${_cache.expectedCount}'
        : '';
    String text;
    if (_cache.message != null && grid == null) {
      text = _cache.message!;
    } else if (grid == null) {
      text = _cache.status.isEmpty ? 'Radar' : '${_cache.status}...';
    } else {
      final newest = frames.last.time;
      final behind = newest.difference(grid.time).inMinutes;
      final age = grid.ageMinutes.round();
      final t = grid.time;
      final hh = t.hour.toString().padLeft(2, '0');
      final mm = t.minute.toString().padLeft(2, '0');
      text = '${grid.label}  $hh${mm}Z  '
          '${behind > 0 ? '-$behind min' : (age < 1 ? 'now' : '$age min old')}'
          '$progress';
    }
    final built = _cache.builtAt;
    String? builtText;
    if (built != null && grid != null) {
      final b = built.toUtc();
      final left = _cache.lifeLeft ?? Duration.zero;
      builtText =
          'Built ${b.hour.toString().padLeft(2, '0')}${b.minute.toString().padLeft(2, '0')}Z'
          '  rebuild in ${(left.inSeconds / 60).ceil()} min';
    }
    final index = grid == null ? 0 : frames.indexOf(grid);
    final canPlay = frames.length > 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface.withAlpha(190),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface)),
          if (builtText != null)
            Text(builtText,
                style: TextStyle(fontSize: 10, color: scheme.outline)),
          if (canPlay)
            SizedBox(
              width: 190,
              height: 30,
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 22,
                      tooltip: _playing ? 'Pause' : 'Play',
                      icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                      onPressed: () => setState(() {
                        _playing = !_playing;
                        _rest = 0;
                      }),
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        overlayShape: SliderComponentShape.noOverlay,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        min: 0,
                        max: (frames.length - 1).toDouble(),
                        divisions: frames.length - 1,
                        value: index.clamp(0, frames.length - 1).toDouble(),
                        onChanged: (value) => setState(() {
                          _playing = false;
                          _shown = frames[value.round()];
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (grid != null) ...[
            const SizedBox(height: 3),
            SizedBox(
              width: 150,
              height: 8,
              child: CustomPaint(painter: _RadarRampPainter()),
            ),
            SizedBox(
              width: 150,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final label in ['10', '30', '50', '70 dBZ'])
                    Text(label,
                        style: TextStyle(fontSize: 9, color: scheme.outline)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RadarRampPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const low = 10;
    const high = 75;
    final step = size.width / (high - low);
    for (var dbz = low; dbz < high; dbz++) {
      final argb = _radarColors[dbz];
      canvas.drawRect(
        Rect.fromLTWH((dbz - low) * step, 0, step + 0.6, size.height),
        Paint()..color = Color(argb | 0xFF000000),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
