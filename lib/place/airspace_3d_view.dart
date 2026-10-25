import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:avaremp/constants.dart';
import 'package:avaremp/io/gps.dart';
import 'package:avaremp/place/airspace_volume.dart';
import 'package:avaremp/place/elevation_cache.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/path_utils.dart';
import 'package:avaremp/weather/game_tfr.dart';
import 'package:avaremp/weather/tfr.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:universal_io/io.dart';

/// Elevation samples over the 25 NM square. Row 0 is south, column 0 is west.
class _AirspaceTerrain {
  final int cols;
  final int rows;
  final List<double?> elevFt;

  const _AirspaceTerrain({required this.cols, required this.rows, required this.elevFt});
}

/// One ADS-B target already converted into the 3D view.
class _AirspaceTrafficDot {
  final double eastNm;
  final double northNm;
  final double altitudeFt;
  final bool threat;

  const _AirspaceTrafficDot({
    required this.eastNm,
    required this.northNm,
    required this.altitudeFt,
    required this.threat,
  });
}

const int _clipWest = 1;
const int _clipEast = 2;
const int _clipSouth = 4;
const int _clipNorth = 8;

int _clipCode(double east, double north, double radius) {
  var code = 0;
  if (east < -radius) {
    code |= _clipWest;
  } else if (east > radius) {
    code |= _clipEast;
  }
  if (north < -radius) {
    code |= _clipSouth;
  } else if (north > radius) {
    code |= _clipNorth;
  }
  return code;
}

(NmPoint, NmPoint)? _clipSegment(NmPoint a, NmPoint b, double radius) {
  var e0 = a.e;
  var n0 = a.n;
  var e1 = b.e;
  var n1 = b.n;
  for (var guard = 0; guard < 8; guard++) {
    final c0 = _clipCode(e0, n0, radius);
    final c1 = _clipCode(e1, n1, radius);
    if ((c0 | c1) == 0) {
      return (NmPoint(e0, n0), NmPoint(e1, n1));
    }
    if ((c0 & c1) != 0) {
      return null;
    }
    final outside = c0 != 0 ? c0 : c1;
    final de = e1 - e0;
    final dn = n1 - n0;
    final double east;
    final double north;
    if ((outside & _clipNorth) != 0 && dn != 0) {
      east = e0 + de * (radius - n0) / dn;
      north = radius;
    } else if ((outside & _clipSouth) != 0 && dn != 0) {
      east = e0 + de * (-radius - n0) / dn;
      north = -radius;
    } else if ((outside & _clipEast) != 0 && de != 0) {
      north = n0 + dn * (radius - e0) / de;
      east = radius;
    } else if ((outside & _clipWest) != 0 && de != 0) {
      north = n0 + dn * (-radius - e0) / de;
      east = -radius;
    } else {
      return null;
    }
    if (outside == c0) {
      e0 = east;
      n0 = north;
    } else {
      e1 = east;
      n1 = north;
    }
  }
  return null;
}

/// Pieces of [points] that lie inside the 3D square. A leg that only crosses
/// the view is cut at the edge instead of being dropped.
@visibleForTesting
List<List<NmPoint>> clipPathToView(List<NmPoint> points, {double radiusNm = airspaceViewRadiusNm}) {
  final pieces = <List<NmPoint>>[];
  List<NmPoint>? current;
  for (var i = 0; i < points.length - 1; i++) {
    final clipped = _clipSegment(points[i], points[i + 1], radiusNm);
    if (clipped == null) {
      if (current != null) {
        pieces.add(current);
        current = null;
      }
      continue;
    }
    final start = clipped.$1;
    final end = clipped.$2;
    if (current == null || (current.last.e - start.e).abs() > 0.05 || (current.last.n - start.n).abs() > 0.05) {
      if (current != null) {
        pieces.add(current);
      }
      current = [start, end];
    } else {
      current.add(end);
    }
  }
  if (current != null) {
    pieces.add(current);
  }
  return pieces;
}

class _AltNm {
  final NmPoint point;
  final double altitudeFt;

  const _AltNm(this.point, this.altitudeFt);
}

double _altitudeOnSegment(_AltNm from, _AltNm to, NmPoint at) {
  final double de = to.point.e - from.point.e;
  final double dn = to.point.n - from.point.n;
  final double length2 = de * de + dn * dn;
  if (length2 <= 0) {
    return from.altitudeFt;
  }
  final double t = ((at.e - from.point.e) * de + (at.n - from.point.n) * dn) / length2;
  return from.altitudeFt + (to.altitudeFt - from.altitudeFt) * t.clamp(0.0, 1.0);
}

/// Same clipping as [clipPathToView], keeping each point's altitude.
List<List<_AltNm>> _clipAltPath(List<_AltNm> points, {double radiusNm = airspaceViewRadiusNm}) {
  final List<List<_AltNm>> pieces = [];
  List<_AltNm>? current;
  for (int index = 0; index < points.length - 1; index++) {
    final _AltNm from = points[index];
    final _AltNm to = points[index + 1];
    final (NmPoint, NmPoint)? clipped = _clipSegment(from.point, to.point, radiusNm);
    if (clipped == null) {
      if (current != null) {
        pieces.add(current);
        current = null;
      }
      continue;
    }
    final _AltNm start = _AltNm(clipped.$1, _altitudeOnSegment(from, to, clipped.$1));
    final _AltNm end = _AltNm(clipped.$2, _altitudeOnSegment(from, to, clipped.$2));
    if (current == null ||
        (current.last.point.e - start.point.e).abs() > 0.05 ||
        (current.last.point.n - start.point.n).abs() > 0.05) {
      if (current != null) {
        pieces.add(current);
      }
      current = [start, end];
    } else {
      current.add(end);
    }
  }
  if (current != null) {
    pieces.add(current);
  }
  return pieces;
}

List<NmPoint> _planOffsets(LatLng center, List<LatLng> path) {
  final points = <NmPoint>[];
  for (final point in path) {
    final offset = ownshipOffsetNm(center, point, radiusNm: null);
    if (offset != null) {
      points.add(offset);
    }
  }
  return points;
}

/// True when the glide profile produced a ring, not a single fallback point.
@visibleForTesting
bool glideRingHasReach(List<LatLng> points) {
  if (points.length < 3) {
    return false;
  }
  final origin = points.first;
  for (final point in points.skip(1)) {
    if ((point.latitude - origin.latitude).abs() > 1e-5 || (point.longitude - origin.longitude).abs() > 1e-5) {
      return true;
    }
  }
  return false;
}

/// Ground height in feet at [east]/[north], or null when a sample is missing.
@visibleForTesting
double? sampleTerrainFt(List<double?> elevFt, int cols, int rows, double east, double north, double radius) {
  if (cols < 2 || rows < 2 || radius <= 0 || elevFt.length < cols * rows) {
    return null;
  }
  final col = ((east + radius) / (2 * radius) * (cols - 1)).clamp(0.0, (cols - 1).toDouble());
  final row = ((north + radius) / (2 * radius) * (rows - 1)).clamp(0.0, (rows - 1).toDouble());
  final col0 = col.floor();
  final row0 = row.floor();
  final col1 = math.min(col0 + 1, cols - 1);
  final row1 = math.min(row0 + 1, rows - 1);
  final h00 = elevFt[row0 * cols + col0];
  final h10 = elevFt[row0 * cols + col1];
  final h01 = elevFt[row1 * cols + col0];
  final h11 = elevFt[row1 * cols + col1];
  if (h00 == null || h10 == null || h01 == null || h11 == null) {
    return null;
  }
  final tx = col - col0;
  final ty = row - row0;
  return (h00 + (h10 - h00) * tx) + ((h01 + (h11 - h01) * tx) - (h00 + (h10 - h00) * tx)) * ty;
}

/// Published shelf floor, raised to the ground when the terrain is higher.
/// Surface airspace is stored as 0 ft, which is sea level, not the hill under it.
@visibleForTesting
double airspaceAboveGround(double floorFt, double? terrainFt) {
  if (terrainFt == null || terrainFt <= floorFt) {
    return floorFt;
  }
  return terrainFt;
}

/// [subject] cut to [clip]. [clip] may be clockwise or counterclockwise.
@visibleForTesting
List<NmPoint> clipRingToRing(List<NmPoint> subject, List<NmPoint> clip) {
  final ring = _openRing(clip);
  final start = _openRing(subject);
  if (ring.length < 3 || start.length < 3) {
    return const [];
  }
  final ccw = _ringArea(ring) >= 0;
  var output = start;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    if ((a.e - b.e).abs() < 1e-9 && (a.n - b.n).abs() < 1e-9) {
      continue;
    }
    final input = output;
    output = <NmPoint>[];
    if (input.isEmpty) {
      return const [];
    }
    var previous = input.last;
    for (final point in input) {
      final inside = _ringSide(a, b, point, ccw);
      final wasInside = _ringSide(a, b, previous, ccw);
      if (inside) {
        if (!wasInside) {
          output.add(_ringHit(previous, point, a, b));
        }
        output.add(point);
      } else if (wasInside) {
        output.add(_ringHit(previous, point, a, b));
      }
      previous = point;
    }
  }
  return _openRing(output);
}

