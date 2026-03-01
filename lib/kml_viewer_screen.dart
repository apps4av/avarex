import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:avaremp/constants.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/logbook/log_entry.dart';
import 'package:avaremp/place/elevation_cache.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/kml_parser.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

class KmlViewerScreen extends StatefulWidget {
  final String kmlPath;

  const KmlViewerScreen({super.key, required this.kmlPath});

  @override
  State<KmlViewerScreen> createState() => _KmlViewerScreenState();
}

class _KmlViewerScreenState extends State<KmlViewerScreen> {
  KmlTrack? _track;
  bool _loading = true;
  bool _loadingTerrain = false;
  String? _error;
  int _currentView = 0;
  
  double _rotationX = 0.5;
  double _rotationY = 0.3;
  double _zoom3D = 1.0;
  double _lastScale = 1.0;
  
  List<TerrainPoint>? _terrainGrid;
  double _terrainMinElev = 0;
  double _terrainMaxElev = 0;
  ui.Image? _topoImage;
  bool _loadingTopoImage = false;

  @override
  void initState() {
    super.initState();
    _loadKml();
  }

  Future<void> _loadKml() async {
    try {
      final track = await KmlParser.parseFile(widget.kmlPath);
      if (mounted) {
        setState(() {
          _track = track;
          _loading = false;
          if (track == null) {
            _error = 'Could not parse KML file or no track data found';
          }
        });
        if (track != null) {
          _loadTerrain(track);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Error: $e';
        });
      }
    }
  }

  Future<void> _loadTerrain(KmlTrack track) async {
    if (_loadingTerrain) return;
    _loadingTerrain = true;
    
    const int gridSize = 15;
    final List<TerrainPoint> grid = [];
    
    final latStep = (track.maxLat - track.minLat) / (gridSize - 1);
    final lonStep = (track.maxLon - track.minLon) / (gridSize - 1);
    
    double minElev = double.infinity;
    double maxElev = double.negativeInfinity;
    
    for (int i = 0; i < gridSize; i++) {
      for (int j = 0; j < gridSize; j++) {
        final lat = track.minLat + i * latStep;
        final lon = track.minLon + j * lonStep;
        final elevation = await ElevationCache.getElevation(LatLng(lat, lon));
        
        if (elevation != null) {
          grid.add(TerrainPoint(lat: lat, lon: lon, elevation: elevation));
          if (elevation < minElev) minElev = elevation;
          if (elevation > maxElev) maxElev = elevation;
        } else {
          grid.add(TerrainPoint(lat: lat, lon: lon, elevation: 0));
        }
      }
    }
    
    if (minElev == double.infinity) minElev = 0;
    if (maxElev == double.negativeInfinity) maxElev = 1000;
    
    if (mounted) {
      setState(() {
        _terrainGrid = grid;
        _terrainMinElev = minElev;
        _terrainMaxElev = maxElev;
        _loadingTerrain = false;
      });
      _loadTopoImage(track);
    }
  }

  Future<void> _loadTopoImage(KmlTrack track) async {
    if (_loadingTopoImage) return;
    _loadingTopoImage = true;
    
    try {
      final padding = 0.1;
      final latRange = track.maxLat - track.minLat;
      final lonRange = track.maxLon - track.minLon;
      final minLat = track.minLat - latRange * padding;
      final maxLat = track.maxLat + latRange * padding;
      final minLon = track.minLon - lonRange * padding;
      final maxLon = track.maxLon + lonRange * padding;
      
      const int imageSize = 512;
      final bbox = '$minLon,$minLat,$maxLon,$maxLat';
      final url = 'https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer/export?'
          'bbox=$bbox&bboxSR=4326&imageSR=4326&size=$imageSize,$imageSize&format=png&f=image';
      
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final Uint8List bytes = response.bodyBytes;
        final ui.Codec codec = await ui.instantiateImageCodec(bytes);
        final ui.FrameInfo frame = await codec.getNextFrame();
        codec.dispose();
        
        if (mounted) {
          setState(() {
            _topoImage = frame.image;
            _loadingTopoImage = false;
          });
        }
      } else {
        _loadingTopoImage = false;
      }
    } catch (e) {
      _loadingTopoImage = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: Text(_track?.name ?? 'Track Viewer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.map),
            onPressed: () => setState(() => _currentView = 0),
            tooltip: '2D Map',
            color: _currentView == 0 ? Colors.blue : null,
          ),
          IconButton(
            icon: const Icon(Icons.show_chart),
            onPressed: () => setState(() => _currentView = 1),
            tooltip: 'Altitude Profile',
            color: _currentView == 1 ? Colors.blue : null,
          ),
          IconButton(
            icon: const Icon(Icons.view_in_ar),
            onPressed: () => setState(() => _currentView = 2),
            tooltip: '3D View',
            color: _currentView == 2 ? Colors.blue : null,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _track == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text('Failed to load track', style: TextStyle(fontSize: 18)),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                        ],
                        const SizedBox(height: 8),
                        Text('Path: ${widget.kmlPath}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                  ),
                )
              : _buildCurrentView(),
    );
  }

  Widget _buildCurrentView() {
    switch (_currentView) {
      case 0:
        return _build2DMapView();
      case 1:
        return _buildAltitudeProfile();
      case 2:
        return _build3DView();
      default:
        return _build2DMapView();
    }
  }

  Future<void> _createLogbookEntry() async {
    final track = _track;
    if (track == null || track.points.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No track data available')),
        );
      }
      return;
    }

    final points = track.points;
    final startCoord = points.first.coordinate;
    final endCoord = points.last.coordinate;

    final aircraftName = Storage().settings.getAircraft();
    if (aircraftName.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No aircraft selected. Please select an aircraft first.')),
        );
      }
      return;
    }

    final aircraft = await UserDatabaseHelper.db.getAircraft(aircraftName);

    final startAirports = await MainDatabaseHelper.db.findNearestAirportsWithRunways(startCoord, 0);
    final endAirports = await MainDatabaseHelper.db.findNearestAirportsWithRunways(endCoord, 0);

    final startAirport = startAirports.isNotEmpty ? startAirports.first.locationID : 'Unknown';
    final endAirport = endAirports.isNotEmpty ? endAirports.first.locationID : 'Unknown';

    final route = startAirport == endAirport ? startAirport : '$startAirport-$endAirport';

    double totalFlightTime = 0.0;
    
    // Try to calculate from track-level timestamps first, then point timestamps
    if (track.startTime != null && track.endTime != null) {
      final duration = track.endTime!.difference(track.startTime!);
      totalFlightTime = duration.inMinutes / 60.0;
    } else if (points.length >= 2 && points.first.time != null && points.last.time != null) {
      final duration = points.last.time!.difference(points.first.time!);
      totalFlightTime = duration.inMinutes / 60.0;
    }
    
    // If no timestamps available, calculate from track distance
    if (totalFlightTime <= 0 && points.length >= 2) {
      const Distance distanceCalc = Distance();
      double totalDistanceNm = 0;
      for (int i = 1; i < points.length; i++) {
        final distanceMeters = distanceCalc.as(
          LengthUnit.Meter,
          points[i - 1].coordinate,
          points[i].coordinate,
        );
        totalDistanceNm += distanceMeters / 1852.0;
      }
      // Use aircraft's cruise TAS, fallback to 100 knots if not set
      double groundSpeedKts = double.tryParse(aircraft.cruiseTas) ?? 100.0;
      if (groundSpeedKts <= 0) {
        groundSpeedKts = 100.0;
      }
      totalFlightTime = totalDistanceNm / groundSpeedKts;
    }

    DateTime flightDate = track.startTime ?? points.first.time ?? DateTime.now();

    final entry = LogEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: flightDate,
      aircraftMakeModel: aircraft.type,
      aircraftIdentification: aircraft.tail,
      route: route,
      totalFlightTime: totalFlightTime,
      pilotInCommand: totalFlightTime,
      dayLandings: 1,
      remarks: 'Created from track: ${track.name}',
    );

    await UserDatabaseHelper.db.insertLogbook(entry);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logbook entry created: $route (${totalFlightTime.toStringAsFixed(1)} hrs)'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _build2DMapView() {
    final track = _track!;
    final points = track.points.map((p) => p.coordinate).toList();

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: track.center,
            initialZoom: 10,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer/WMTS/tile/1.0.0/USGSTopo/default/default028mm/{z}/{y}/{x}.png',
              maxNativeZoom: 16,
              userAgentPackageName: 'com.apps4av.avarex',
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: points,
                  strokeWidth: 3,
                  color: Colors.blue,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                if (points.isNotEmpty)
                  Marker(
                    point: points.first,
                    child: const Icon(Icons.flight_takeoff, color: Colors.green, size: 30),
                  ),
                if (points.length > 1)
                  Marker(
                    point: points.last,
                    child: const Icon(Icons.flight_land, color: Colors.red, size: 30),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          bottom: 16,
          right: 16,
          child: FloatingActionButton.extended(
            onPressed: _createLogbookEntry,
            icon: const Icon(Icons.book),
            label: const Text('Log Flight'),
            tooltip: 'Create logbook entry from this track',
          ),
        ),
      ],
    );
  }

  Widget _buildAltitudeProfile() {
    final track = _track!;
    if (track.points.isEmpty) {
      return const Center(child: Text('No altitude data'));
    }

    final spots = <FlSpot>[];
    double totalDistance = 0;
    const Distance distanceCalc = Distance();

    for (int i = 0; i < track.points.length; i++) {
      if (i > 0) {
        final distanceMeters = distanceCalc.as(
          LengthUnit.Meter,
          track.points[i - 1].coordinate,
          track.points[i].coordinate,
        );
        totalDistance += distanceMeters / 1852.0;
      }
      final altFeet = track.points[i].altitude * 3.28084;
      spots.add(FlSpot(totalDistance, altFeet));
    }

    final minAltFeet = track.minAltitude * 3.28084;
    final maxAltFeet = track.maxAltitude * 3.28084;
    final altRange = maxAltFeet - minAltFeet;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Altitude Profile',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Distance: ${totalDistance.toStringAsFixed(1)} NM  |  '
            'Alt: ${minAltFeet.toStringAsFixed(0)} - ${maxAltFeet.toStringAsFixed(0)} ft',
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: (minAltFeet - altRange * 0.1).clamp(0, double.infinity),
                maxY: maxAltFeet + altRange * 0.1,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.2,
                    color: Colors.blue,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.blue.withAlpha(50),
                    ),
                  ),
                ],
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    axisNameWidget: const Text('Altitude (ft)'),
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      getTitlesWidget: (value, meta) {
                        return Text(value.toInt().toString(), style: const TextStyle(fontSize: 10));
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    axisNameWidget: const Text('Distance (NM)'),
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Text(value.toStringAsFixed(1), style: const TextStyle(fontSize: 10));
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawHorizontalLine: true,
                  drawVerticalLine: true,
                  horizontalInterval: altRange > 0 ? altRange / 5 : 1000,
                ),
                borderData: FlBorderData(show: true),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _build3DView() {
    final track = _track!;
    if (track.points.isEmpty) {
      return const Center(child: Text('No track data'));
    }

    return GestureDetector(
      onScaleStart: (details) {
        _lastScale = 1.0;
      },
      onScaleUpdate: (details) {
        setState(() {
          if (details.pointerCount == 1) {
            _rotationY += details.focalPointDelta.dx * 0.01;
            _rotationX += details.focalPointDelta.dy * 0.01;
            _rotationX = _rotationX.clamp(-1.5, 1.5);
          } else if (details.scale != _lastScale) {
            _zoom3D = (_zoom3D * (details.scale / _lastScale)).clamp(0.5, 3.0);
            _lastScale = details.scale;
          }
        });
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Drag to rotate • Pinch to zoom',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                CustomPaint(
                  painter: Track3DPainter(
                    track: track,
                    rotationX: _rotationX,
                    rotationY: _rotationY,
                    zoom: _zoom3D,
                    terrainGrid: _terrainGrid,
                    terrainMinElev: _terrainMinElev,
                    terrainMaxElev: _terrainMaxElev,
                    topoImage: _topoImage,
                  ),
                  size: Size.infinite,
                ),
                if (_loadingTerrain || _loadingTopoImage)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _loadingTerrain ? 'Loading terrain...' : 'Loading topo map...',
                          style: const TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _rotationX = 0.5;
                      _rotationY = 0.3;
                      _zoom3D = 1.0;
                    });
                  },
                  child: const Text('Reset View'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TerrainPoint {
  final double lat;
  final double lon;
  final double elevation;
  
  TerrainPoint({required this.lat, required this.lon, required this.elevation});
}

class Track3DPainter extends CustomPainter {
  final KmlTrack track;
  final double rotationX;
  final double rotationY;
  final double zoom;
  final List<TerrainPoint>? terrainGrid;
  final double terrainMinElev;
  final double terrainMaxElev;
  final ui.Image? topoImage;

  Track3DPainter({
    required this.track,
    required this.rotationX,
    required this.rotationY,
    required this.zoom,
    this.terrainGrid,
    this.terrainMinElev = 0,
    this.terrainMaxElev = 1000,
    this.topoImage,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (track.points.isEmpty) return;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    final latRange = track.maxLat - track.minLat;
    final lonRange = track.maxLon - track.minLon;
    final altRange = track.maxAltitude - track.minAltitude;
    final terrainElevRange = terrainMaxElev - terrainMinElev;

    final scale = math.min(size.width, size.height) * 0.35 * zoom;

    final cosX = math.cos(rotationX);
    final sinX = math.sin(rotationX);
    final cosY = math.cos(rotationY);
    final sinY = math.sin(rotationY);

    Offset project3D(double x, double y, double z) {
      double x1 = x * cosY - z * sinY;
      double z1 = x * sinY + z * cosY;
      double y1 = y * cosX - z1 * sinX;
      double z2 = y * sinX + z1 * cosX;

      final perspective = 1.0 + z2 * 0.3;
      final projX = centerX + x1 * scale / perspective;
      final projY = centerY - y1 * scale / perspective;

      return Offset(projX, projY);
    }

    if (terrainGrid != null && terrainGrid!.isNotEmpty) {
      _drawTerrain(canvas, size, project3D, latRange, lonRange, terrainElevRange);
    } else {
      _drawGrid(canvas, size, project3D);
    }

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final ui.Path path = ui.Path();
    final ui.Path shadowPath = ui.Path();

    for (int i = 0; i < track.points.length; i++) {
      final p = track.points[i];

      final normX = latRange > 0 ? (p.coordinate.latitude - track.minLat) / latRange - 0.5 : 0.0;
      final normZ = lonRange > 0 ? (p.coordinate.longitude - track.minLon) / lonRange - 0.5 : 0.0;
      final normY = altRange > 0 ? (p.altitude - track.minAltitude) / altRange : 0.0;

      final point3D = project3D(normX, normY * 0.5, normZ);
      final groundPoint = project3D(normX, 0, normZ);

      if (i == 0) {
        path.moveTo(point3D.dx, point3D.dy);
        shadowPath.moveTo(groundPoint.dx, groundPoint.dy);
      } else {
        path.lineTo(point3D.dx, point3D.dy);
        shadowPath.lineTo(groundPoint.dx, groundPoint.dy);
      }
    }

    final shadowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.black.withAlpha(50);
    canvas.drawPath(shadowPath, shadowPaint);

    for (int i = 0; i < track.points.length; i += math.max(1, track.points.length ~/ 20)) {
      final p = track.points[i];
      final normX = latRange > 0 ? (p.coordinate.latitude - track.minLat) / latRange - 0.5 : 0.0;
      final normZ = lonRange > 0 ? (p.coordinate.longitude - track.minLon) / lonRange - 0.5 : 0.0;
      final normY = altRange > 0 ? (p.altitude - track.minAltitude) / altRange : 0.0;

      final point3D = project3D(normX, normY * 0.5, normZ);
      final groundPoint = project3D(normX, 0, normZ);

      final dropPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = Colors.grey.withAlpha(100);
      canvas.drawLine(groundPoint, point3D, dropPaint);
    }

    trackPaint.shader = LinearGradient(
      colors: [Colors.green, Colors.yellow, Colors.orange, Colors.red],
      stops: const [0.0, 0.33, 0.66, 1.0],
    ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(path, trackPaint);

    if (track.points.isNotEmpty) {
      final first = track.points.first;
      final last = track.points.last;

      final firstNormX = latRange > 0 ? (first.coordinate.latitude - track.minLat) / latRange - 0.5 : 0.0;
      final firstNormZ = lonRange > 0 ? (first.coordinate.longitude - track.minLon) / lonRange - 0.5 : 0.0;
      final firstNormY = altRange > 0 ? (first.altitude - track.minAltitude) / altRange : 0.0;
      final firstPoint = project3D(firstNormX, firstNormY * 0.5, firstNormZ);

      final lastNormX = latRange > 0 ? (last.coordinate.latitude - track.minLat) / latRange - 0.5 : 0.0;
      final lastNormZ = lonRange > 0 ? (last.coordinate.longitude - track.minLon) / lonRange - 0.5 : 0.0;
      final lastNormY = altRange > 0 ? (last.altitude - track.minAltitude) / altRange : 0.0;
      final lastPoint = project3D(lastNormX, lastNormY * 0.5, lastNormZ);

      canvas.drawCircle(firstPoint, 8, Paint()..color = Colors.green);
      canvas.drawCircle(lastPoint, 8, Paint()..color = Colors.red);
    }

    _drawLegend(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size, Offset Function(double, double, double) project3D) {
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = Colors.grey.withAlpha(80);

    for (double x = -0.5; x <= 0.5; x += 0.25) {
      final start = project3D(x, 0, -0.5);
      final end = project3D(x, 0, 0.5);
      canvas.drawLine(start, end, gridPaint);
    }

    for (double z = -0.5; z <= 0.5; z += 0.25) {
      final start = project3D(-0.5, 0, z);
      final end = project3D(0.5, 0, z);
      canvas.drawLine(start, end, gridPaint);
    }

    final axisPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    axisPaint.color = Colors.red.withAlpha(150);
    canvas.drawLine(project3D(0, 0, 0), project3D(0.3, 0, 0), axisPaint);

    axisPaint.color = Colors.green.withAlpha(150);
    canvas.drawLine(project3D(0, 0, 0), project3D(0, 0.2, 0), axisPaint);

    axisPaint.color = Colors.blue.withAlpha(150);
    canvas.drawLine(project3D(0, 0, 0), project3D(0, 0, 0.3), axisPaint);
  }

  void _drawTerrain(Canvas canvas, Size size, Offset Function(double, double, double) project3D, 
      double latRange, double lonRange, double elevRange) {
    if (terrainGrid == null || terrainGrid!.isEmpty) return;
    
    final int gridSize = math.sqrt(terrainGrid!.length).round();
    if (gridSize < 2) return;
    
    const double maxTerrainHeight = 0.15;
    const double padding = 0.1;
    
    if (topoImage != null) {
      _drawTexturedTerrain(canvas, size, project3D, latRange, lonRange, elevRange, gridSize, maxTerrainHeight, padding);
    } else {
      _drawColoredTerrain(canvas, size, project3D, latRange, lonRange, elevRange, gridSize, maxTerrainHeight);
    }
  }

  void _drawTexturedTerrain(Canvas canvas, Size size, Offset Function(double, double, double) project3D,
      double latRange, double lonRange, double elevRange, int gridSize, double maxTerrainHeight, double padding) {
    final List<Offset> positions = [];
    final List<Offset> texCoords = [];
    final List<int> indices = [];
    
    final imgWidth = topoImage!.width.toDouble();
    final imgHeight = topoImage!.height.toDouble();
    
    for (int i = 0; i < gridSize; i++) {
      for (int j = 0; j < gridSize; j++) {
        final idx = i * gridSize + j;
        if (idx >= terrainGrid!.length) continue;
        
        final p = terrainGrid![idx];
        
        final normX = latRange > 0 ? (p.lat - track.minLat) / latRange - 0.5 : 0.0;
        final normZ = lonRange > 0 ? (p.lon - track.minLon) / lonRange - 0.5 : 0.0;
        final normY = elevRange > 0 ? ((p.elevation - terrainMinElev) / elevRange) * maxTerrainHeight : 0.0;
        
        final pt = project3D(normX, normY, normZ);
        positions.add(pt);
        
        final texU = (padding + (1.0 - 2.0 * padding) * (p.lon - track.minLon) / lonRange) * imgWidth;
        final texV = (padding + (1.0 - 2.0 * padding) * (1.0 - (p.lat - track.minLat) / latRange)) * imgHeight;
        texCoords.add(Offset(texU.clamp(0, imgWidth - 1), texV.clamp(0, imgHeight - 1)));
      }
    }
    
    for (int i = 0; i < gridSize - 1; i++) {
      for (int j = 0; j < gridSize - 1; j++) {
        final idx00 = i * gridSize + j;
        final idx01 = i * gridSize + j + 1;
        final idx10 = (i + 1) * gridSize + j;
        final idx11 = (i + 1) * gridSize + j + 1;
        
        if (idx11 >= positions.length) continue;
        
        indices.addAll([idx00, idx01, idx11]);
        indices.addAll([idx00, idx11, idx10]);
      }
    }
    
    if (positions.isEmpty || indices.isEmpty) return;
    
    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: texCoords,
      indices: indices,
    );
    
    final paint = Paint()
      ..shader = ImageShader(
        topoImage!,
        TileMode.clamp,
        TileMode.clamp,
        Matrix4.identity().storage,
      );
    
    canvas.drawVertices(vertices, BlendMode.srcOver, paint);
  }

  void _drawColoredTerrain(Canvas canvas, Size size, Offset Function(double, double, double) project3D,
      double latRange, double lonRange, double elevRange, int gridSize, double maxTerrainHeight) {
    for (int i = 0; i < gridSize - 1; i++) {
      for (int j = 0; j < gridSize - 1; j++) {
        final idx00 = i * gridSize + j;
        final idx01 = i * gridSize + j + 1;
        final idx10 = (i + 1) * gridSize + j;
        final idx11 = (i + 1) * gridSize + j + 1;
        
        if (idx11 >= terrainGrid!.length) continue;
        
        final p00 = terrainGrid![idx00];
        final p01 = terrainGrid![idx01];
        final p10 = terrainGrid![idx10];
        final p11 = terrainGrid![idx11];
        
        final normX00 = latRange > 0 ? (p00.lat - track.minLat) / latRange - 0.5 : 0.0;
        final normZ00 = lonRange > 0 ? (p00.lon - track.minLon) / lonRange - 0.5 : 0.0;
        final normY00 = elevRange > 0 ? ((p00.elevation - terrainMinElev) / elevRange) * maxTerrainHeight : 0.0;
        
        final normX01 = latRange > 0 ? (p01.lat - track.minLat) / latRange - 0.5 : 0.0;
        final normZ01 = lonRange > 0 ? (p01.lon - track.minLon) / lonRange - 0.5 : 0.0;
        final normY01 = elevRange > 0 ? ((p01.elevation - terrainMinElev) / elevRange) * maxTerrainHeight : 0.0;
        
        final normX10 = latRange > 0 ? (p10.lat - track.minLat) / latRange - 0.5 : 0.0;
        final normZ10 = lonRange > 0 ? (p10.lon - track.minLon) / lonRange - 0.5 : 0.0;
        final normY10 = elevRange > 0 ? ((p10.elevation - terrainMinElev) / elevRange) * maxTerrainHeight : 0.0;
        
        final normX11 = latRange > 0 ? (p11.lat - track.minLat) / latRange - 0.5 : 0.0;
        final normZ11 = lonRange > 0 ? (p11.lon - track.minLon) / lonRange - 0.5 : 0.0;
        final normY11 = elevRange > 0 ? ((p11.elevation - terrainMinElev) / elevRange) * maxTerrainHeight : 0.0;
        
        final pt00 = project3D(normX00, normY00, normZ00);
        final pt01 = project3D(normX01, normY01, normZ01);
        final pt10 = project3D(normX10, normY10, normZ10);
        final pt11 = project3D(normX11, normY11, normZ11);
        
        final avgElev = (p00.elevation + p01.elevation + p10.elevation + p11.elevation) / 4;
        final elevNorm = elevRange > 0 ? (avgElev - terrainMinElev) / elevRange : 0.0;
        
        final color = Color.lerp(
          const Color(0xFF2E7D32),
          const Color(0xFF8D6E63),
          elevNorm.clamp(0.0, 1.0),
        )!.withAlpha(180);
        
        final path = ui.Path();
        path.moveTo(pt00.dx, pt00.dy);
        path.lineTo(pt01.dx, pt01.dy);
        path.lineTo(pt11.dx, pt11.dy);
        path.lineTo(pt10.dx, pt10.dy);
        path.close();
        
        canvas.drawPath(path, Paint()
          ..color = color
          ..style = PaintingStyle.fill);
        
        canvas.drawPath(path, Paint()
          ..color = Colors.black.withAlpha(30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5);
      }
    }
  }

  void _drawLegend(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Alt: ${(track.minAltitude * 3.28084).toStringAsFixed(0)} - ${(track.maxAltitude * 3.28084).toStringAsFixed(0)} ft',
        style: const TextStyle(color: Colors.white, fontSize: 12, backgroundColor: Colors.black54),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(10, size.height - 30));
    
    if (terrainGrid != null && terrainGrid!.isNotEmpty) {
      final terrainTextPainter = TextPainter(
        text: TextSpan(
          text: 'Terrain: ${terrainMinElev.toStringAsFixed(0)} - ${terrainMaxElev.toStringAsFixed(0)} ft',
          style: const TextStyle(color: Colors.white, fontSize: 12, backgroundColor: Colors.black54),
        ),
        textDirection: TextDirection.ltr,
      );
      terrainTextPainter.layout();
      terrainTextPainter.paint(canvas, Offset(10, size.height - 50));
    }
  }

  @override
  bool shouldRepaint(covariant Track3DPainter oldDelegate) {
    return oldDelegate.rotationX != rotationX ||
        oldDelegate.rotationY != rotationY ||
        oldDelegate.zoom != zoom ||
        oldDelegate.terrainGrid != terrainGrid ||
        oldDelegate.topoImage != topoImage;
  }
}
