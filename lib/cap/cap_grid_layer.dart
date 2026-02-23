import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class CapChart {
  final String identifier;
  final double northWestLon;
  final double northWestLat;
  final double southEastLon;
  final double southEastLat;

  const CapChart(this.identifier, this.northWestLon, this.northWestLat, this.southEastLon, this.southEastLat);

  bool containsGrid(double gridLat, double gridLon) {
    return gridLon >= northWestLon && 
           gridLon < southEastLon && 
           gridLat <= northWestLat && 
           gridLat > southEastLat;
  }

  int getGridIndex(double gridLat, double gridLon) {
    int xDivs = ((southEastLon - northWestLon) / CapGridLayer.gridSize).round();
    int distX = ((gridLon - northWestLon) / CapGridLayer.gridSize).round();
    int distY = ((northWestLat - gridLat) / CapGridLayer.gridSize).round();
    return distY * xDivs + distX + 1;
  }
}

class CapGridLayer {
  static const double gridSize = 0.25;
  static const Color gridColor = Colors.blue;
  static const double gridStrokeWidth = 2.0;

  static const List<CapChart> _charts = [
    CapChart("SEA", -125, 49, -117, 44.5),
    CapChart("GTF", -117, 49, -109, 44.5),
    CapChart("BIL", -109, 49, -101, 44.5),
    CapChart("MSP", -101, 49, -93, 44.5),
    CapChart("GRB", -93, 48.25, -85, 44),
    CapChart("LHN", -85, 48, -77, 44),
    CapChart("MON", -77, 48, -69, 44),
    CapChart("HFX", -69, 48, -61, 44),
    CapChart("LMT", -125, 44.5, -117, 40),
    CapChart("SLC", -117, 44.5, -109, 40),
    CapChart("CYS", -109, 44.5, -101, 40),
    CapChart("OMA", -101, 44.5, -93, 40),
    CapChart("ORD", -93, 44, -85, 40),
    CapChart("DET", -85, 44, -77, 40),
    CapChart("NYC", -77, 44, -69, 40),
    CapChart("SFO", -125, 40, -118, 36),
    CapChart("LAS", -118, 40, -111, 35.75),
    CapChart("DEN", -111, 40, -104, 35.75),
    CapChart("ICT", -104, 40, -97, 36),
    CapChart("MKC", -97, 40, -90, 36),
    CapChart("STL", -91, 40, -84, 36),
    CapChart("LUK", -85, 40, -78, 36),
    CapChart("DCA", -79, 40, -72, 36),
    CapChart("LAX", -121.5, 36, -115, 32),
    CapChart("PHX", -116, 35.75, -109, 31.25),
    CapChart("ABQ", -109, 36, -102, 32),
    CapChart("DFW", -102, 36, -95, 32),
    CapChart("MEM", -95, 36, -88, 32),
    CapChart("ATL", -88, 36, -81, 32),
    CapChart("CLT", -81, 36, -75, 32),
    CapChart("ELP", -109, 32, -103, 28),
    CapChart("SAT", -103, 32, -97, 28),
    CapChart("HOU", -97, 32, -91, 28),
    CapChart("MSY", -91, 32, -85, 28),
    CapChart("JAX", -85, 32, -79, 28),
    CapChart("BRO", -103, 28, -97, 24),
    CapChart("MIA", -83, 28, -77, 24),
  ];

  CapChart? _recentChart;

  PolylineLayer? _cachedPolylineLayer;
  MarkerLayer? _cachedMarkerLayer;
  double? _cachedCenterLat;
  double? _cachedCenterLon;
  double? _cachedZoom;

  double _snapToGrid(double value) {
    double snapped = (value / gridSize).round() * gridSize;
    return (snapped * 100).round() / 100;
  }

  String _getGridName(double topLeftLat, double topLeftLon) {
    if (_recentChart != null && _recentChart!.containsGrid(topLeftLat, topLeftLon)) {
      return "${_recentChart!.identifier}${_recentChart!.getGridIndex(topLeftLat, topLeftLon)}";
    }

    for (CapChart chart in _charts) {
      if (chart.containsGrid(topLeftLat, topLeftLon)) {
        _recentChart = chart;
        return "${chart.identifier}${chart.getGridIndex(topLeftLat, topLeftLon)}";
      }
    }
    return "";
  }

  (PolylineLayer, MarkerLayer) build({
    required LatLng center,
    required double zoom,
  }) {
    if (zoom < 9) {
      _cachedPolylineLayer = PolylineLayer(polylines: []);
      _cachedMarkerLayer = MarkerLayer(markers: []);
      return (_cachedPolylineLayer!, _cachedMarkerLayer!);
    }

    double roundedLat = (center.latitude * 4).roundToDouble() / 4;
    double roundedLon = (center.longitude * 4).roundToDouble() / 4;
    double roundedZoom = zoom.roundToDouble();

    if (_cachedPolylineLayer != null &&
        _cachedMarkerLayer != null &&
        _cachedCenterLat == roundedLat &&
        _cachedCenterLon == roundedLon &&
        _cachedZoom == roundedZoom) {
      return (_cachedPolylineLayer!, _cachedMarkerLayer!);
    }

    _cachedCenterLat = roundedLat;
    _cachedCenterLon = roundedLon;
    _cachedZoom = roundedZoom;

    int gridCount = 4;

    double latitudeUpper = _snapToGrid(center.latitude + gridSize * gridCount);
    double latitudeLower = _snapToGrid(center.latitude - gridSize * gridCount);
    double longitudeLeft = _snapToGrid(center.longitude - gridSize * gridCount);
    double longitudeRight = _snapToGrid(center.longitude + gridSize * gridCount);

    List<Polyline> polylines = [];

    for (double lat = latitudeUpper; lat >= latitudeLower; lat -= gridSize) {
      polylines.add(Polyline(
        points: [
          LatLng(lat, longitudeLeft),
          LatLng(lat, longitudeRight),
        ],
        color: gridColor,
        strokeWidth: gridStrokeWidth,
        borderColor: Colors.white,
        borderStrokeWidth: 1,
      ));
    }

    for (double lon = longitudeLeft; lon <= longitudeRight; lon += gridSize) {
      polylines.add(Polyline(
        points: [
          LatLng(latitudeUpper, lon),
          LatLng(latitudeLower, lon),
        ],
        color: gridColor,
        strokeWidth: gridStrokeWidth,
        borderColor: Colors.white,
        borderStrokeWidth: 1,
      ));
    }

    List<Marker> markers = [];

    for (double lat = latitudeUpper; lat > latitudeLower; lat -= gridSize) {
      for (double lon = longitudeLeft; lon < longitudeRight; lon += gridSize) {
        String gridName = _getGridName(lat, lon);
        if (gridName.isNotEmpty) {
          markers.add(Marker(
            point: LatLng(lat - gridSize / 2, lon + gridSize / 2),
            width: 80,
            height: 24,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(
                  gridName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ));
        }
      }
    }

    _cachedPolylineLayer = PolylineLayer(polylines: polylines);
    _cachedMarkerLayer = MarkerLayer(markers: markers);

    return (_cachedPolylineLayer!, _cachedMarkerLayer!);
  }
}