List<NmPoint> _openRing(List<NmPoint> ring) {
  if (ring.length > 1 &&
      (ring.first.e - ring.last.e).abs() < 1e-6 &&
      (ring.first.n - ring.last.n).abs() < 1e-6) {
    return ring.sublist(0, ring.length - 1);
  }
  return ring;
}

double _ringArea(List<NmPoint> ring) {
  var area = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    area += a.e * b.n - b.e * a.n;
  }
  return area / 2;
}

bool _ringSide(NmPoint a, NmPoint b, NmPoint p, bool ccw) {
  final cross = (b.e - a.e) * (p.n - a.n) - (b.n - a.n) * (p.e - a.e);
  return ccw ? cross >= -1e-8 : cross <= 1e-8;
}

NmPoint _ringHit(NmPoint s, NmPoint e, NmPoint a, NmPoint b) {
  final seE = e.e - s.e;
  final seN = e.n - s.n;
  final abE = b.e - a.e;
  final abN = b.n - a.n;
  final denom = seE * abN - seN * abE;
  if (denom.abs() < 1e-12) {
    return e;
  }
  final t = (((a.e - s.e) * abN - (a.n - s.n) * abE) / denom).clamp(0.0, 1.0).toDouble();
  return NmPoint(s.e + seE * t, s.n + seN * t);
}

bool _layerOn(String name) {
  try {
    final layers = Storage().settings.getLayers();
    final opacity = Storage().settings.getLayersOpacity();
    final index = layers.indexOf(name);
    return index >= 0 && index < opacity.length && opacity[index] > 0;
  } catch (_) {
    return false;
  }
}

bool _planInView(LatLng? center) {
  if (center == null) {
    return false;
  }
  final route = Storage().route;
  bool any(List<LatLng> path) => clipPathToView(_planOffsets(center, path)).isNotEmpty;
  return any(route.getPathPassed()) || any(route.getPathCurrent()) || any(route.getPathNext());
}

/// 3D Class B/C/D shelves and obstacles.
///
/// The long-press tab passes [center] and [showPressPoint]. The menu screen
/// sets [followAircraft], [showTerrain], and [showTraffic] on this same view.
/// Drag rotates, a pinch zooms, and two fingers pan.
class Airspace3DView extends StatefulWidget {
  /// Locked center. Null when [followAircraft] chooses the center from GPS.
  final LatLng? center;

  /// Live ownship. Drawn only when it is inside the 25 NM view.
  final ValueListenable<Position>? ownship;

  /// Yellow stem at the center. Used for the long-press point only.
  final bool showPressPoint;

  /// Keep the scene on the aircraft and slide it forward after about 8 NM.
  final bool followAircraft;

  /// Draw downloaded elevation under the shelves.
  final bool showTerrain;

  /// Draw ADS-B targets as dots.
  final bool showTraffic;

  const Airspace3DView({
    super.key,
    this.center,
    this.ownship,
    this.showPressPoint = false,
    this.followAircraft = false,
    this.showTerrain = false,
    this.showTraffic = false,
  });

  /// Seeds the in-memory shelf cache so a test can open the view without the database path.
  @visibleForTesting
  static void debugSetScene(LatLng center, AirspaceScene? scene) {
    _Airspace3DViewState._cacheKey =
        scene == null ? null : '${center.latitude.toStringAsFixed(4)},${center.longitude.toStringAsFixed(4)}';
    _Airspace3DViewState._cache = scene;
  }

  @override
  State<Airspace3DView> createState() => _Airspace3DViewState();
}

class _Airspace3DViewState extends State<Airspace3DView> {
  static const double _pitch0 = 0.85;
  static const double _yaw0 = 0.55;
  static const int _terrainGrid = 17;
  static const double _recenterNm = 8;
  static String? _cacheKey;
  static AirspaceScene? _cache;

  AirspaceScene? _scene;
  bool _loading = true;
  LatLng? _center;
  _AirspaceTerrain? _terrain;
  List<_AirspaceTrafficDot> _traffic = const [];
  int _terrainGeneration = 0;
  double _pitch = _pitch0;
  double _yaw = _yaw0;
  double _zoom = 1;
  double _panX = 0;
  double _panY = 0;
  double _lastScale = 1;
  Offset? _lastFocal;
  int _pointers = 0;
  bool _tfrListening = false;

  /// Shared by the long-press tab and the menu screen. On means that part is drawn.
  static bool _showB = true;
  static bool _showC = true;
  static bool _showD = true;
  static bool _showTfr = true;
  static bool _showGame = true;
  static bool _showPlan = true;
  static bool _showObstacles = true;
  static bool _showSua = true;
  static bool _showTerrain = true;

  @override
  void initState() {
    super.initState();
    _attachTfr();
    _center = widget.center;
    if (widget.followAircraft) {
      Storage().gpsChange.addListener(_onGps);
    }
    if (widget.showTraffic) {
      Storage().trafficChange.addListener(_onTraffic);
    }
    if (widget.followAircraft) {
      _onGps();
      if (_center == null) {
        _loading = false;
      }
      return;
    }
    if (_center == null) {
      _loading = false;
      return;
    }
    final cached = _cached(_placeKey);
    if (cached != null) {
      _scene = cached;
      _loading = false;
    } else {
      _load();
    }
    if (widget.showTerrain) {
      _loadTerrain(_center!);
    }
  }

