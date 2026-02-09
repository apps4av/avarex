import 'dart:math';

import 'package:avaremp/chart/download_screen.dart';
import 'package:avaremp/place/elevation_cache.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/chart_texture_sampler.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

const double _nmToFt = 6076.12;
const double _horizontalFovDeg = 74.0;

class Terrain3DScreen extends StatefulWidget {
  const Terrain3DScreen({super.key});

  @override
  State<Terrain3DScreen> createState() => Terrain3DScreenState();
}

class Terrain3DScreenState extends State<Terrain3DScreen> {
  static const int _forwardSteps = 18;
  static const int _lateralSteps = 7;
  static const double _nearNm = 0.25;

  final List<String> _charts = DownloadScreenState.getCategories();

  double _farNm = 24;
  double _verticalExaggeration = 1.2;
  bool _trackUp = true;
  bool _isBuilding = false;
  bool _queuedRebuild = false;
  late String _chartType;

  _TerrainFrame? _frame;

  @override
  void initState() {
    super.initState();
    _chartType = Storage().settings.getChartType();
    if (!_charts.contains(_chartType) && _charts.isNotEmpty) {
      _chartType = _charts.first;
    }
    Storage().timeChange.addListener(_onTimeChange);
    _scheduleRebuild();
  }

  @override
  void dispose() {
    Storage().timeChange.removeListener(_onTimeChange);
    ChartTextureSampler.clear();
    super.dispose();
  }

  void _onTimeChange() {
    if ((Storage().timeChange.value % 2) != 0) {
      return;
    }
    _scheduleRebuild();
  }

  void _scheduleRebuild() {
    _queuedRebuild = true;
    _runBuildLoop();
  }

  Future<void> _runBuildLoop() async {
    if (_isBuilding) {
      return;
    }

    if (mounted) {
      setState(() {
        _isBuilding = true;
      });
    }

    _isBuilding = true;
    while (_queuedRebuild && mounted) {
      _queuedRebuild = false;
      try {
        final _TerrainFrame frame = await _buildFrame();
        if (!mounted) {
          break;
        }
        setState(() {
          _frame = frame;
        });
      } catch (_) {
        // Ignore occasional tile read/decode failures and continue with previous frame.
      }
    }

    if (mounted) {
      setState(() {
        _isBuilding = false;
      });
    }
    _isBuilding = false;
  }

  Future<_TerrainFrame> _buildFrame() async {
    final Position aircraft = Storage().position;
    final double headingDeg = _trackUp ? aircraft.heading : 0.0;
    final double aircraftAltitudeFt = GeoCalculations.convertAltitude(
      aircraft.altitude,
    );

    final int rowCount = _forwardSteps + 1;
    final int colCount = _lateralSteps * 2 + 1;

    final List<Future<_TerrainSample>> tasks = [];
    for (int row = 0; row < rowCount; row++) {
      for (int col = 0; col < colCount; col++) {
        tasks.add(_samplePoint(aircraft, headingDeg, row, col));
      }
    }

    final List<_TerrainSample> samples = await Future.wait(tasks);
    final List<List<_TerrainPoint>> grid = List<List<_TerrainPoint>>.generate(
      rowCount,
      (_) => List<_TerrainPoint>.generate(
        colCount,
        (_) => const _TerrainPoint.empty(),
      ),
    );

    double minClearanceFt = double.infinity;
    for (final _TerrainSample sample in samples) {
      grid[sample.row][sample.col] = sample.point;
      final double clearanceFt = aircraftAltitudeFt - sample.point.elevationFt;
      if (clearanceFt < minClearanceFt) {
        minClearanceFt = clearanceFt;
      }
    }

    if (minClearanceFt == double.infinity) {
      minClearanceFt = 0;
    }

    return _TerrainFrame(
      grid: grid,
      aircraftAltitudeFt: aircraftAltitudeFt,
      pitchDeg: Storage().pfdData.pitch,
      rollDeg: Storage().pfdData.roll,
      headingDeg: headingDeg,
      minimumClearanceFt: minClearanceFt,
      chartType: _chartType,
    );
  }

