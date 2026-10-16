import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:avaremp/io/gps.dart';
import 'package:avaremp/place/airspace_volume.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/path_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:universal_io/io.dart';

/// 3D Class B/C/D shelves around a long-press point.
///
/// Drag rotates, a pinch zooms, and two fingers pan.
class Airspace3DView extends StatefulWidget {
  final LatLng center;

  /// Live ownship. Drawn only when it is inside the 25 NM view.
  final ValueListenable<Position>? ownship;

  const Airspace3DView({super.key, required this.center, this.ownship});

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
  static String? _cacheKey;
  static AirspaceScene? _cache;

  AirspaceScene? _scene;
  bool _loading = true;
  double _pitch = _pitch0;
  double _yaw = _yaw0;
  double _zoom = 1;
  double _panX = 0;
  double _panY = 0;
  double _lastScale = 1;
  Offset? _lastFocal;
  int _pointers = 0;

  @override
  void initState() {
    super.initState();
    final cached = _cached(_placeKey);
    if (cached != null) {
      _scene = cached;
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void didUpdateWidget(Airspace3DView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.center.latitude == widget.center.latitude &&
        oldWidget.center.longitude == widget.center.longitude) {
      return;
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

  int _generation = 0;

  String get _placeKey =>
      '${widget.center.latitude.toStringAsFixed(4)},${widget.center.longitude.toStringAsFixed(4)}';

  static AirspaceScene? _cached(String key) {
    if (_cache != null && _cacheKey == key) {
      return _cache;
    }
    return null;
  }

  Future<void> _load() async {
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
      scene = await Future(() => loadClassAirspace(path, widget.center));
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
    final scene = _scene;
    if (_loading || scene == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (scene.message != null) {
      return _message(context, scene.message!);
    }
    if (scene.shelves.isEmpty) {
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
    return CustomPaint(
      painter: _AirspacePainter(
        scene: scene,
        center: widget.center,
        ownship: widget.ownship,
        pitch: _pitch,
        yaw: _yaw,
        zoom: _zoom,
        panX: _panX,
        panY: _panY,
        background: dark ? const Color(0xFF12171C) : const Color(0xFFEEF3F8),
        gridColor: scheme.outline.withAlpha(110),
        axisColor: scheme.onSurface.withAlpha(200),
        hereColor: const Color(0xFFFF9800),
      ),
      child: const SizedBox.expand(),
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
  final double pitch;
  final double yaw;
  final double zoom;
  final double panX;
  final double panY;
  final Color background;
  final Color gridColor;
  final Color axisColor;
  final Color hereColor;

  _AirspacePainter({
    required this.scene,
    required this.center,
    required this.ownship,
    required this.pitch,
    required this.yaw,
    required this.zoom,
    required this.panX,
    required this.panY,
    required this.background,
    required this.gridColor,
    required this.axisColor,
    required this.hereColor,
  }) : super(repaint: ownship);

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
    final maxAlt = scene.maxAltitudeFt;
    // Stretch altitude so a shelf is tall enough to read next to a 25 NM square.
    final double altScale = radius * 0.72 / maxAlt;

    final cosY = math.cos(yaw);
    final sinY = math.sin(yaw);
    final cosP = math.cos(pitch);
    final sinP = math.sin(pitch);
    final s = math.min(size.width, size.height) * 0.36 * zoom;
    const camera = 3.2;

    _Proj project(double east, double north, double altFt) {
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

    _drawGround(canvas, project, radius);
    _drawAxis(canvas, project, radius, maxAlt);

    final faces = <_Face>[];
    for (final shelf in scene.shelves) {
      _addShelf(faces, project, shelf);
    }
    faces.sort((a, b) => b.depth.compareTo(a.depth));
    for (final face in faces) {
      face.draw(canvas);
    }

    _drawHere(canvas, project, maxAlt);
    _drawAirports(canvas, project);
    for (final shelf in scene.shelves) {
      if (shelf.showLabel && shelf.rings.isNotEmpty) {
        _drawLabel(canvas, project, shelf);
      }
    }
    _drawOwnship(canvas, project, maxAlt);
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
    canvas.drawPath(ground, Paint()..color = gridColor.withAlpha(28));

    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = gridColor;
    for (var g = -radius; g <= radius + 0.01; g += 5) {
      final a = project(-radius, g, 0);
      final b = project(radius, g, 0);
      final c = project(g, -radius, 0);
      final d = project(g, radius, 0);
      canvas.drawLine(a.o, b.o, grid);
      canvas.drawLine(c.o, d.o, grid);
    }

    final north = project(0, radius, 0);
    _text(canvas, 'N', north.o, axisColor, 12, FontWeight.w700);
    final scaleA = project(-radius, radius, 0);
    final scaleB = project(-radius + 5, radius, 0);
    canvas.drawLine(scaleA.o, scaleB.o, Paint()..color = axisColor..strokeWidth = 2);
    _text(canvas, '5 NM', Offset((scaleA.x + scaleB.x) / 2, (scaleA.y + scaleB.y) / 2 - 12), axisColor, 10, FontWeight.w500);
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
          ? '00'
          : (thousands == thousands.roundToDouble() ? '${thousands.round()}k' : '${thousands.toStringAsFixed(1)}k');
      _text(canvas, label, p.o + const Offset(-28, -6), axisColor, 10, FontWeight.w500);
    }
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
    cap(floorFt, 90);

    final wall = Paint()..style = PaintingStyle.fill;
    for (final ring in rings) {
      for (var i = 0; i < ring.points.length; i++) {
        if (ring.hides(i)) {
          continue;
        }
        final a = ring.points[i];
        final b = ring.points[(i + 1) % ring.points.length];
        final p1 = project(a.e, a.n, floorFt);
        final p2 = project(b.e, b.n, floorFt);
        final p3 = project(b.e, b.n, ceilingFt);
        final p4 = project(a.e, a.n, ceilingFt);
        final path = ui.Path()
          ..moveTo(p1.x, p1.y)
          ..lineTo(p2.x, p2.y)
          ..lineTo(p3.x, p3.y)
          ..lineTo(p4.x, p4.y)
          ..close();
        final depth = (p1.depth + p2.depth + p3.depth + p4.depth) / 4;
        final de = b.e - a.e;
        final dn = b.n - a.n;
        final len = math.sqrt(de * de + dn * dn);
        var shade = 0.72;
        if (len > 1e-6) {
          final nx = dn / len;
          final nz = -de / len;
          shade = (0.55 + 0.45 * (nx * 0.65 + nz * 0.75).abs()).clamp(0.45, 1.0);
        }
        final side = Color.lerp(Colors.black, color, shade)!.withAlpha(120);
        faces.add(_Face(depth, (c) {
          wall.color = side;
          c.drawPath(path, wall);
        }));
      }
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

  void _drawAirports(Canvas canvas, _Proj Function(double, double, double) project) {
    const radiusNm = 0.55;
    const steps = 28;
    for (final airport in scene.airports) {
      final color = _classColor(airport.airspaceClass);
      final disk = ui.Path();
      for (var i = 0; i < steps; i++) {
        final angle = i * 2 * math.pi / steps;
        final p = project(
          airport.e + radiusNm * math.sin(angle),
          airport.n + radiusNm * math.cos(angle),
          0,
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
      final at = project(airport.e, airport.n, 0);
      _text(canvas, airport.ident, at.o + const Offset(12, -14), Colors.white, 13, FontWeight.w700, halo: color);
    }
  }

  void _drawHere(Canvas canvas, _Proj Function(double, double, double) project, double maxAlt) {
    final paint = Paint()
      ..color = hereColor
      ..strokeWidth = 1.5;
    final ground = project(0, 0, 0);
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
    final at = project(e, n, (floorFt + ceilingFt) / 2);
    final color = _classColor(shelf.airspaceClass);
    _text(canvas, shelf.label, at.o, Color.lerp(color, Colors.white, 0.55)!, 13, FontWeight.w500, outline: Colors.white);
  }

  void _drawOwnship(Canvas canvas, _Proj Function(double, double, double) project, double maxAlt) {
    final ship = _liveOwnship;
    if (ship == null) {
      return;
    }
    final alt = ship.altFt.clamp(0.0, maxAlt);
    final at = project(ship.offset.e, ship.offset.n, alt);
    canvas.drawCircle(at.o, 5, Paint()..color = const Color(0xFFE53935));
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
        oldDelegate.ownship != ownship;
  }
}