  @override
  void dispose() {
    if (_tfrListening) {
      Storage().tfr.change.removeListener(_onTfr);
    }
    if (widget.followAircraft) {
      Storage().gpsChange.removeListener(_onGps);
    }
    if (widget.showTraffic) {
      Storage().trafficChange.removeListener(_onTraffic);
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(Airspace3DView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.followAircraft || widget.center == null || oldWidget.center == null) {
      return;
    }
    if (oldWidget.center!.latitude == widget.center!.latitude &&
        oldWidget.center!.longitude == widget.center!.longitude) {
      return;
    }
    _center = widget.center;
    if (widget.showTerrain) {
      _loadTerrain(_center!);
    }
    final cached = _cached(_placeKey);
    if (cached != null) {
      _scene = cached;
      _loading = false;
      return;
    }
    _loading = true;
    _scene = null;
    _load();
  }

  void _attachTfr() {
    try {
      Storage().tfr.change.addListener(_onTfr);
      _tfrListening = true;
    } catch (_) {
      _tfrListening = false;
    }
  }

  void _onTfr() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onGps() {
    if (!widget.followAircraft || !mounted) {
      return;
    }
    final pos = Storage().gpsChange.value;
    if (Gps.isPositionCloseToZero(pos)) {
      return;
    }
    final here = LatLng(pos.latitude, pos.longitude);
    final center = _center;
    if (center != null) {
      final offset = ownshipOffsetNm(center, here);
      if (offset != null && offset.e * offset.e + offset.n * offset.n < _recenterNm * _recenterNm) {
        return;
      }
    }
    setState(() {
      _center = here;
      _loading = true;
      _scene = null;
    });
    _load();
    if (widget.showTerrain) {
      _loadTerrain(here);
    }
    _onTraffic();
  }

  Future<void> _loadTerrain(LatLng center) async {
    final generation = ++_terrainGeneration;
    final cosLat = math.cos(center.latitude * math.pi / 180).abs().clamp(0.2, 1.0);
    final points = <LatLng>[];
    for (var row = 0; row < _terrainGrid; row++) {
      final north = -airspaceViewRadiusNm + 2 * airspaceViewRadiusNm * row / (_terrainGrid - 1);
      for (var col = 0; col < _terrainGrid; col++) {
        final east = -airspaceViewRadiusNm + 2 * airspaceViewRadiusNm * col / (_terrainGrid - 1);
        points.add(LatLng(
          center.latitude + north / 60.0,
          center.longitude + east / (60.0 * cosLat),
        ));
      }
    }
    final heights = await ElevationCache.getElevationOfPoints(points);
    if (!mounted || generation != _terrainGeneration) {
      return;
    }
    setState(() {
      _terrain = heights.every((height) => height == null)
          ? null
          : _AirspaceTerrain(cols: _terrainGrid, rows: _terrainGrid, elevFt: heights);
    });
  }

  void _onTraffic() {
    final center = _center;
    if (!widget.showTraffic || !mounted || center == null) {
      return;
    }
    final dots = <_AirspaceTrafficDot>[];
    for (final target in Storage().trafficCache.getTraffic()) {
      final offset = ownshipOffsetNm(center, target.message.coordinates);
      if (offset == null) {
        continue;
      }
      final altitude = target.message.altitude;
      dots.add(_AirspaceTrafficDot(
        eastNm: offset.e,
        northNm: offset.n,
        altitudeFt: altitude < -200 ? 0 : altitude,
        threat: target.isThreat,
      ));
    }
    setState(() => _traffic = dots);
  }

  int _generation = 0;

  String get _placeKey {
    final center = _center;
    if (center == null) {
      return '';
    }
    return '${center.latitude.toStringAsFixed(4)},${center.longitude.toStringAsFixed(4)}';
  }

  static AirspaceScene? _cached(String key) {
    if (_cache != null && _cacheKey == key) {
      return _cache;
    }
    return null;
  }

  Future<void> _load() async {
    final center = _center;
    if (center == null) {
      return;
    }
    final generation = ++_generation;
    final key = _placeKey;
    final path = PathUtils.getFilePath(
      Storage().dataDir,
      PathUtils.getFilePath('maps', 'nasr.mbtiles'),
    );
    AirspaceScene scene;
    if (!File(path).existsSync()) {
      scene = const AirspaceScene(
        radiusNm: airspaceViewRadiusNm,
        shelves: [],
        message: 'Vector Map is not downloaded.',
      );
    } else {
      // Yield so the progress indicator can paint before the tile decode.
      scene = await Future(() => loadClassAirspace(path, center));
      if (scene.message == null) {
        final obstacles = await loadObstacles(
          PathUtils.getFilePath(Storage().dataDir, 'main.db'),
          center,
        );
        scene = scene.copyWith(obstacles: obstacles);
      }
    }
    if (!mounted || generation != _generation) {
      return;
    }
    if (scene.message == null) {
      _cache = scene;
      _cacheKey = key;
    }
    setState(() {
      _scene = scene;
      _loading = false;
    });
  }

  void _reset() {
    setState(() {
      _pitch = _pitch0;
      _yaw = _yaw0;
      _zoom = 1;
      _panX = 0;
      _panY = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.followAircraft && _center == null) {
      return Center(
        child: Text(
          'Waiting for a GPS position.',
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
      );
    }
    final scene = _scene;
    if (_loading || scene == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (scene.message != null) {
      return _message(context, scene.message!);
    }
    if (scene.shelves.isEmpty &&
        scene.obstacles.isEmpty &&
        !widget.followAircraft &&
        !_planInView(_center) &&
        !_layerOn('TFR') &&
        !_layerOn(GameTfr.layerName)) {
      return _message(context, 'No Class B, C, or D, restricted, warning, prohibited, or MOA airspace within ${airspaceViewRadiusNm.round()} NM');
    }

    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (details) {
              _lastScale = 1;
              _lastFocal = details.focalPoint;
              _pointers = details.pointerCount;
            },
            onScaleUpdate: (details) {
              if (details.pointerCount != _pointers) {
                _pointers = details.pointerCount;
                _lastFocal = details.focalPoint;
                _lastScale = details.scale;
                return;
              }
              setState(() {
                final focal = _lastFocal;
                if (details.pointerCount <= 1) {
                  if (focal != null) {
                    final delta = details.focalPoint - focal;
                    _yaw += delta.dx * 0.01;
                    _pitch = (_pitch + delta.dy * 0.008).clamp(0.2, 1.35);
                  }
                } else {
                  if ((details.scale - _lastScale).abs() > 0.0001 && _lastScale != 0) {
                    _zoom = (_zoom * details.scale / _lastScale).clamp(0.4, 8.0);
                  }
                  _lastScale = details.scale;
                  if (focal != null) {
                    final delta = details.focalPoint - focal;
                    _panX += delta.dx;
                    _panY += delta.dy;
                  }
                }
                _lastFocal = details.focalPoint;
              });
            },
            onScaleEnd: (_) {
              _lastFocal = null;
              _pointers = 0;
            },
            child: _canvas(scene, dark, scheme),
          ),
        ),
        _filters(scheme),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Drag to rotate · pinch to zoom · two fingers to pan · ${airspaceViewRadiusNm.round()} NM',
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
              ),
              TextButton(onPressed: _reset, child: const Text('Reset')),
            ],
          ),
        ),
      ],
    );
  }

  /// Meters to feet, matching the shelf altitudes. Independent of display units.
  static const double _metersToFeet = 3.28084;

  Widget _canvas(AirspaceScene scene, bool dark, ColorScheme scheme) {
    final center = _center;
    if (center == null) {
      return const SizedBox.expand();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
      painter: _AirspacePainter(
        scene: scene,
        center: center,
        ownship: widget.followAircraft ? Storage().gpsChange : widget.ownship,
        showPressPoint: widget.showPressPoint,
        pitch: _pitch,
        yaw: _yaw,
        zoom: _zoom,
        panX: _panX,
        panY: _panY,
        background: dark ? const Color(0xFF12171C) : const Color(0xFFEEF3F8),
        gridColor: scheme.outline.withAlpha(110),
        axisColor: scheme.onSurface.withAlpha(200),
        hereColor: const Color(0xFFFF9800),
        terrain: _terrain,
        traffic: _traffic,
        showClassB: _showB,
        showClassC: _showC,
        showClassD: _showD,
        showTfr: _showTfr,
        showGame: _showGame,
        showPlan: _showPlan,
        showObstacles: _showObstacles,
        showSua: _showSua,
        showTerrainMesh: _showTerrain,
      ),
          child: const SizedBox.expand(),
        ),
        _OwnshipPulse(
          center: center,
          ownship: widget.followAircraft ? Storage().gpsChange : widget.ownship,
          maxAltitudeFt: airspaceScaleAltitude(
            scene.maxAltitudeFt,
            _showTerrain ? _terrain?.elevFt ?? const <double?>[] : const <double?>[],
          ),
          radiusNm: scene.radiusNm,
          pitch: _pitch,
          yaw: _yaw,
          zoom: _zoom,
          panX: _panX,
          panY: _panY,
        ),
      ],
    );
  }

  Widget _filters(ColorScheme scheme) {
    Widget chip(String label, bool on, Color color, void Function(bool) set) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FilterChip(
          label: Text(label),
          selected: on,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          selectedColor: color,
          labelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: on ? Colors.white : scheme.onSurface,
          ),
          onSelected: (value) => setState(() => set(value)),
        ),
      );
    }

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          chip('B', _showB, _classColor('B'), (value) => _showB = value),
          chip('C', _showC, _classColor('C'), (value) => _showC = value),
          chip('D', _showD, _classColor('D'), (value) => _showD = value),
          chip('SUA', _showSua, _classColor('MOA'), (value) => _showSua = value),
          chip('TFR', _showTfr, Constants.tfrColor, (value) => _showTfr = value),
          chip('Game', _showGame, GameTfr.borderColor, (value) => _showGame = value),
          chip('Plan', _showPlan, Constants.planCurrentColor, (value) => _showPlan = value),
          chip('Obstacles', _showObstacles, const Color(0xFFE53935), (value) => _showObstacles = value),
          chip('Terrain', _showTerrain, const Color(0xFF5D4037), (value) => _showTerrain = value),
        ],
      ),
    );
  }

  Widget _message(BuildContext context, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.view_in_ar_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }

}

Color _classColor(String cls) {
  switch (cls) {
    case 'B':
      return const Color(0xFF0000FF);
    case 'C':
      return const Color(0xFFFF00FF);
    case 'D':
      return const Color(0xFF0088FF);
    case 'RESTRICTED':
      return const Color(0xFFFF1744);
    case 'WARNING':
      return const Color(0xFF8B4513);
    case 'PROHIBITED':
      return const Color(0xFF6A1B9A);
    case 'MOA':
      return const Color(0xFF827717);
    default:
      return Colors.grey;
  }
}

class _Ownship {
  final NmPoint offset;
  final double altFt;

  const _Ownship(this.offset, this.altFt);
}

/// Shelf tops, or the terrain when the ground is higher, so a slab on the ground stays in frame.
@visibleForTesting
double airspaceScaleAltitude(double shelfMaxFt, Iterable<double?> terrainFt) {
  var maxFt = shelfMaxFt;
  for (final height in terrainFt) {
    if (height != null && height.isFinite && height > maxFt) {
      maxFt = height;
    }
  }
  return maxFt;
}

/// Same camera for the airspace and the pulsing ownship dot.
_Proj _projectView(
  Size size,
  double east,
  double north,
  double altFt, {
  required double radius,
  required double maxAlt,
  required double pitch,
  required double yaw,
  required double zoom,
  required double panX,
  required double panY,
}) {
  final altScale = radius * 0.72 / maxAlt;
  final cosY = math.cos(yaw);
  final sinY = math.sin(yaw);
  final cosP = math.cos(pitch);
  final sinP = math.sin(pitch);
  final s = math.min(size.width, size.height) * 0.36 * zoom;
  const camera = 3.2;
  final x = east / radius;
  final z = north / radius;
  final y = altFt * altScale / radius;
  final x1 = x * cosY - z * sinY;
  final z1 = x * sinY + z * cosY;
  final y2 = y * cosP + z1 * sinP;
  final z2 = -y * sinP + z1 * cosP;
  final persp = camera / (camera + z2);
  return _Proj(
    size.width / 2 + x1 * s * persp + panX,
    size.height / 2 - y2 * s * persp + panY,
    z2,
  );
}

class _Proj {
  final double x;
  final double y;
  final double depth;

  const _Proj(this.x, this.y, this.depth);

  Offset get o => Offset(x, y);
}