  Future<_TerrainSample> _samplePoint(
    Position aircraft,
    double headingDeg,
    int row,
    int col,
  ) async {
    final double rowProgress = row / _forwardSteps;
    final double forwardNm = _nearNm +
        pow(rowProgress, 1.35).toDouble() * (_farNm - _nearNm);
    final double halfWidthNm = max(
      0.45,
      min(11.0, forwardNm * tan(GeoCalculations.toRadians(_horizontalFovDeg / 2))),
    );
    final double rightFraction = (col - _lateralSteps) / _lateralSteps;
    final double rightNm = rightFraction * halfWidthNm;

    final LatLng sampleLocation = _offsetLatLng(
      aircraft.latitude,
      aircraft.longitude,
      headingDeg,
      forwardNm,
      rightNm,
    );

    final List<dynamic> sampledData = await Future.wait<dynamic>([
      ElevationCache.getElevation(sampleLocation),
      ChartTextureSampler.getColor(sampleLocation, _chartType),
    ]);
    final double elevationFt = (sampledData[0] as double?) ?? 0.0;
    final Color textureColor =
        (sampledData[1] as Color?) ?? _fallbackTerrainColor(elevationFt);

    return _TerrainSample(
      row: row,
      col: col,
      point: _TerrainPoint(
        forwardNm: forwardNm,
        rightNm: rightNm,
        elevationFt: elevationFt,
        color: textureColor,
      ),
    );
  }

  LatLng _offsetLatLng(
    double latitude,
    double longitude,
    double headingDeg,
    double forwardNm,
    double rightNm,
  ) {
    final double headingRad = GeoCalculations.toRadians(headingDeg);
    final double eastNm =
        forwardNm * sin(headingRad) + rightNm * cos(headingRad);
    final double northNm =
        forwardNm * cos(headingRad) - rightNm * sin(headingRad);
    final double latitudeOut = latitude + northNm / 60.0;
    final double lonScale = cos(GeoCalculations.toRadians(latitude)).abs();
    final double longitudeOut = longitude +
        (lonScale < 0.0001 ? 0.0 : eastNm / (60.0 * lonScale));
    return LatLng(latitudeOut, longitudeOut);
  }

  Color _fallbackTerrainColor(double elevationFt) {
    if (elevationFt > 9000) {
      return const Color(0xFF7D7467);
    }
    if (elevationFt > 4500) {
      return const Color(0xFF6B614E);
    }
    if (elevationFt > 1200) {
      return const Color(0xFF4E6A3B);
    }
    return const Color(0xFF3B5E35);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("3D Terrain"),
      ),
      body: Column(
        children: [
          Expanded(
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _frame == null
                          ? null
                          : _TerrainPainter(
                              frame: _frame!,
                              verticalExaggeration: _verticalExaggeration,
                            ),
                    ),
                  ),
                  if (_frame != null)
                    Positioned(
                      left: 10,
                      top: 10,
                      child: _buildHud(),
                    ),
                  if (_isBuilding)
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius:
                              const BorderRadius.all(Radius.circular(8)),
                        ),
                        child: const Text("Rendering..."),
                      ),
                    ),
                  if (_frame == null && !_isBuilding)
                    const Center(
                      child: Text("No terrain data"),
                    ),
                ],
              ),
            ),
          ),
          _buildControls(context),
        ],
      ),
    );
  }

  Widget _buildHud() {
    final Position aircraft = Storage().position;
    final double clearance = _frame!.minimumClearanceFt;
    Color clearanceColor = Colors.greenAccent;
    if (clearance < 1000) {
      clearanceColor = Colors.orangeAccent;
    }
    if (clearance < 200) {
      clearanceColor = Colors.redAccent;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 12, color: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("ALT ${GeoCalculations.convertAltitude(aircraft.altitude).round()} ft"),
            Text(
              "HDG ${(((_frame!.headingDeg) + 360) % 360).round()}\u00b0  "
              "PIT ${Storage().pfdData.pitch.toStringAsFixed(1)}\u00b0  "
              "ROL ${Storage().pfdData.roll.toStringAsFixed(1)}\u00b0",
            ),
            Text(
              "CLR ${clearance.round()} ft",
              style: TextStyle(color: clearanceColor),
            ),
            Text("CHART ${_frame!.chartType}"),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    return Container(
      color: Theme.of(context).cardColor.withValues(alpha: 0.95),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "Range ${_farNm.toStringAsFixed(0)} NM",
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: _trackUp
                    ? "Track-up with aircraft heading"
                    : "North-up view",
                onPressed: () {
                  setState(() {
                    _trackUp = !_trackUp;
                  });
                  _scheduleRebuild();
                },
                icon: Icon(_trackUp ? Icons.navigation : Icons.explore),
              ),
              PopupMenuButton<String>(
                tooltip: "Chart texture source",
                icon: const Icon(Icons.photo_library_rounded),
                initialValue: _charts.contains(_chartType) ? _chartType : null,
                onSelected: (String type) {
                  setState(() {
                    _chartType = type;
                  });
                  _scheduleRebuild();
                },
                itemBuilder: (BuildContext context) {
                  return List<PopupMenuEntry<String>>.generate(_charts.length,
                      (int index) {
                    return PopupMenuItem<String>(
                      value: _charts[index],
                      child: Text(_charts[index]),
                    );
                  });
                },
              ),
            ],
          ),
          Slider(
            min: 8,
            max: 35,
            divisions: 27,
            value: _farNm,
            onChanged: (double value) {
              setState(() {
                _farNm = value;
              });
            },
            onChangeEnd: (_) {
              _scheduleRebuild();
            },
          ),
          Row(
            children: [
              const Text("Vertical"),
              Expanded(
                child: Slider(
                  min: 0.7,
                  max: 2.2,
                  divisions: 15,
                  value: _verticalExaggeration,
                  onChanged: (double value) {
                    setState(() {
                      _verticalExaggeration = value;
                    });
                  },
                ),
              ),
              Text("${_verticalExaggeration.toStringAsFixed(1)}x"),
            ],
          ),
        ],
      ),
    );
  }
}

