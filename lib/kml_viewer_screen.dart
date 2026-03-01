import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:avaremp/chart/chart.dart';
import 'package:avaremp/utils/epsg900913.dart';
import 'package:universal_io/io.dart';
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
  double _panX = 0.0;
  double _panY = 0.0;
  Offset? _lastFocalPoint;
  
  List<TerrainPoint>? _terrainGrid;
  double _terrainMinElev = 0;
  double _terrainMaxElev = 0;
  // Terrain grid bounds (may be expanded from track bounds)
  double _terrainMinLat = 0;
  double _terrainMaxLat = 0;
  double _terrainMinLon = 0;
  double _terrainMaxLon = 0;
  ui.Image? _topoImage;
  bool _loadingTopoImage = false;
  // Actual geographic bounds of the topo image (based on tile boundaries)
  double _topoMinLat = 0;
  double _topoMaxLat = 0;
  double _topoMinLon = 0;
  double _topoMaxLon = 0;

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
    
    // Increase grid size for larger coverage area
    const int gridSize = 25;
    final List<TerrainPoint> grid = [];
    
    // Add 20 nm buffer around the track
    // 1 degree latitude ≈ 60 nm, so 20 nm ≈ 0.333 degrees
    const double bufferNm = 20.0;
    const double nmPerDegreeLat = 60.0;
    final double latBuffer = bufferNm / nmPerDegreeLat;
    
    // For longitude, adjust for latitude (1 degree lon = 60 nm * cos(lat))
    final double avgLat = (track.minLat + track.maxLat) / 2;
    final double nmPerDegreeLon = 60.0 * math.cos(avgLat * math.pi / 180);
    final double lonBuffer = nmPerDegreeLon > 0 ? bufferNm / nmPerDegreeLon : latBuffer;
    
    double minLat = track.minLat - latBuffer;
    double maxLat = track.maxLat + latBuffer;
    double minLon = track.minLon - lonBuffer;
    double maxLon = track.maxLon + lonBuffer;
    
    double latRange = maxLat - minLat;
    double lonRange = maxLon - minLon;
    
    final latStep = latRange / (gridSize - 1);
    final lonStep = lonRange / (gridSize - 1);
    
    double minElev = double.infinity;
    double maxElev = double.negativeInfinity;
    int validElevationCount = 0;
    
    // First pass: collect all elevation data, mark missing as null
    List<double?> elevations = [];
    for (int i = 0; i < gridSize; i++) {
      for (int j = 0; j < gridSize; j++) {
        final lat = minLat + i * latStep;
        final lon = minLon + j * lonStep;
        final elevation = await ElevationCache.getElevation(LatLng(lat, lon));
        elevations.add(elevation);
        
        if (elevation != null) {
          if (elevation < minElev) minElev = elevation;
          if (elevation > maxElev) maxElev = elevation;
          validElevationCount++;
        }
      }
    }
    
    if (minElev == double.infinity) minElev = 0;
    if (maxElev == double.negativeInfinity) maxElev = 1000;
    
    // Calculate average elevation for filling missing values
    final double avgElev = validElevationCount > 0 
        ? (minElev + maxElev) / 2 
        : 0;
    
    // Second pass: fill missing elevations with interpolated/average values
    for (int i = 0; i < gridSize; i++) {
      for (int j = 0; j < gridSize; j++) {
        final idx = i * gridSize + j;
        final lat = minLat + i * latStep;
        final lon = minLon + j * lonStep;
        
        double elevation;
        if (elevations[idx] != null) {
          elevation = elevations[idx]!;
        } else {
          // Try to interpolate from neighbors
          double sum = 0;
          int count = 0;
          for (int di = -1; di <= 1; di++) {
            for (int dj = -1; dj <= 1; dj++) {
              if (di == 0 && dj == 0) continue;
              final ni = i + di;
              final nj = j + dj;
              if (ni >= 0 && ni < gridSize && nj >= 0 && nj < gridSize) {
                final nidx = ni * gridSize + nj;
                if (elevations[nidx] != null) {
                  sum += elevations[nidx]!;
                  count++;
                }
              }
            }
          }
          elevation = count > 0 ? sum / count : avgElev;
        }
        
        grid.add(TerrainPoint(lat: lat, lon: lon, elevation: elevation));
      }
    }
    
    if (mounted) {
      setState(() {
        // Only set terrain grid if we got at least some valid elevation data
        if (validElevationCount > 0) {
          _terrainGrid = grid;
          _terrainMinElev = minElev;
          _terrainMaxElev = maxElev;
          // Store the actual terrain grid bounds
          _terrainMinLat = minLat;
          _terrainMaxLat = maxLat;
          _terrainMinLon = minLon;
          _terrainMaxLon = maxLon;
        }
        _loadingTerrain = false;
      });
      // Load topo image with the expanded bounds
      _loadTopoImageWithBounds(minLat, maxLat, minLon, maxLon);
    }
  }

  Future<void> _loadTopoImageWithBounds(double minLat, double maxLat, double minLon, double maxLon) async {
    if (_loadingTopoImage) return;
    _loadingTopoImage = true;
    
    try {
      // Get current chart type
      final String chartType = Storage().settings.getChartType();
      final String chartIndex = ChartCategory.chartTypeToIndex(chartType);
      final String extension = ChartCategory.chartTypeToExtension(chartType);
      final int maxZoom = ChartCategory.chartTypeToZoom(chartType);
      
      // Use a zoom level that gives good detail but not too many tiles
      final int zoom = math.min(maxZoom, 9);
      final double zoomD = zoom.toDouble();
      
      // Use Epsg900913 to get tile coordinates (same as the rest of the app)
      final Epsg900913 projMinMin = Epsg900913.fromLatLon(minLat, minLon, zoomD);
      final Epsg900913 projMaxMax = Epsg900913.fromLatLon(maxLat, maxLon, zoomD);
      
      // Get tile range
      final int minTileX = math.min(projMinMin.getTilex(), projMaxMax.getTilex());
      final int maxTileX = math.max(projMinMin.getTilex(), projMaxMax.getTilex());
      final int minTileY = math.min(projMinMin.getTiley(), projMaxMax.getTiley());
      final int maxTileY = math.max(projMinMin.getTiley(), projMaxMax.getTiley());
      
      final int tilesX = maxTileX - minTileX + 1;
      final int tilesY = maxTileY - minTileY + 1;
      
      // Limit to reasonable number of tiles
      if (tilesX <= 0 || tilesY <= 0 || tilesX * tilesY > 25) {
        _loadingTopoImage = false;
        return;
      }
      
      const int tileSize = 512; // This app uses 512px tiles
      final int imageWidth = tilesX * tileSize;
      final int imageHeight = tilesY * tileSize;
      
      // Create a picture recorder to draw tiles onto
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      
      // Fill with a default color in case tiles are missing
      canvas.drawRect(
        Rect.fromLTWH(0, 0, imageWidth.toDouble(), imageHeight.toDouble()),
        Paint()..color = const Color(0xFFE8E4D8),
      );
      
      // Load and draw each tile
      final String basePath = '${Storage().dataDir}/tiles/$chartIndex/$zoom';
      int tilesLoaded = 0;
      
      for (int x = minTileX; x <= maxTileX; x++) {
        for (int y = minTileY; y <= maxTileY; y++) {
          final String tilePath = '$basePath/$x/$y.$extension';
          final File tileFile = File(tilePath);
          
          if (await tileFile.exists()) {
            try {
              final Uint8List bytes = await tileFile.readAsBytes();
              final ui.Codec codec = await ui.instantiateImageCodec(bytes);
              final ui.FrameInfo frame = await codec.getNextFrame();
              
              // Y is flipped in the image coordinate system
              final int destX = (x - minTileX) * tileSize;
              final int destY = (maxTileY - y) * tileSize;
              
              canvas.drawImage(
                frame.image,
                Offset(destX.toDouble(), destY.toDouble()),
                Paint(),
              );
              
              tilesLoaded++;
              frame.image.dispose();
              codec.dispose();
            } catch (e) {
              // Skip failed tiles
            }
          }
        }
      }
      
      // Only create image if we loaded at least one tile
      if (tilesLoaded > 0) {
        final ui.Picture picture = recorder.endRecording();
        final ui.Image image = await picture.toImage(imageWidth, imageHeight);
        picture.dispose();
        
        // Calculate the actual geographic bounds of the loaded tiles
        final Epsg900913 bottomLeftTile = Epsg900913.fromTile(minTileX, minTileY, zoomD);
        final Epsg900913 topRightTile = Epsg900913.fromTile(maxTileX, maxTileY, zoomD);
        
        // Bottom-left tile gives us minLon and minLat (lower-left corner)
        // Top-right tile gives us maxLon and maxLat (upper-right corner)
        final double tileMinLon = bottomLeftTile.getLonLowerLeft();
        final double tileMinLat = bottomLeftTile.getLatLowerLeft();
        final double tileMaxLon = topRightTile.getLonLowerRight();
        final double tileMaxLat = topRightTile.getLatUpperLeft();
        
        if (mounted) {
          setState(() {
            _topoImage = image;
            _topoMinLat = tileMinLat;
            _topoMaxLat = tileMaxLat;
            _topoMinLon = tileMinLon;
            _topoMaxLon = tileMaxLon;
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
        _lastFocalPoint = details.focalPoint;
      },
      onScaleUpdate: (details) {
        setState(() {
          if (details.pointerCount == 1) {
            // Single finger: pan
            if (_lastFocalPoint != null) {
              final delta = details.focalPoint - _lastFocalPoint!;
              _panX += delta.dx;
              _panY += delta.dy;
            }
            _lastFocalPoint = details.focalPoint;
          } else if (details.pointerCount >= 2) {
            // Two fingers: rotate and zoom
            // Handle zoom - also scale pan to keep content aligned
            if (details.scale != _lastScale) {
              final double scaleFactor = details.scale / _lastScale;
              _zoom3D = (_zoom3D * scaleFactor).clamp(0.5, 30.0);
              // Scale pan offset by the same factor to maintain alignment
              _panX *= scaleFactor;
              _panY *= scaleFactor;
              _lastScale = details.scale;
            }
            // Handle rotation
            _rotationY += details.focalPointDelta.dx * 0.01;
            _rotationX += details.focalPointDelta.dy * 0.01;
            _rotationX = _rotationX.clamp(-1.5, 1.5);
          }
        });
      },
      onScaleEnd: (details) {
        _lastFocalPoint = null;
      },
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                CustomPaint(
                  painter: Track3DPainter(
                    track: track,
                    rotationX: _rotationX,
                    rotationY: _rotationY,
                    zoom: _zoom3D,
                    panX: _panX,
                    panY: _panY,
                    terrainGrid: _terrainGrid,
                    terrainMinElev: _terrainMinElev,
                    terrainMaxElev: _terrainMaxElev,
                    terrainMinLat: _terrainMinLat,
                    terrainMaxLat: _terrainMaxLat,
                    terrainMinLon: _terrainMinLon,
                    terrainMaxLon: _terrainMaxLon,
                    topoImage: _topoImage,
                    topoMinLat: _topoMinLat,
                    topoMaxLat: _topoMaxLat,
                    topoMinLon: _topoMinLon,
                    topoMaxLon: _topoMaxLon,
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
                      _panX = 0.0;
                      _panY = 0.0;
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
  final double panX;
  final double panY;
  final List<TerrainPoint>? terrainGrid;
  final double terrainMinElev;
  final double terrainMaxElev;
  final double terrainMinLat;
  final double terrainMaxLat;
  final double terrainMinLon;
  final double terrainMaxLon;
  final ui.Image? topoImage;
  final double topoMinLat;
  final double topoMaxLat;
  final double topoMinLon;
  final double topoMaxLon;

  Track3DPainter({
    required this.track,
    required this.rotationX,
    required this.rotationY,
    required this.zoom,
    this.panX = 0,
    this.panY = 0,
    this.terrainGrid,
    this.terrainMinElev = 0,
    this.terrainMaxElev = 1000,
    this.terrainMinLat = 0,
    this.terrainMaxLat = 0,
    this.terrainMinLon = 0,
    this.terrainMaxLon = 0,
    this.topoImage,
    this.topoMinLat = 0,
    this.topoMaxLat = 0,
    this.topoMinLon = 0,
    this.topoMaxLon = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (track.points.isEmpty) return;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Use terrain bounds (with 20nm buffer) as the coordinate system
    // This ensures terrain fills the view and track is positioned within it
    final bool hasTerrainBounds = terrainMaxLat > terrainMinLat && terrainMaxLon > terrainMinLon;
    final double viewMinLat = hasTerrainBounds ? terrainMinLat : track.minLat;
    final double viewMaxLat = hasTerrainBounds ? terrainMaxLat : track.maxLat;
    final double viewMinLon = hasTerrainBounds ? terrainMinLon : track.minLon;
    final double viewMaxLon = hasTerrainBounds ? terrainMaxLon : track.maxLon;
    
    final latRange = viewMaxLat - viewMinLat;
    final lonRange = viewMaxLon - viewMinLon;
    
    // Overall elevation range (from lowest terrain to highest track altitude)
    final double overallMinElev = terrainMinElev;
    final double overallMaxElev = math.max(terrainMaxElev, track.maxAltitude * 3.28084);
    final double overallElevRange = overallMaxElev - overallMinElev;
    
    // Normalize vertical axis to screen space
    // Use a moderate height proportion so altitude is visible but not overwhelming
    const double targetVerticalHeight = 0.125;
    final double verticalScale = targetVerticalHeight;

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
      final projX = centerX + x1 * scale / perspective + panX;
      final projY = centerY - y1 * scale / perspective + panY;

      return Offset(projX, projY);
    }

    if (terrainGrid != null && terrainGrid!.isNotEmpty) {
      _drawTerrain(canvas, size, project3D, latRange, lonRange, overallMinElev, overallElevRange, verticalScale);
    } else {
      _drawGrid(canvas, size, project3D);
    }

    // Draw vertical scale
    _drawVerticalScale(canvas, size, project3D, overallMinElev, overallElevRange, verticalScale);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final ui.Path path = ui.Path();
    final ui.Path shadowPath = ui.Path();

    for (int i = 0; i < track.points.length; i++) {
      final p = track.points[i];

      // Use view bounds (terrain bounds with buffer) for positioning
      final normX = latRange > 0 ? (p.coordinate.latitude - viewMinLat) / latRange - 0.5 : 0.0;
      final normZ = lonRange > 0 ? (p.coordinate.longitude - viewMinLon) / lonRange - 0.5 : 0.0;
      // Use unified vertical scale based on actual feet MSL
      final altFt = p.altitude * 3.28084;
      final normY = overallElevRange > 0 ? ((altFt - overallMinElev) / overallElevRange) * verticalScale : 0.0;

      final point3D = project3D(normX, normY, normZ);
      // Ground at actual terrain surface (interpolated)
      final terrainElev = _getTerrainElevationAt(p.coordinate.latitude, p.coordinate.longitude);
      final groundY = overallElevRange > 0 ? ((terrainElev - overallMinElev) / overallElevRange) * verticalScale : 0.0;
      final groundPoint = project3D(normX, groundY, normZ);

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
      final normX = latRange > 0 ? (p.coordinate.latitude - viewMinLat) / latRange - 0.5 : 0.0;
      final normZ = lonRange > 0 ? (p.coordinate.longitude - viewMinLon) / lonRange - 0.5 : 0.0;
      final altFt = p.altitude * 3.28084;
      final normY = overallElevRange > 0 ? ((altFt - overallMinElev) / overallElevRange) * verticalScale : 0.0;

      final point3D = project3D(normX, normY, normZ);
      // Drop line goes to actual terrain surface
      final terrainElev = _getTerrainElevationAt(p.coordinate.latitude, p.coordinate.longitude);
      final groundY = overallElevRange > 0 ? ((terrainElev - overallMinElev) / overallElevRange) * verticalScale : 0.0;
      final groundPoint = project3D(normX, groundY, normZ);

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

      final firstNormX = latRange > 0 ? (first.coordinate.latitude - viewMinLat) / latRange - 0.5 : 0.0;
      final firstNormZ = lonRange > 0 ? (first.coordinate.longitude - viewMinLon) / lonRange - 0.5 : 0.0;
      final firstAltFt = first.altitude * 3.28084;
      final firstNormY = overallElevRange > 0 ? ((firstAltFt - overallMinElev) / overallElevRange) * verticalScale : 0.0;
      final firstPoint = project3D(firstNormX, firstNormY, firstNormZ);

      final lastNormX = latRange > 0 ? (last.coordinate.latitude - viewMinLat) / latRange - 0.5 : 0.0;
      final lastNormZ = lonRange > 0 ? (last.coordinate.longitude - viewMinLon) / lonRange - 0.5 : 0.0;
      final lastAltFt = last.altitude * 3.28084;
      final lastNormY = overallElevRange > 0 ? ((lastAltFt - overallMinElev) / overallElevRange) * verticalScale : 0.0;
      final lastPoint = project3D(lastNormX, lastNormY, lastNormZ);

      canvas.drawCircle(firstPoint, 8, Paint()..color = Colors.green);
      canvas.drawCircle(lastPoint, 8, Paint()..color = Colors.red);
    }

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

  void _drawVerticalScale(Canvas canvas, Size size, Offset Function(double, double, double) project3D,
      double overallMinElev, double overallElevRange, double verticalScale) {
    if (overallElevRange <= 0) return;
    
    final scalePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.grey.shade700;
    
    // Position the scale at the back-left corner of the view
    const double scaleX = -0.5;
    const double scaleZ = -0.5;
    
    // Draw main vertical line
    final bottom = project3D(scaleX, 0, scaleZ);
    final top = project3D(scaleX, verticalScale, scaleZ);
    canvas.drawLine(bottom, top, scalePaint);
    
    // Round min elevation down to nearest 1000, max up to nearest 1000
    final int minElev1k = ((overallMinElev / 1000).floor() * 1000);
    final int maxElev1k = ((overallMinElev + overallElevRange) / 1000).ceil() * 1000;
    
    // Draw tick marks and labels at 1000ft increments
    for (int elev = minElev1k; elev <= maxElev1k; elev += 1000) {
      if (elev < overallMinElev || elev > overallMinElev + overallElevRange) continue;
      
      final normY = ((elev - overallMinElev) / overallElevRange) * verticalScale;
      final tickStart = project3D(scaleX, normY, scaleZ);
      final tickEnd = project3D(scaleX - 0.02, normY, scaleZ);
      
      canvas.drawLine(tickStart, tickEnd, scalePaint);
      
      // Draw elevation label
      final label = '${(elev / 1000).round()}k';
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 8,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(tickEnd.dx - textPainter.width - 2, tickEnd.dy - textPainter.height / 2));
    }
  }

  void _drawTerrain(Canvas canvas, Size size, Offset Function(double, double, double) project3D, 
      double latRange, double lonRange, double overallMinElev, double overallElevRange, double verticalScale) {
    if (terrainGrid == null || terrainGrid!.isEmpty) return;
    
    final int gridSize = math.sqrt(terrainGrid!.length).round();
    if (gridSize < 2) return;
    
    const double padding = 0.1;
    
    // Use terrain bounds for terrain rendering (may be expanded from track bounds)
    final tLatRange = terrainMaxLat - terrainMinLat;
    final tLonRange = terrainMaxLon - terrainMinLon;
    
    if (topoImage != null) {
      _drawTexturedTerrain(canvas, size, project3D, tLatRange, tLonRange, overallMinElev, overallElevRange, verticalScale, gridSize, padding);
    } else {
      _drawColoredTerrain(canvas, size, project3D, tLatRange, tLonRange, overallMinElev, overallElevRange, verticalScale, gridSize);
    }
  }

  void _drawTexturedTerrain(Canvas canvas, Size size, Offset Function(double, double, double) project3D,
      double tLatRange, double tLonRange, double overallMinElev, double overallElevRange, double verticalScale, int gridSize, double padding) {
    final List<Offset> positions = [];
    final List<Offset> texCoords = [];
    final List<int> indices = [];
    
    final imgWidth = topoImage!.width.toDouble();
    final imgHeight = topoImage!.height.toDouble();
    
    // Calculate topo image's geographic range
    final topoLatRange = topoMaxLat - topoMinLat;
    final topoLonRange = topoMaxLon - topoMinLon;
    
    for (int i = 0; i < gridSize; i++) {
      for (int j = 0; j < gridSize; j++) {
        final idx = i * gridSize + j;
        if (idx >= terrainGrid!.length) continue;
        
        final p = terrainGrid![idx];
        
        // Use terrain bounds for positioning (view is based on terrain bounds with 20nm buffer)
        final normX = tLatRange > 0 ? (p.lat - terrainMinLat) / tLatRange - 0.5 : 0.0;
        final normZ = tLonRange > 0 ? (p.lon - terrainMinLon) / tLonRange - 0.5 : 0.0;
        // Use unified vertical scale based on feet MSL
        final normY = overallElevRange > 0 ? ((p.elevation - overallMinElev) / overallElevRange) * verticalScale : 0.0;
        
        final pt = project3D(normX, normY, normZ);
        positions.add(pt);
        
        // Use topo bounds for texture coordinates (the actual geographic extent of loaded tiles)
        // texU: longitude maps to X (left to right)
        // texV: latitude maps to Y (top is higher lat, bottom is lower lat)
        final texU = topoLonRange > 0 
            ? ((p.lon - topoMinLon) / topoLonRange) * imgWidth
            : imgWidth / 2;
        final texV = topoLatRange > 0 
            ? ((topoMaxLat - p.lat) / topoLatRange) * imgHeight
            : imgHeight / 2;
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
      double tLatRange, double tLonRange, double overallMinElev, double overallElevRange, double verticalScale, int gridSize) {
    final terrainElevRange = terrainMaxElev - terrainMinElev;
    
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
        
        // Use terrain bounds for positioning (view is based on terrain bounds with 20nm buffer)
        final normX00 = tLatRange > 0 ? (p00.lat - terrainMinLat) / tLatRange - 0.5 : 0.0;
        final normZ00 = tLonRange > 0 ? (p00.lon - terrainMinLon) / tLonRange - 0.5 : 0.0;
        // Use unified vertical scale based on feet MSL
        final normY00 = overallElevRange > 0 ? ((p00.elevation - overallMinElev) / overallElevRange) * verticalScale : 0.0;
        
        final normX01 = tLatRange > 0 ? (p01.lat - terrainMinLat) / tLatRange - 0.5 : 0.0;
        final normZ01 = tLonRange > 0 ? (p01.lon - terrainMinLon) / tLonRange - 0.5 : 0.0;
        final normY01 = overallElevRange > 0 ? ((p01.elevation - overallMinElev) / overallElevRange) * verticalScale : 0.0;
        
        final normX10 = tLatRange > 0 ? (p10.lat - terrainMinLat) / tLatRange - 0.5 : 0.0;
        final normZ10 = tLonRange > 0 ? (p10.lon - terrainMinLon) / tLonRange - 0.5 : 0.0;
        final normY10 = overallElevRange > 0 ? ((p10.elevation - overallMinElev) / overallElevRange) * verticalScale : 0.0;
        
        final normX11 = tLatRange > 0 ? (p11.lat - terrainMinLat) / tLatRange - 0.5 : 0.0;
        final normZ11 = tLonRange > 0 ? (p11.lon - terrainMinLon) / tLonRange - 0.5 : 0.0;
        final normY11 = overallElevRange > 0 ? ((p11.elevation - overallMinElev) / overallElevRange) * verticalScale : 0.0;
        
        final pt00 = project3D(normX00, normY00, normZ00);
        final pt01 = project3D(normX01, normY01, normZ01);
        final pt10 = project3D(normX10, normY10, normZ10);
        final pt11 = project3D(normX11, normY11, normZ11);
        
        // Color based on terrain elevation range (for visual differentiation)
        final avgElev = (p00.elevation + p01.elevation + p10.elevation + p11.elevation) / 4;
        final elevNorm = terrainElevRange > 0 ? (avgElev - terrainMinElev) / terrainElevRange : 0.0;
        
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

  double _getTerrainElevationAt(double lat, double lon) {
    if (terrainGrid == null || terrainGrid!.isEmpty) return terrainMinElev;
    
    final int gridSize = math.sqrt(terrainGrid!.length).round();
    if (gridSize < 2) return terrainMinElev;
    
    final tLatRange = terrainMaxLat - terrainMinLat;
    final tLonRange = terrainMaxLon - terrainMinLon;
    
    if (tLatRange <= 0 || tLonRange <= 0) return terrainMinElev;
    
    // Normalize lat/lon to grid coordinates
    final double normLat = (lat - terrainMinLat) / tLatRange;
    final double normLon = (lon - terrainMinLon) / tLonRange;
    
    // Clamp to grid bounds
    final double gridX = (normLat * (gridSize - 1)).clamp(0, gridSize - 1.001);
    final double gridY = (normLon * (gridSize - 1)).clamp(0, gridSize - 1.001);
    
    // Get the four surrounding grid points
    final int x0 = gridX.floor();
    final int y0 = gridY.floor();
    final int x1 = (x0 + 1).clamp(0, gridSize - 1);
    final int y1 = (y0 + 1).clamp(0, gridSize - 1);
    
    // Bilinear interpolation weights
    final double fx = gridX - x0;
    final double fy = gridY - y0;
    
    // Get elevations at four corners
    final double e00 = terrainGrid![x0 * gridSize + y0].elevation;
    final double e01 = terrainGrid![x0 * gridSize + y1].elevation;
    final double e10 = terrainGrid![x1 * gridSize + y0].elevation;
    final double e11 = terrainGrid![x1 * gridSize + y1].elevation;
    
    // Bilinear interpolation
    final double e0 = e00 * (1 - fy) + e01 * fy;
    final double e1 = e10 * (1 - fy) + e11 * fy;
    return e0 * (1 - fx) + e1 * fx;
  }

  @override
  bool shouldRepaint(covariant Track3DPainter oldDelegate) {
    return oldDelegate.rotationX != rotationX ||
        oldDelegate.rotationY != rotationY ||
        oldDelegate.zoom != zoom ||
        oldDelegate.panX != panX ||
        oldDelegate.panY != panY ||
        oldDelegate.terrainGrid != terrainGrid ||
        oldDelegate.topoImage != topoImage;
  }
}