class _Face {
  final double depth;
  final void Function(Canvas canvas) draw;

  const _Face(this.depth, this.draw);
}

class _AirspacePainter extends CustomPainter {
  final AirspaceScene scene;
  final LatLng center;
  final ValueListenable<Position>? ownship;
  final bool showPressPoint;
  final double pitch;
  final double yaw;
  final double zoom;
  final double panX;
  final double panY;
  final Color background;
  final Color gridColor;
  final Color axisColor;
  final Color hereColor;
  final _AirspaceTerrain? terrain;
  final List<_AirspaceTrafficDot> traffic;
  final bool showClassB;
  final bool showClassC;
  final bool showClassD;
  final bool showTfr;
  final bool showGame;
  final bool showPlan;
  final bool showObstacles;
  final bool showSua;
  final bool showTerrainMesh;

  _AirspacePainter({
    required this.scene,
    required this.center,
    required this.ownship,
    required this.showPressPoint,
    required this.pitch,
    required this.yaw,
    required this.zoom,
    required this.panX,
    required this.panY,
    required this.background,
    required this.gridColor,
    required this.axisColor,
    required this.hereColor,
    required this.terrain,
    required this.traffic,
    required this.showClassB,
    required this.showClassC,
    required this.showClassD,
    required this.showTfr,
    required this.showGame,
    required this.showPlan,
    required this.showObstacles,
    required this.showSua,
    required this.showTerrainMesh,
  }) : super(repaint: Listenable.merge([ownship, Storage().route.change, Storage().area.change]));