class _TerrainPainter extends CustomPainter {
  final _TerrainFrame frame;
  final double verticalExaggeration;

  _TerrainPainter({
    required this.frame,
    required this.verticalExaggeration,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (frame.grid.length < 2 || frame.grid[0].length < 2) {
      return;
    }

    final Rect bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF355A86), Color(0xFF0C1724)],
        ).createShader(bounds),
    );

    final int rows = frame.grid.length;
    final int cols = frame.grid[0].length;
    final double cx = size.width * 0.5;
    final double horizonY = size.height * 0.39;
    final double focalX =
        (size.width * 0.5) / tan(GeoCalculations.toRadians(_horizontalFovDeg / 2));
    final double focalY = size.height * 0.92;

    final double pitchRad = GeoCalculations.toRadians(frame.pitchDeg);
    final double rollRad = GeoCalculations.toRadians(frame.rollDeg);
    final List<List<Offset?>> projected = List<List<Offset?>>.generate(
      rows,
      (_) => List<Offset?>.filled(cols, null),
    );

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        projected[row][col] = _project(
          frame.grid[row][col],
          cx,
          horizonY,
          focalX,
          focalY,
          pitchRad,
          rollRad,
        );
      }
    }

    final Paint paint = Paint()..style = PaintingStyle.fill;
    final Paint edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = Colors.black.withValues(alpha: 0.18);

    for (int row = rows - 2; row >= 0; row--) {
      final double distanceFade = row / (rows - 1);
      for (int col = 0; col < cols - 1; col++) {
        final Offset? p00 = projected[row][col];
        final Offset? p01 = projected[row][col + 1];
        final Offset? p10 = projected[row + 1][col];
        final Offset? p11 = projected[row + 1][col + 1];
        if (p00 == null || p01 == null || p10 == null || p11 == null) {
          continue;
        }

        final _TerrainPoint t00 = frame.grid[row][col];
        final _TerrainPoint t01 = frame.grid[row][col + 1];
        final _TerrainPoint t10 = frame.grid[row + 1][col];
        final _TerrainPoint t11 = frame.grid[row + 1][col + 1];

        final double avgElevationFt =
            (t00.elevationFt + t01.elevationFt + t10.elevationFt + t11.elevationFt) /
                4;

        Color color = _averageColor([t00.color, t01.color, t10.color, t11.color]);
        color = _modulateColor(color, 0.92 - distanceFade * 0.35);
        final double clearanceFt = frame.aircraftAltitudeFt - avgElevationFt;
        if (clearanceFt < 200) {
          color = Color.lerp(color, const Color(0xFFFF3B30), 0.70)!;
        } else if (clearanceFt < 1000) {
          color = Color.lerp(color, const Color(0xFFFFB347), 0.52)!;
        }

        final Path path = Path()
          ..moveTo(p00.dx, p00.dy)
          ..lineTo(p01.dx, p01.dy)
          ..lineTo(p11.dx, p11.dy)
          ..lineTo(p10.dx, p10.dy)
          ..close();
        paint.color = color;
        canvas.drawPath(path, paint);
        canvas.drawPath(path, edgePaint);
      }
    }

    _drawReticle(canvas, size, horizonY);
  }

  Offset? _project(
    _TerrainPoint point,
    double centerX,
    double horizonY,
    double focalX,
    double focalY,
    double pitchRad,
    double rollRad,
  ) {
    final double forwardFt = point.forwardNm * _nmToFt;
    if (forwardFt < 10) {
      return null;
    }

    final double screenX = (point.rightNm / point.forwardNm) * focalX;
    final double pitchOffsetFt = forwardFt * tan(pitchRad);
    final double verticalRatio = ((point.elevationFt - frame.aircraftAltitudeFt) *
            verticalExaggeration -
        pitchOffsetFt) /
        forwardFt;
    final double screenY = -verticalRatio * focalY;

    // Rotate world around pilot eye so bank changes the rendered horizon.
    final double cosRoll = cos(-rollRad);
    final double sinRoll = sin(-rollRad);
    final double rotatedX = screenX * cosRoll - screenY * sinRoll;
    final double rotatedY = screenX * sinRoll + screenY * cosRoll;

    return Offset(centerX + rotatedX, horizonY + rotatedY);
  }

  void _drawReticle(Canvas canvas, Size size, double horizonY) {
    final Paint reticlePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.80)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final double cx = size.width * 0.5;
    final double cy = size.height * 0.84;
    canvas.drawLine(Offset(cx - 18, cy), Offset(cx + 18, cy), reticlePaint);
    canvas.drawLine(Offset(cx, cy - 10), Offset(cx, cy + 10), reticlePaint);
    canvas.drawCircle(Offset(cx, cy), 14, reticlePaint);

    final Paint horizonPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.20)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(0, horizonY),
      Offset(size.width, horizonY),
      horizonPaint,
    );
  }

  Color _averageColor(List<Color> colors) {
    int red = 0;
    int green = 0;
    int blue = 0;
    for (final Color color in colors) {
      red += color.red;
      green += color.green;
      blue += color.blue;
    }
    final int count = colors.length;
    return Color.fromARGB(
      255,
      (red / count).round(),
      (green / count).round(),
      (blue / count).round(),
    );
  }

  Color _modulateColor(Color color, double scale) {
    final double clampedScale = scale.clamp(0.0, 1.0).toDouble();
    return Color.fromARGB(
      color.alpha,
      (color.red * clampedScale).round(),
      (color.green * clampedScale).round(),
      (color.blue * clampedScale).round(),
    );
  }

  @override
  bool shouldRepaint(covariant _TerrainPainter oldDelegate) {
    return oldDelegate.frame != frame ||
        oldDelegate.verticalExaggeration != verticalExaggeration;
  }
}

class _TerrainFrame {
  final List<List<_TerrainPoint>> grid;
  final double aircraftAltitudeFt;
  final double pitchDeg;
  final double rollDeg;
  final double headingDeg;
  final double minimumClearanceFt;
  final String chartType;

  const _TerrainFrame({
    required this.grid,
    required this.aircraftAltitudeFt,
    required this.pitchDeg,
    required this.rollDeg,
    required this.headingDeg,
    required this.minimumClearanceFt,
    required this.chartType,
  });
}

class _TerrainPoint {
  final double forwardNm;
  final double rightNm;
  final double elevationFt;
  final Color color;

  const _TerrainPoint({
    required this.forwardNm,
    required this.rightNm,
    required this.elevationFt,
    required this.color,
  });

  const _TerrainPoint.empty()
      : forwardNm = 0,
        rightNm = 0,
        elevationFt = 0,
        color = const Color(0xFF000000);
}

class _TerrainSample {
  final int row;
  final int col;
  final _TerrainPoint point;

  const _TerrainSample({
    required this.row,
    required this.col,
    required this.point,
  });
}