  /// Current ownship in this view, or null when it has no fix or is outside 25 NM.
  _Ownship? get _liveOwnship {
    final feed = ownship;
    if (feed == null) {
      return null;
    }
    final pos = feed.value;
    if (Gps.isPositionCloseToZero(pos)) {
      return null;
    }
    final offset = ownshipOffsetNm(center, LatLng(pos.latitude, pos.longitude));
    if (offset == null) {
      return null;
    }
    final alt = pos.altitude * _Airspace3DViewState._metersToFeet;
    return _Ownship(offset, alt.isFinite && alt > 0 ? alt : 0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final radius = scene.radiusNm;
    final maxAlt = airspaceScaleAltitude(
      scene.maxAltitudeFt,
      showTerrainMesh ? terrain?.elevFt ?? const <double?>[] : const <double?>[],
    );

    _Proj project(double east, double north, double altFt) {
      return _projectView(
        size,
        east,
        north,
        altFt,
        radius: radius,
        maxAlt: maxAlt,
        pitch: pitch,
        yaw: yaw,
        zoom: zoom,
        panX: panX,
        panY: panY,
      );
    }

    _drawGround(canvas, project, radius);
    _drawAxis(canvas, project, radius, maxAlt);

    final faces = <_Face>[];
    for (final shelf in scene.shelves) {
      if (_classOn(shelf.airspaceClass)) {
        _addShelf(faces, project, shelf);
      }
    }
    _addEnabledAreas(faces, project, maxAlt);
    _addGlideCone(faces, project, maxAlt);
    _addTerrain(faces, project);
    faces.sort((a, b) => b.depth.compareTo(a.depth));
    for (final face in faces) {
      face.draw(canvas);
    }
    _drawGrid(canvas, project, radius);

    if (showPressPoint) {
      _drawHere(canvas, project, maxAlt);
    }
    if (showObstacles) {
      _drawObstacles(canvas, project);
    }
    _drawAirports(canvas, project);
    for (final shelf in scene.shelves) {
      if (_classOn(shelf.airspaceClass) && shelf.showLabel && shelf.rings.isNotEmpty) {
        _drawLabel(canvas, project, shelf);
      }
    }
    if (showPlan) {
      _drawPlan(canvas, project, maxAlt);
    }
    _drawGlide(canvas, project, maxAlt);
    _drawTraffic(canvas, project, maxAlt);
  }

  void _drawGround(Canvas canvas, _Proj Function(double, double, double) project, double radius) {
    final corners = [
      project(-radius, -radius, 0),
      project(radius, -radius, 0),
      project(radius, radius, 0),
      project(-radius, radius, 0),
    ];
    final ground = ui.Path()..moveTo(corners[0].x, corners[0].y);
    for (final c in corners.skip(1)) {
      ground.lineTo(c.x, c.y);
    }
    ground.close();
    if (terrain == null || !showTerrainMesh) {
      canvas.drawPath(ground, Paint()..color = gridColor.withAlpha(28));
    }
  }

  /// 5 NM reference drawn on the surface, after the mesh, so the lines follow the hills.
  void _drawGrid(Canvas canvas, _Proj Function(double, double, double) project, double radius) {
    final mesh = showTerrainMesh ? terrain : null;
    double heightAt(double east, double north) {
      if (mesh == null) {
        return 0;
      }
      return sampleTerrainFt(mesh.elevFt, mesh.cols, mesh.rows, east, north, radius) ?? 0;
    }

    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = gridColor;
    final steps = mesh == null ? 1 : math.max(1, mesh.cols - 1);
    void stroke(double e0, double n0, double e1, double n1) {
      Offset? previous;
      for (var i = 0; i <= steps; i++) {
        final t = i / steps;
        final east = e0 + (e1 - e0) * t;
        final north = n0 + (n1 - n0) * t;
        final at = project(east, north, heightAt(east, north));
        if (previous != null) {
          canvas.drawLine(previous, at.o, grid);
        }
        previous = at.o;
      }
    }

    for (var g = -radius; g <= radius + 0.01; g += 5) {
      stroke(-radius, g, radius, g);
      stroke(g, -radius, g, radius);
    }

    final north = project(0, radius, heightAt(0, radius));
    _text(canvas, 'N', north.o, axisColor, 12, FontWeight.w700);
    final scaleA = project(-radius, radius, heightAt(-radius, radius));
    final scaleB = project(-radius + 5, radius, heightAt(-radius + 5, radius));
    canvas.drawLine(scaleA.o, scaleB.o, Paint()..color = axisColor..strokeWidth = 2);
    _text(canvas, '5 NM', Offset((scaleA.x + scaleB.x) / 2, (scaleA.y + scaleB.y) / 2 - 12), axisColor, 10, FontWeight.w500);
  }

  /// Opaque ground cells, sorted with the shelves and the glide cone.
  /// A cell with one missing sample is still drawn from the other three corners.
  void _addTerrain(List<_Face> faces, _Proj Function(double, double, double) project) {
    final mesh = terrain;
    if (!showTerrainMesh || mesh == null || mesh.cols < 2 || mesh.rows < 2) {
      return;
    }
    var minFt = double.infinity;
    var maxFt = -double.infinity;
    for (final height in mesh.elevFt) {
      if (height == null) {
        continue;
      }
      minFt = math.min(minFt, height);
      maxFt = math.max(maxFt, height);
    }
    if (minFt == double.infinity) {
      return;
    }
    final ownAlt = _liveOwnship?.altFt;
    final radius = scene.radiusNm;
    for (var row = 0; row < mesh.rows - 1; row++) {
      for (var col = 0; col < mesh.cols - 1; col++) {
        final i00 = row * mesh.cols + col;
        final heights = [
          mesh.elevFt[i00],
          mesh.elevFt[i00 + 1],
          mesh.elevFt[i00 + mesh.cols + 1],
          mesh.elevFt[i00 + mesh.cols],
        ];
        final corners = <List<num>>[
          [col, row, heights[0] ?? -1],
          [col + 1, row, heights[1] ?? -1],
          [col + 1, row + 1, heights[2] ?? -1],
          [col, row + 1, heights[3] ?? -1],
        ];
        final known = <int>[
          for (var i = 0; i < corners.length; i++)
            if (heights[i] != null) i,
        ];
        if (known.length < 3) {
          continue;
        }
        final used = known.length == 4 ? const [0, 1, 2, 3] : known;
        final path = ui.Path();
        var depth = 0.0;
        var top = -double.infinity;
        for (var i = 0; i < used.length; i++) {
          final corner = corners[used[i]];
          final east = -radius + 2 * radius * corner[0] / (mesh.cols - 1);
          final north = -radius + 2 * radius * corner[1] / (mesh.rows - 1);
          final elevFt = corner[2].toDouble();
          final at = project(east, north, elevFt);
          depth += at.depth;
          if (elevFt > top) {
            top = elevFt;
          }
          if (i == 0) {
            path.moveTo(at.x, at.y);
          } else {
            path.lineTo(at.x, at.y);
          }
        }
        path.close();
        final color = _terrainColor(top, ownAlt, minFt, maxFt);
        final fill = Paint()..color = color;
        final edge = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = Color.lerp(color, Colors.black, 0.28)!;
        faces.add(_Face(depth / used.length, (canvas) {
          canvas.drawPath(path, fill);
          canvas.drawPath(path, edge);
        }));
      }
    }
  }

  Color _terrainColor(double elevFt, double? ownAltFt, double minFt, double maxFt) {
    if (ownAltFt != null && elevFt >= ownAltFt - 500) {
      return const Color(0xCCFF0000);
    }
    final span = math.max(400.0, maxFt - minFt);
    final shade = ((elevFt - minFt) / span).clamp(0.0, 1.0);
    return Color.lerp(const Color(0xFF3E2723), const Color(0xFFEFEBE9), shade)!;
  }

  void _drawTraffic(Canvas canvas, _Proj Function(double, double, double) project, double maxAlt) {
    final fill = Paint();
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.black;
    for (final dot in traffic) {
      final at = project(dot.eastNm, dot.northNm, dot.altitudeFt.clamp(0, maxAlt));
      fill.color = dot.threat ? Constants.trafficColorAlert : Constants.trafficColor;
      canvas.drawCircle(at.o, 4.5, fill);
      canvas.drawCircle(at.o, 4.5, outline);
    }
  }

  void _drawAxis(Canvas canvas, _Proj Function(double, double, double) project, double radius, double maxAlt) {
    final paint = Paint()
      ..color = axisColor
      ..strokeWidth = 1.2;
    final bottom = project(-radius, -radius, 0);
    final top = project(-radius, -radius, maxAlt);
    canvas.drawLine(bottom.o, top.o, paint);
    final step = maxAlt > 15000 ? 5000.0 : (maxAlt > 8000 ? 2500.0 : 1000.0);
    for (var ft = 0.0; ft <= maxAlt + 1; ft += step) {
      final p = project(-radius, -radius, ft);
      final tick = project(-radius + 1.2, -radius, ft);
      canvas.drawLine(p.o, tick.o, paint);
      final thousands = ft / 1000;
      final label = ft <= 0
          ? 'SF'
          : (thousands == thousands.roundToDouble() ? '${thousands.round()}k' : '${thousands.toStringAsFixed(1)}k');
      _text(canvas, label, p.o + const Offset(-28, -6), axisColor, 10, FontWeight.w500);
    }
  }

  bool _classOn(String cls) {
    switch (cls) {
      case 'B':
        return showClassB;
      case 'C':
        return showClassC;
      case 'D':
        return showClassD;
      default:
        return showSua;
    }
  }

  void _addEnabledAreas(List<_Face> faces, _Proj Function(double, double, double) project, double maxAlt) {
    if (showTfr && _layerOn('TFR')) {
      try {
        for (final weather in Storage().tfr.getAll()) {
          final tfr = weather as Tfr;
          if (!tfr.isRelevant() || tfr.coordinates.length < 3) {
            continue;
          }
          final lower = parseTfrLevel(tfr.lowerAltitude);
          final upper = parseTfrLevel(tfr.upperAltitude);
          final floor = lower?.feet ?? 0;
          final ceiling = upper == null || upper.unlimited ? maxAlt : upper.feet;
          final ring = clipPolygon(_planOffsets(center, tfr.coordinates), scene.radiusNm);
          final color = tfr.isInEffect() ? Constants.tfrColor : Constants.tfrColorFuture;
          if (tfrAboveScale(lower, maxAlt)) {
            _addAboveScaleArrows(faces, project, ring, maxAlt, color);
            continue;
          }
          _addPrism(
            faces,
            project,
            ring,
            floor,
            ceiling,
            color,
            floorAgl: lower?.agl ?? false,
            ceilingAgl: upper != null && !upper.unlimited && upper.agl,
          );
        }
      } catch (_) {}
    }
    if (!showGame || !_layerOn(GameTfr.layerName)) {
      return;
    }
    const radiusNm = 3.0;
    for (final venue in GameTfr.locations) {
      final at = ownshipOffsetNm(center, LatLng(venue.latitude, venue.longitude), radiusNm: null);
      if (at == null || at.e.abs() > scene.radiusNm + radiusNm || at.n.abs() > scene.radiusNm + radiusNm) {
        continue;
      }
      final mesh = terrain;
      final ground = mesh == null
          ? 0.0
          : (sampleTerrainFt(mesh.elevFt, mesh.cols, mesh.rows, at.e, at.n, scene.radiusNm) ?? 0);
      final floor = ground.clamp(0.0, maxAlt).toDouble();
      final ceiling = (floor + 3000).clamp(floor, maxAlt).toDouble();
      final ring = <NmPoint>[];
      for (var step = 0; step < 24; step++) {
        final angle = step * math.pi * 2 / 24;
        ring.add(NmPoint(at.e + radiusNm * math.sin(angle), at.n + radiusNm * math.cos(angle)));
      }
      _addPrism(faces, project, clipPolygon(ring, scene.radiusNm), floor, ceiling, GameTfr.borderColor);
    }
  }

  /// Terrain under [east]/[north], or 0 when the mesh has no sample.
  double _groundFt(double east, double north) {
    final mesh = showTerrainMesh ? terrain : null;
    if (mesh == null) {
      return 0;
    }
    return sampleTerrainFt(mesh.elevFt, mesh.cols, mesh.rows, east, north, scene.radiusNm) ?? 0;
  }

/// MSL stays a fixed altitude, lifted to the ground when the hill is higher.
/// AGL stays that many feet above the ground, including above the shelf scale.
double _tfrLevel(double east, double north, double feet, bool agl) {
  final ground = _groundFt(east, north);
  if (agl) {
    return tfrLevelFeet(feet, agl: true, groundFt: ground);
  }
  return math.max(feet, ground).clamp(0.0, scene.maxAltitudeFt).toDouble();
}

  /// Published MSL altitude, or the terrain when the ground is higher.
  double _onSurface(double east, double north, double mslFt) {
    final mesh = showTerrainMesh ? terrain : null;
    if (mesh == null) {
      return mslFt;
    }
    return airspaceAboveGround(
      mslFt,
      sampleTerrainFt(mesh.elevFt, mesh.cols, mesh.rows, east, north, scene.radiusNm),
    );
  }

  /// Floor of a volume. With terrain, each piece sits on the ground and stops at the ceiling.
  void _addDrapedFloor(
    List<_Face> faces,
    _Proj Function(double, double, double) project,
    List<List<NmPoint>> rings,
    double floorFt,
    double ceilingFt,
    Color color,
    int alpha, {
    double Function(double east, double north)? floorAt,
    double Function(double east, double north)? ceilingAt,
  }) {
    final mesh = showTerrainMesh ? terrain : null;
    if (mesh == null) {
      _addFlatCap(faces, project, rings, floorFt, color, alpha, stroke: true);
      return;
    }
    final step = scene.radiusNm / 16;
    var minE = double.infinity;
    var maxE = -double.infinity;
    var minN = double.infinity;
    var maxN = -double.infinity;
    for (final ring in rings) {
      for (final point in ring) {
        minE = math.min(minE, point.e);
        maxE = math.max(maxE, point.e);
        minN = math.min(minN, point.n);
        maxN = math.max(maxN, point.n);
      }
    }
    if (minE == double.infinity) {
      return;
    }
    final fill = Paint()..color = color.withAlpha(alpha)..style = PaintingStyle.fill;
    for (var north = minN; north < maxN; north += step) {
      for (var east = minE; east < maxE; east += step) {
        final mid = NmPoint(east + step / 2, north + step / 2);
        if (!polygonContains(rings, mid.e, mid.n)) {
          continue;
        }
        List<NmPoint>? clip;
        var clipArea = double.infinity;
        for (final ring in rings) {
          if (!polygonContains([ring], mid.e, mid.n)) {
            continue;
          }
          final area = _ringArea(ring).abs();
          if (area < clipArea) {
            clipArea = area;
            clip = ring;
          }
        }
        if (clip == null) {
          continue;
        }
        final piece = clipRingToRing([
          NmPoint(east, north),
          NmPoint(east + step, north),
          NmPoint(east + step, north + step),
          NmPoint(east, north + step),
        ], clip);
        if (piece.length < 3) {
          continue;
        }
        final path = ui.Path();
        var depth = 0.0;
        var buried = true;
        for (var i = 0; i < piece.length; i++) {
          final point = piece[i];
          final cap = ceilingAt?.call(point.e, point.n) ?? ceilingFt;
          final raw = floorAt?.call(point.e, point.n) ?? _onSurface(point.e, point.n, floorFt);
          final height = math.min(raw, cap);
          if (height < cap - 1) {
            buried = false;
          }
          final at = project(point.e, point.n, height);
          depth += at.depth;
          if (i == 0) {
            path.moveTo(at.x, at.y);
          } else {
            path.lineTo(at.x, at.y);
          }
        }
        if (buried) {
          continue;
        }
        path.close();
        final drawn = path;
        faces.add(_Face(depth / piece.length - 0.004, (canvas) {
          canvas.drawPath(drawn, fill);
        }));
      }
    }
  }

  void _addFlatCap(
    List<_Face> faces,
    _Proj Function(double, double, double) project,
    List<List<NmPoint>> rings,
    double altFt,
    Color color,
    int alpha, {
    required bool stroke,
  }) {
    final path = ui.Path()..fillType = PathFillType.evenOdd;
    var depth = 0.0;
    var count = 0;
    for (final ring in rings) {
      if (ring.length < 3) {
        continue;
      }
      for (var i = 0; i < ring.length; i++) {
        final at = project(ring[i].e, ring[i].n, altFt);
        depth += at.depth;
        count++;
        if (i == 0) {
          path.moveTo(at.x, at.y);
        } else {
          path.lineTo(at.x, at.y);
        }
      }
      path.close();
    }
    if (count == 0) {
      return;
    }
    final fill = Paint()..color = color.withAlpha(alpha)..style = PaintingStyle.fill;
    final edge = Paint()
      ..color = color.withAlpha(230)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    faces.add(_Face(depth / count, (canvas) {
      canvas.drawPath(path, fill);
      if (stroke) {
        canvas.drawPath(path, edge);
      }
    }));
  }

  /// Walls from the ground (or the published floor, whichever is higher) up to [ceilingFt].
  void _addLiftedWalls(
    List<_Face> faces,
    _Proj Function(double, double, double) project,
    List<List<NmPoint>> rings,
    List<bool> hidden,
    double floorFt,
    double ceilingFt,
    Color color,
    int alpha, {
    double Function(double east, double north)? floorAt,
    double Function(double east, double north)? ceilingAt,
  }) {
    final wall = Paint()..style = PaintingStyle.fill;
    for (final ring in rings) {
      if (ring.length < 2) {
        continue;
      }
      for (var i = 0; i < ring.length; i++) {
        if (i < hidden.length && hidden[i]) {
          continue;
        }
        final a = ring[i];
        final b = ring[(i + 1) % ring.length];
        final de = b.e - a.e;
        final dn = b.n - a.n;
        final len = math.sqrt(de * de + dn * dn);
        var shade = 0.72;
        if (len > 1e-6) {
          final nx = dn / len;
          final nz = -de / len;
          shade = (0.55 + 0.45 * (nx * 0.65 + nz * 0.75).abs()).clamp(0.45, 1.0);
        }
        final side = Color.lerp(Colors.black, color, shade)!.withAlpha(alpha);
        final steps = math.max(1, (len / 0.75).ceil());
        for (var step = 0; step < steps; step++) {
          final t0 = step / steps;
          final t1 = (step + 1) / steps;
          final e0 = a.e + de * t0;
          final n0 = a.n + dn * t0;
          final e1 = a.e + de * t1;
          final n1 = a.n + dn * t1;
          final cap0 = ceilingAt?.call(e0, n0) ?? ceilingFt;
          final cap1 = ceilingAt?.call(e1, n1) ?? ceilingFt;
          final h0 = math.min(cap0, floorAt?.call(e0, n0) ?? _onSurface(e0, n0, floorFt));
          final h1 = math.min(cap1, floorAt?.call(e1, n1) ?? _onSurface(e1, n1, floorFt));
          if (h0 >= cap0 - 1 && h1 >= cap1 - 1) {
            continue;
          }
          final p1 = project(e0, n0, h0);
          final p2 = project(e1, n1, h1);
          final p3 = project(e1, n1, cap1);
          final p4 = project(e0, n0, cap0);
          final path = ui.Path()
            ..moveTo(p1.x, p1.y)
            ..lineTo(p2.x, p2.y)
            ..lineTo(p3.x, p3.y)
            ..lineTo(p4.x, p4.y)
            ..close();
          final depth = (p1.depth + p2.depth + p3.depth + p4.depth) / 4 - 0.004;
          faces.add(_Face(depth, (canvas) {
            wall.color = side;
            canvas.drawPath(path, wall);
          }));
        }
      }
    }
  }

  /// Dashed footprint at the top of the picture, with arrows continuing up.
  void _addAboveScaleArrows(
    List<_Face> faces,
    _Proj Function(double, double, double) project,
    List<NmPoint> ring,
    double scaleFt,
    Color color,
  ) {
    if (ring.length < 3) {
      return;
    }
    var depth = 0.0;
    for (final point in ring) {
      depth += project(point.e, point.n, scaleFt).depth;
    }
    final count = math.min(6, ring.length);
    faces.add(_Face(depth / ring.length - 0.02, (canvas) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = color.withAlpha(230);
      for (var i = 0; i < ring.length; i++) {
        final a = project(ring[i].e, ring[i].n, scaleFt).o;
        final b = project(ring[(i + 1) % ring.length].e, ring[(i + 1) % ring.length].n, scaleFt).o;
        _dash(canvas, a, b, paint);
      }
      final rise = math.max(scaleFt * 0.12, 800);
      for (var mark = 0; mark < count; mark++) {
        final point = ring[(mark * ring.length / count).floor()];
        final base = project(point.e, point.n, scaleFt).o;
        final tip = project(point.e, point.n, scaleFt + rise).o;
        _upArrow(canvas, base, tip, color.withAlpha(230));
      }
    }));
  }

  void _addPrism(
    List<_Face> faces,
    _Proj Function(double, double, double) project,
    List<NmPoint> ring,
    double floorFt,
    double ceilingFt,
    Color color, {
    bool floorAgl = false,
    bool ceilingAgl = false,
  }) {
    if (ring.length < 3 || (!floorAgl && !ceilingAgl && ceilingFt <= floorFt)) {
      return;
    }
    double floorHere(double east, double north) => _tfrLevel(east, north, floorFt, floorAgl);
    double ceilingHere(double east, double north) => ceilingAgl
        ? _tfrLevel(east, north, ceilingFt, true)
        : math.min(ceilingFt, scene.maxAltitudeFt);
    void cap(double altFt, int alpha) {
      final path = ui.Path();
      var depth = 0.0;
      _Proj? first;
      for (final point in ring) {
        final at = project(point.e, point.n, altFt);
        depth += at.depth;
        if (first == null) {
          first = at;
          path.moveTo(at.x, at.y);
        } else {
          path.lineTo(at.x, at.y);
        }
      }
      path.close();
      final fill = Paint()..color = color.withAlpha(alpha)..style = PaintingStyle.fill;
      final stroke = Paint()
        ..color = color.withAlpha(230)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      faces.add(_Face(depth / ring.length, (canvas) {
        canvas.drawPath(path, fill);
        canvas.drawPath(path, stroke);
      }));
    }

    if (ceilingAgl) {
      _addDrapedFloor(
        faces,
        project,
        [ring],
        ceilingFt,
        double.infinity,
        color,
        130,
        floorAt: ceilingHere,
        ceilingAt: (east, north) => double.infinity,
      );
    } else {
      cap(math.min(ceilingFt, scene.maxAltitudeFt), 130);
    }
    _addDrapedFloor(
      faces,
      project,
      [ring],
      floorFt,
      ceilingFt,
      color,
      70,
      floorAt: floorHere,
      ceilingAt: ceilingHere,
    );
    _addLiftedWalls(
      faces,
      project,
      [ring],
      List.filled(ring.length, false),
      floorFt,
      ceilingFt,
      color,
      90,
      floorAt: floorHere,
      ceilingAt: ceilingHere,
    );
  }

  void _addShelf(List<_Face> faces, _Proj Function(double, double, double) project, AirspaceShelf shelf) {
    final color = _classColor(shelf.airspaceClass);
    final rings = shelf.rings;
    if (rings.isEmpty) {
      return;
    }
    final floorFt = math.min(shelf.floorFt, scene.maxAltitudeFt);
    final ceilingFt = math.min(shelf.ceilingFt, scene.maxAltitudeFt);
    if (ceilingFt <= floorFt) {
      return;
    }

    void cap(double altFt, int alpha) {
      final projected = <List<_Proj>>[];
      var depth = 0.0;
      var count = 0;
      final path = ui.Path()..fillType = PathFillType.evenOdd;
      final strokePath = ui.Path();
      for (final ring in rings) {
        final pts = <_Proj>[];
        for (final p in ring.points) {
          final q = project(p.e, p.n, altFt);
          pts.add(q);
          depth += q.depth;
          count++;
        }
        if (pts.length < 3) {
          continue;
        }
        projected.add(pts);
        path.moveTo(pts.first.x, pts.first.y);
        for (final q in pts.skip(1)) {
          path.lineTo(q.x, q.y);
        }
        path.close();
        for (var i = 0; i < pts.length; i++) {
          if (ring.hides(i)) {
            continue;
          }
          final a = pts[i];
          final b = pts[(i + 1) % pts.length];
          strokePath
            ..moveTo(a.x, a.y)
            ..lineTo(b.x, b.y);
        }
      }
      if (count == 0) {
        return;
      }
      final fill = Paint()..color = color.withAlpha(alpha)..style = PaintingStyle.fill;
      final stroke = Paint()
        ..color = color.withAlpha(230)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      faces.add(_Face(depth / count, (c) {
        c.drawPath(path, fill);
        c.drawPath(strokePath, stroke);
      }));
    }

    if (shelf.ceilingFt > airspaceDisplayCapFt || shelf.unlimitedCeiling) {
      _addClippedCrown(faces, project, rings, ceilingFt, color);
    } else {
      cap(ceilingFt, 150);
    }
    if (showTerrainMesh && terrain != null) {
      _addDrapedFloor(
        faces,
        project,
        [for (final ring in rings) ring.points],
        floorFt,
        ceilingFt,
        color,
        90,
      );
    } else {
      cap(floorFt, 90);
    }
    for (final ring in rings) {
      _addLiftedWalls(faces, project, [ring.points], ring.tileCut, floorFt, ceilingFt, color, 120);
    }
  }

  /// Open top plus a short fading stack, so a shelf above 10,000 ft does not roof over the picture.
  void _addClippedCrown(
    List<_Face> faces,
    _Proj Function(double, double, double) project,
    List<AirspaceRing> rings,
    double clipFt,
    Color color,
  ) {
    final steps = <(double, int, bool)>[
      (clipFt, 230, true),
      (clipFt + scene.maxAltitudeFt * 0.06, 160, false),
      (clipFt + scene.maxAltitudeFt * 0.12, 90, false),
      (clipFt + scene.maxAltitudeFt * 0.18, 36, false),
    ];
    var depth = 0.0;
    var count = 0;
    for (final ring in rings) {
      for (final p in ring.points) {
        depth += project(p.e, p.n, clipFt).depth;
        count++;
      }
    }
    if (count == 0) {
      return;
    }
    faces.add(_Face(depth / count - 0.02, (canvas) {
      for (final step in steps) {
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = step.$3 ? 1.8 : 1.2
          ..color = color.withAlpha(step.$2);
        for (final ring in rings) {
          for (var i = 0; i < ring.points.length; i++) {
            if (ring.hides(i)) {
              continue;
            }
            final a = project(ring.points[i].e, ring.points[i].n, step.$1).o;
            final b = project(ring.points[(i + 1) % ring.points.length].e, ring.points[(i + 1) % ring.points.length].n, step.$1).o;
            if (step.$3) {
              _dash(canvas, a, b, paint);
            } else {
              canvas.drawLine(a, b, paint);
            }
          }
        }
      }
      var ring = rings.first;
      for (final candidate in rings.skip(1)) {
        if (candidate.points.length > ring.points.length) {
          ring = candidate;
        }
      }
      final marks = ring.points.length < 4 ? ring.points.length : 4;
      for (var m = 0; m < marks; m++) {
        final p = ring.points[(m * ring.points.length / marks).floor()];
        final base = project(p.e, p.n, clipFt).o;
        final tip = project(p.e, p.n, clipFt + scene.maxAltitudeFt * 0.16).o;
        _chevron(canvas, base, tip, color.withAlpha(220));
      }
    }));
  }

  void _dash(Canvas canvas, Offset a, Offset b, Paint paint) {
    final delta = b - a;
    final len = delta.distance;
    if (len < 1) {
      return;
    }
    final dir = delta / len;
    const dash = 8.0;
    const gap = 5.0;
    var t = 0.0;
    while (t < len) {
      final end = math.min(t + dash, len);
      canvas.drawLine(a + dir * t, a + dir * end, paint);
      t = end + gap;
    }
  }

  void _upArrow(Canvas canvas, Offset base, Offset tip, Color color) {
    final delta = tip - base;
    final len = delta.distance;
    if (len < 2) {
      return;
    }
    final u = delta / len;
    final n = Offset(-u.dy, u.dx);
    canvas.drawLine(
      base,
      tip,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    final path = ui.Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - u.dx * 9 + n.dx * 4.5, tip.dy - u.dy * 9 + n.dy * 4.5)
      ..lineTo(tip.dx - u.dx * 9 - n.dx * 4.5, tip.dy - u.dy * 9 - n.dy * 4.5)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _chevron(Canvas canvas, Offset base, Offset tip, Color color) {
    final delta = tip - base;
    final len = delta.distance;
    if (len < 2) {
      return;
    }
    final u = delta / len;
    final n = Offset(-u.dy, u.dx);
    final head = base + u * math.min(len, 18);
    final path = ui.Path()
      ..moveTo(head.dx, head.dy)
      ..lineTo(head.dx - u.dx * 9 + n.dx * 4.5, head.dy - u.dy * 9 + n.dy * 4.5)
      ..lineTo(head.dx - u.dx * 9 - n.dx * 4.5, head.dy - u.dy * 9 - n.dy * 4.5)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  /// Red line from the ground to the obstacle top.
  void _drawObstacles(Canvas canvas, _Proj Function(double, double, double) project) {
    final items = <({Offset foot, Offset top, double depth})>[];
    for (final obstacle in scene.obstacles) {
      final topFt = math.min(obstacle.heightFt, scene.maxAltitudeFt);
      final groundFt = _onSurface(obstacle.e, obstacle.n, 0);
      if (groundFt >= topFt - 1) {
        continue;
      }
      final ground = project(obstacle.e, obstacle.n, groundFt);
      final top = project(obstacle.e, obstacle.n, topFt);
      var foot = ground.o;
      var tip = top.o;
      final rise = tip - foot;
      if (rise.distance < 8) {
        final dir = rise.distance < 0.5 ? const Offset(0, -1) : rise / rise.distance;
        tip = foot + dir * 8;
      }
      items.add((foot: foot, top: tip, depth: (ground.depth + top.depth) / 2));
    }
    items.sort((a, b) => b.depth.compareTo(a.depth));
    final paint = Paint()
      ..color = const Color(0xFFE53935)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final item in items) {
      canvas.drawLine(item.foot, item.top, paint);
    }
  }

  void _drawAirports(Canvas canvas, _Proj Function(double, double, double) project) {
    const radiusNm = 0.55;
    const steps = 28;
    for (final airport in scene.airports) {
      if (!_classOn(airport.airspaceClass)) {
        continue;
      }
      final color = _classColor(airport.airspaceClass);
      final disk = ui.Path();
      for (var i = 0; i < steps; i++) {
        final angle = i * 2 * math.pi / steps;
        final p = project(
          airport.e + radiusNm * math.sin(angle),
          airport.n + radiusNm * math.cos(angle),
          _onSurface(airport.e, airport.n, 0),
        );
        if (i == 0) {
          disk.moveTo(p.x, p.y);
        } else {
          disk.lineTo(p.x, p.y);
        }
      }
      disk.close();
      canvas.drawPath(disk, Paint()..color = color);
      canvas.drawPath(
        disk,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
      final at = project(airport.e, airport.n, _onSurface(airport.e, airport.n, 0));
      _text(canvas, airport.ident, at.o + const Offset(12, -14), Colors.white, 13, FontWeight.w700, halo: color);
    }
  }

  void _drawHere(Canvas canvas, _Proj Function(double, double, double) project, double maxAlt) {
    final paint = Paint()
      ..color = hereColor
      ..strokeWidth = 1.5;
    final ground = project(0, 0, _onSurface(0, 0, 0));
    final top = project(0, 0, maxAlt);
    canvas.drawLine(ground.o, top.o, paint);
    canvas.drawCircle(ground.o, 4, Paint()..color = hereColor);
  }

  void _drawLabel(Canvas canvas, _Proj Function(double, double, double) project, AirspaceShelf shelf) {
    var ring = shelf.rings.first.points;
    for (final candidate in shelf.rings.skip(1)) {
      if (candidate.points.length > ring.length) {
        ring = candidate.points;
      }
    }
    var e = 0.0;
    var n = 0.0;
    for (final p in ring) {
      e += p.e;
      n += p.n;
    }
    e /= ring.length;
    n /= ring.length;
    var farE = ring.first.e;
    var farN = ring.first.n;
    var farD = -1.0;
    for (final p in ring) {
      final d = (p.e - e) * (p.e - e) + (p.n - n) * (p.n - n);
      if (d > farD) {
        farD = d;
        farE = p.e;
        farN = p.n;
      }
    }
    if (farD > 1) {
      e = e * 0.35 + farE * 0.65;
      n = n * 0.35 + farN * 0.65;
    }
    final floorFt = math.min(shelf.floorFt, scene.maxAltitudeFt);
    final ceilingFt = math.min(shelf.ceilingFt, scene.maxAltitudeFt);
    final bottom = math.min(ceilingFt, _onSurface(e, n, floorFt));
    final at = project(e, n, bottom >= ceilingFt ? ceilingFt : (bottom + ceilingFt) / 2);
    final color = _classColor(shelf.airspaceClass);
    _text(canvas, shelf.label, at.o, Color.lerp(color, Colors.white, 0.55)!, 13, FontWeight.w500, outline: Colors.white);
  }

  void _drawPlan(Canvas canvas, _Proj Function(double, double, double) project, double maxAlt) {
    final route = Storage().route;
    final double fallback = route.altitude.toDouble().clamp(0.0, maxAlt).toDouble();
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Constants.planBorderColor;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void stroke(List<LatLng> path, List<double> altitudes, Color color) {
      final List<_AltNm> located = [];
      for (int index = 0; index < path.length; index++) {
        final offset = ownshipOffsetNm(center, path[index], radiusNm: null);
        if (offset == null) {
          continue;
        }
        final double altitude = index < altitudes.length ? altitudes[index] : fallback;
        located.add(_AltNm(offset, altitude.clamp(0.0, maxAlt).toDouble()));
      }
      line.color = color;
      for (final List<_AltNm> piece in _clipAltPath(located)) {
        for (int index = 1; index < piece.length; index++) {
          final _AltNm from = piece[index - 1];
          final _AltNm to = piece[index];
          final _Proj start = project(from.point.e, from.point.n, from.altitudeFt);
          final _Proj end = project(to.point.e, to.point.n, to.altitudeFt);
          canvas.drawLine(start.o, end.o, border);
          canvas.drawLine(start.o, end.o, line);
        }
      }
    }

    stroke(route.getPathPassed(), route.getPathPassedAltitudes(), Constants.planPassedColor);
    stroke(route.getPathCurrent(), route.getPathCurrentAltitudes(), Constants.planCurrentColor);
    stroke(route.getPathNext(), route.getPathNextLineAltitudes(), Constants.planNextColor);
  }

  /// Translucent cone from the aircraft down to the glide ring.
  void _addGlideCone(List<_Face> faces, _Proj Function(double, double, double) project, double maxAlt) {
    final apex = _liveOwnship;
    final ring = _glideGround(maxAlt);
    if (apex == null || ring == null) {
      return;
    }
    final fill = Constants.glideCircleHaloColor.withAlpha(64);
    for (var i = 0; i < ring.length - 1; i++) {
      final start = ring[i];
      final end = ring[i + 1];
      final p1 = project(apex.offset.e, apex.offset.n, apex.altFt.clamp(0.0, maxAlt).toDouble());
      final p2 = project(start.e, start.n, start.h);
      final p3 = project(end.e, end.n, end.h);
      // A ring point behind the camera projects across the whole picture and hides the ground.
      if (p1.depth < -2.6 || p2.depth < -2.6 || p3.depth < -2.6) {
        continue;
      }
      final path = ui.Path()
        ..moveTo(p1.x, p1.y)
        ..lineTo(p2.x, p2.y)
        ..lineTo(p3.x, p3.y)
        ..close();
      final depth = (p1.depth + p2.depth + p3.depth) / 3;
      faces.add(_Face(depth, (canvas) {
        canvas.drawPath(path, Paint()..color = fill);
      }));
    }
  }

  /// Glide ring in view coordinates, closed, with a height on the visible ground.
  List<({double e, double n, double h})>? _glideGround(double maxAlt) {
    final List<LatLng> ring;
    try {
      ring = Storage().area.glideProfile.getGlideCircle();
    } catch (_) {
      return null;
    }
    if (!glideRingHasReach(ring)) {
      return null;
    }
    final mesh = showTerrainMesh ? terrain : null;
    final points = <({double e, double n, double h})>[];
    for (final point in ring) {
      final offset = ownshipOffsetNm(center, point, radiusNm: null);
      if (offset == null) {
        continue;
      }
      final ground = mesh == null
          ? 0.0
          : (sampleTerrainFt(mesh.elevFt, mesh.cols, mesh.rows, offset.e, offset.n, scene.radiusNm) ?? 0);
      points.add((e: offset.e, n: offset.n, h: ground.clamp(0.0, maxAlt).toDouble()));
    }
    return points.length >= 3 ? points : null;
  }

  void _drawGlide(Canvas canvas, _Proj Function(double, double, double) project, double maxAlt) {
    final ring = _glideGround(maxAlt);
    if (ring == null) {
      return;
    }
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Constants.glideCircleHaloColor;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Constants.glideCircleColor;
    final drawn = ui.Path();
    for (var i = 0; i < ring.length; i++) {
      final at = project(ring[i].e, ring[i].n, ring[i].h);
      if (i == 0) {
        drawn.moveTo(at.x, at.y);
      } else {
        drawn.lineTo(at.x, at.y);
      }
    }
    canvas.drawPath(drawn, halo);
    canvas.drawPath(drawn, line);
  }

  void _text(Canvas canvas, String text, Offset at, Color color, double size, FontWeight weight, {Color? halo, Color? outline}) {
    Offset place(TextPainter painter) => at - Offset(painter.width / 2, painter.height / 2);
    if (outline != null) {
      final stroke = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: size,
            fontWeight: weight,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.15
              ..strokeJoin = StrokeJoin.round
              ..color = outline,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      stroke.paint(canvas, place(stroke));
    }
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          shadows: [
            if (halo != null) Shadow(color: halo, blurRadius: 3),
            if (outline == null) const Shadow(color: Colors.black54, blurRadius: 2),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, place(painter));
  }

  @override
  bool shouldRepaint(covariant _AirspacePainter oldDelegate) {
    return oldDelegate.scene != scene ||
        oldDelegate.pitch != pitch ||
        oldDelegate.yaw != yaw ||
        oldDelegate.zoom != zoom ||
        oldDelegate.panX != panX ||
        oldDelegate.panY != panY ||
        oldDelegate.background != background ||
        oldDelegate.center != center ||
        oldDelegate.ownship != ownship ||
        oldDelegate.showPressPoint != showPressPoint ||
        oldDelegate.terrain != terrain ||
        oldDelegate.traffic != traffic ||
        oldDelegate.showClassB != showClassB ||
        oldDelegate.showClassC != showClassC ||
        oldDelegate.showClassD != showClassD ||
        oldDelegate.showTfr != showTfr ||
        oldDelegate.showGame != showGame ||
        oldDelegate.showPlan != showPlan ||
        oldDelegate.showObstacles != showObstacles ||
        oldDelegate.showSua != showSua ||
        oldDelegate.showTerrainMesh != showTerrainMesh;
  }
}

/// White ownship dot that pulses once per second, above the airspace scene.
class _OwnshipPulse extends StatefulWidget {
  final LatLng center;
  final ValueListenable<Position>? ownship;
  final double maxAltitudeFt;
  final double radiusNm;
  final double pitch;
  final double yaw;
  final double zoom;
  final double panX;
  final double panY;

  const _OwnshipPulse({
    required this.center,
    required this.ownship,
    required this.maxAltitudeFt,
    required this.radiusNm,
    required this.pitch,
    required this.yaw,
    required this.zoom,
    required this.panX,
    required this.panY,
  });

  @override
  State<_OwnshipPulse> createState() => _OwnshipPulseState();
}

class _OwnshipPulseState extends State<_OwnshipPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _cycle;

  @override
  void initState() {
    super.initState();
    _cycle = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
  }

  @override
  void dispose() {
    _cycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _OwnshipPulsePainter(
          cycle: _cycle,
          center: widget.center,
          ownship: widget.ownship,
          maxAltitudeFt: widget.maxAltitudeFt,
          radiusNm: widget.radiusNm,
          pitch: widget.pitch,
          yaw: widget.yaw,
          zoom: widget.zoom,
          panX: widget.panX,
          panY: widget.panY,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _OwnshipPulsePainter extends CustomPainter {
  final Animation<double> cycle;
  final LatLng center;
  final ValueListenable<Position>? ownship;
  final double maxAltitudeFt;
  final double radiusNm;
  final double pitch;
  final double yaw;
  final double zoom;
  final double panX;
  final double panY;

  _OwnshipPulsePainter({
    required this.cycle,
    required this.center,
    required this.ownship,
    required this.maxAltitudeFt,
    required this.radiusNm,
    required this.pitch,
    required this.yaw,
    required this.zoom,
    required this.panX,
    required this.panY,
  }) : super(repaint: Listenable.merge([cycle, ownship]));

  @override
  void paint(Canvas canvas, Size size) {
    final feed = ownship;
    if (feed == null) {
      return;
    }
    final pos = feed.value;
    if (Gps.isPositionCloseToZero(pos)) {
      return;
    }
    final offset = ownshipOffsetNm(center, LatLng(pos.latitude, pos.longitude));
    if (offset == null) {
      return;
    }
    final rawAlt = pos.altitude * _Airspace3DViewState._metersToFeet;
    final alt = (rawAlt.isFinite && rawAlt > 0 ? rawAlt : 0.0).clamp(0.0, maxAltitudeFt).toDouble();
    final at = _projectView(
      size,
      offset.e,
      offset.n,
      alt,
      radius: radiusNm,
      maxAlt: maxAltitudeFt,
      pitch: pitch,
      yaw: yaw,
      zoom: zoom,
      panX: panX,
      panY: panY,
    );
    final t = cycle.value;
    final wave = 0.5 - 0.5 * math.cos(t * 2 * math.pi);
    final radius = 7 + 2.5 * wave;
    final ring = 8 + 14 * t;
    canvas.drawCircle(
      at.o,
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: (1 - t) * 0.75),
    );
    canvas.drawCircle(at.o, radius, Paint()..color = Colors.white);
    canvas.drawCircle(
      at.o,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.black,
    );
  }

  @override
  bool shouldRepaint(covariant _OwnshipPulsePainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.maxAltitudeFt != maxAltitudeFt ||
        oldDelegate.radiusNm != radiusNm ||
        oldDelegate.pitch != pitch ||
        oldDelegate.yaw != yaw ||
        oldDelegate.zoom != zoom ||
        oldDelegate.panX != panX ||
        oldDelegate.panY != panY ||
        oldDelegate.ownship != ownship;
  }
}
