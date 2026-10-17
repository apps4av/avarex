import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:avaremp/place/airspace_volume.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:mbtiles/mbtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

class MBTilesLayerManager {
  MbTiles? _mbtiles;
  String? _currentPath;
  MbTilesMetadata? _metadata;
  bool _isVector = false;
  List<String> _layerNames = [];

  bool get isLoaded => _mbtiles != null;
  bool get isVector => _isVector;
  MbTilesMetadata? get metadata => _metadata;
  LatLng? get defaultCenter => _metadata?.defaultCenter;
  double? get defaultZoom => _metadata?.defaultZoom;
  int? get minZoom => _metadata?.minZoom?.toInt();
  int? get maxZoom => _metadata?.maxZoom?.toInt();
  List<String> get layerNames => _layerNames;

  Future<bool> loadMBTiles(String path) async {
    if (path.isEmpty) {
      return false;
    }

    if (_currentPath == path && _mbtiles != null) {
      return true;
    }

    close();

    try {
      final file = File(path);
      if (!file.existsSync()) {
        return false;
      }

      _mbtiles = MbTiles(mbtilesPath: path);
      _metadata = _mbtiles!.getMetadata();
      _currentPath = path;

      _isVector = _metadata?.format == 'pbf' || _metadata?.format == 'mvt';
      
      _layerNames = _extractLayerNames(_metadata);

      return true;
    } catch (e) {
      close();
      return false;
    }
  }

  List<String> _extractLayerNames(MbTilesMetadata? metadata) {
    if (metadata?.json == null) return [];
    try {
      final jsonStr = metadata!.json!;
      final Map<String, dynamic> jsonData = jsonDecode(jsonStr);
      if (jsonData.containsKey('vector_layers')) {
        final layers = jsonData['vector_layers'] as List;
        return layers.map((l) => l['id'] as String).toList();
      }
    } catch (e) {
      // Ignore parsing errors
    }
    return [];
  }

  void close() {
    _mbtiles?.dispose();
    _mbtiles = null;
    _metadata = null;
    _currentPath = null;
    _isVector = false;
    _layerNames = [];
  }

  List<Widget> buildVectorMapLayers({double opacity = 1.0, String? airportDbPath}) {
    if (_mbtiles == null || !_isVector) {
      return const [];
    }

    final minZ = _metadata?.minZoom?.toInt() ?? 0;
    final maxZ = _metadata?.maxZoom?.toInt() ?? 14;

    final provider = MbTilesVectorTileProvider(
      mbtiles: _mbtiles!,
      maxZoom: maxZ,
      minZoom: minZ,
    );

    return [
      Opacity(
        opacity: opacity,
        child: VectorTileLayer(
          key: const ValueKey('mbtiles_vector_layer'),
          tileProviders: TileProviders({
            'mbtiles': provider,
          }),
          theme: _buildTheme(_layerNames),
          layerMode: VectorTileLayerMode.vector,
        ),
      ),
      IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: _AirspaceLabelOverlay(mbtiles: _mbtiles!, maxTileZoom: maxZ, airportDbPath: airportDbPath),
        ),
      ),
    ];
  }

  Widget? buildRasterTileLayer({double opacity = 1.0}) {
    if (_mbtiles == null || _isVector) {
      return null;
    }

    return Opacity(
      opacity: opacity,
      child: TileLayer(
        tileProvider: MBTilesRasterTileProvider(_mbtiles!),
        minZoom: _metadata?.minZoom?.toDouble() ?? 0,
        // maxNativeZoom is the max zoom of actual tile data
        // maxZoom allows overzooming (scaling up tiles at higher zoom)
        maxNativeZoom: _metadata?.maxZoom?.toInt() ?? 18,
        maxZoom: 20,
      ),
    );
  }

  /// Layer count for the NASR airspace theme, including sector outlines.
  @visibleForTesting
  static int debugThemeLayerCount() => _buildTheme(const [
        'class_airspace',
        'class_airspace_labels',
        'sua_airspace',
        'sua_airspace_labels',
      ]).layers.length;

  static vtr.Theme _buildTheme(List<String> layerNames) {
    final List<Map<String, dynamic>> layers = [];

    for (final layerName in layerNames) {
      if (layerName == 'class_airspace') {
        layers.addAll(_buildClassAirspaceThemeLayers(layerName));
      } else if (layerName == 'sua_airspace') {
        layers.addAll(_buildSuaAirspaceThemeLayers(layerName));
      } else if (layerName == 'class_airspace_labels' || layerName == 'sua_airspace_labels') {
        // Drawn by _AirspaceLabelOverlay at the shelf's own location.
      } else {
        layers.addAll(_buildGenericThemeLayers(layerName));
      }
    }

    if (layers.isEmpty) {
      layers.addAll(_buildDefaultThemeLayers());
    }

    return vtr.ThemeReader().read({
      'version': 8,
      'name': 'MBTiles',
      'sources': {
        'mbtiles': {'type': 'vector'}
      },
      'layers': layers,
    });
  }

  static List<Map<String, dynamic>> _buildClassAirspaceThemeLayers(String layerName) {
    return [
      {
        'id': '${layerName}_class_b_fill',
        'type': 'fill',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'CLASS', 'B'],
        'paint': {
          'fill-color': '#0000FF',
          'fill-opacity': 0.35,
        }
      },
      {
        'id': '${layerName}_class_b_line',
        'type': 'line',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'CLASS', 'B'],
        'paint': {
          'line-color': '#0000FF',
          'line-width': 1.4,
        }
      },
      {
        'id': '${layerName}_class_c_fill',
        'type': 'fill',
        'source': 'mbtiles',
        'source-layer': layerName,
        'minzoom': airspaceClassCZoom,
        'filter': ['==', 'CLASS', 'C'],
        'paint': {
          'fill-color': '#FF00FF',
          'fill-opacity': 0.3,
        }
      },
      {
        'id': '${layerName}_class_c_line',
        'type': 'line',
        'source': 'mbtiles',
        'source-layer': layerName,
        'minzoom': airspaceClassCZoom,
        'filter': ['==', 'CLASS', 'C'],
        'paint': {
          'line-color': '#FF00FF',
          'line-width': 1.4,
        }
      },
      {
        'id': '${layerName}_class_d_fill',
        'type': 'fill',
        'source': 'mbtiles',
        'source-layer': layerName,
        'minzoom': airspaceDetailZoom,
        'filter': ['==', 'CLASS', 'D'],
        'paint': {
          'fill-color': '#0088FF',
          'fill-opacity': 0.25,
        }
      },
      {
        'id': '${layerName}_class_d_line',
        'type': 'line',
        'source': 'mbtiles',
        'source-layer': layerName,
        'minzoom': airspaceDetailZoom,
        'filter': ['==', 'CLASS', 'D'],
        'paint': {
          'line-color': '#0088FF',
          'line-width': 1.4,
        }
      },
    ];
  }

  static List<Map<String, dynamic>> _buildSuaAirspaceThemeLayers(String layerName) {
    return [
      // MOA (Military Operations Area) - Magenta/Brown hatched
      {
        'id': '${layerName}_moa_fill',
        'type': 'fill',
        'source': 'mbtiles',
        'source-layer': layerName,
        'minzoom': airspaceLargeSuaZoom,
        'filter': ['==', 'TYPE', 'MOA'],
        'paint': {
          'fill-color': '#996633',
          'fill-opacity': 0.25,
        }
      },
      // Restricted Area - Blue hatched
      {
        'id': '${layerName}_restricted_fill',
        'type': 'fill',
        'source': 'mbtiles',
        'source-layer': layerName,
        'minzoom': airspaceLargeSuaZoom,
        'filter': ['==', 'TYPE', 'RESTRICTED'],
        'paint': {
          'fill-color': '#0066FF',
          'fill-opacity': 0.3,
        }
      },
      // Warning Area - Blue hatched (offshore)
      {
        'id': '${layerName}_warning_fill',
        'type': 'fill',
        'source': 'mbtiles',
        'source-layer': layerName,
        'minzoom': airspaceLargeSuaZoom,
        'filter': ['==', 'TYPE', 'WARNING'],
        'paint': {
          'fill-color': '#0088FF',
          'fill-opacity': 0.25,
        }
      },
      // Alert Area - Orange
      {
        'id': '${layerName}_alert_fill',
        'type': 'fill',
        'source': 'mbtiles',
        'source-layer': layerName,
        'minzoom': airspaceDetailZoom,
        'filter': ['==', 'TYPE', 'ALERT'],
        'paint': {
          'fill-color': '#FF8800',
          'fill-opacity': 0.25,
        }
      },
      // Prohibited Area - Red (no-fly zone)
      {
        'id': '${layerName}_prohibited_fill',
        'type': 'fill',
        'source': 'mbtiles',
        'source-layer': layerName,
        'minzoom': airspaceDetailZoom,
        'filter': ['==', 'TYPE', 'PROHIBITED'],
        'paint': {
          'fill-color': '#FF0000',
          'fill-opacity': 0.35,
        }
      },
      // NSA (National Security Area) - Green
      {
        'id': '${layerName}_nsa_fill',
        'type': 'fill',
        'source': 'mbtiles',
        'source-layer': layerName,
        'minzoom': airspaceDetailZoom,
        'filter': ['==', 'TYPE', 'NSA'],
        'paint': {
          'fill-color': '#228B22',
          'fill-opacity': 0.25,
        }
      },
      _outline(layerName, 'moa', 'MOA', '#996633', airspaceLargeSuaZoom),
      _outline(layerName, 'restricted', 'RESTRICTED', '#0066FF', airspaceLargeSuaZoom),
      _outline(layerName, 'warning', 'WARNING', '#0088FF', airspaceLargeSuaZoom),
      _outline(layerName, 'alert', 'ALERT', '#FF8800', airspaceDetailZoom),
      _outline(layerName, 'prohibited', 'PROHIBITED', '#FF0000', airspaceDetailZoom),
      _outline(layerName, 'nsa', 'NSA', '#228B22', airspaceDetailZoom),
    ];
  }

  static Map<String, dynamic> _outline(String layerName, String id, String type, String color, int minZoom) {
    return {
      'id': '${layerName}_${id}_line',
      'type': 'line',
      'source': 'mbtiles',
      'source-layer': layerName,
      'minzoom': minZoom,
      'filter': ['==', 'TYPE', type],
      'paint': {
        'line-color': color,
        'line-width': 1.4,
      },
    };
  }

  static List<Map<String, dynamic>> _buildGenericThemeLayers(String layerName) {
    return [
      {
        'id': '${layerName}_fill',
        'type': 'fill',
        'source': 'mbtiles',
        'source-layer': layerName,
        'paint': {
          'fill-color': '#88AAFF',
          'fill-opacity': 0.3,
        }
      },
      {
        'id': '${layerName}_line',
        'type': 'line',
        'source': 'mbtiles',
        'source-layer': layerName,
        'paint': {
          'line-color': '#4466CC',
          'line-width': 1.5,
        }
      },
    ];
  }

  static List<Map<String, dynamic>> _buildDefaultThemeLayers() {
    return [
      {
        'id': 'default_fill',
        'type': 'fill',
        'source': 'mbtiles',
        'paint': {
          'fill-color': '#88AAFF',
          'fill-opacity': 0.3,
        }
      },
      {
        'id': 'default_line',
        'type': 'line',
        'source': 'mbtiles',
        'paint': {
          'line-color': '#4466CC',
          'line-width': 1.5,
        }
      },
    ];
  }
}

class MbTilesVectorTileProvider extends VectorTileProvider {
  final MbTiles mbtiles;
  final int _maximumZoom;
  final int _minimumZoom;

  MbTilesVectorTileProvider({
    required this.mbtiles,
    int maxZoom = 14,
    int minZoom = 0,
  })  : _maximumZoom = maxZoom,
        _minimumZoom = minZoom;

  @override
  int get maximumZoom => _maximumZoom;

  @override
  int get minimumZoom => _minimumZoom;

  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;

  @override
  Future<Uint8List> provide(TileIdentity tile) async {
    // MBTiles uses TMS coordinate scheme where Y is flipped
    // Convert from XYZ (slippy map) to TMS: tms_y = (2^z - 1) - xyz_y
    final tmsY = (1 << tile.z) - 1 - tile.y;
    
    final data = mbtiles.getTile(z: tile.z, x: tile.x, y: tmsY);
    if (data == null) {
      return Uint8List(0);
    }
    return data;
  }
}

class MBTilesRasterTileProvider extends TileProvider {
  final MbTiles mbtiles;
  static const AssetImage assetImage = AssetImage("assets/images/512.png");

  MBTilesRasterTileProvider(this.mbtiles);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    // MBTiles uses TMS coordinate scheme where Y is flipped
    final tmsY = (1 << coordinates.z) - 1 - coordinates.y;
    
    final data = mbtiles.getTile(
      z: coordinates.z,
      x: coordinates.x,
      y: tmsY,
    );

    if (data == null) {
      return assetImage;
    }

    return MemoryImage(data);
  }
}

class _AirspaceLabelOverlay extends StatefulWidget {
  final MbTiles mbtiles;
  final int maxTileZoom;
  final String? airportDbPath;

  const _AirspaceLabelOverlay({required this.mbtiles, required this.maxTileZoom, this.airportDbPath});

  @override
  State<_AirspaceLabelOverlay> createState() => _AirspaceLabelOverlayState();
}

class _AirspaceLabelOverlayState extends State<_AirspaceLabelOverlay> {
  late AirspaceLabelSource _source = AirspaceLabelSource(widget.mbtiles);
  List<ChartAirport> _airports = const [];
  double _south = 0;
  double _north = 0;
  double _west = 0;
  double _east = 0;
  bool _airportsReady = false;
  bool _loadingAirports = false;

  @override
  void didUpdateWidget(covariant _AirspaceLabelOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mbtiles != widget.mbtiles) {
      _source = AirspaceLabelSource(widget.mbtiles);
    }
    if (oldWidget.airportDbPath != widget.airportDbPath) {
      _airports = const [];
      _airportsReady = false;
      _south = _north = _west = _east = 0;
    }
  }

  void _loadAirports(double south, double north, double west, double east) {
    final path = widget.airportDbPath;
    if (path == null || path.isEmpty || _loadingAirports) {
      return;
    }
    if (_airportsReady && south >= _south && north <= _north && west >= _west && east <= _east) {
      return;
    }
    final latSpan = (north - south) * 0.5;
    final lonSpan = (east - west) * 0.5;
    final padLat = latSpan < 0.4 ? 0.4 : latSpan;
    final padLon = lonSpan < 0.4 ? 0.4 : lonSpan;
    final querySouth = south - padLat;
    final queryNorth = north + padLat;
    final queryWest = west - padLon;
    final queryEast = east + padLon;
    _loadingAirports = true;
    loadChartAirports(path, south: querySouth, north: queryNorth, west: queryWest, east: queryEast).then((airports) {
      if (!mounted) {
        return;
      }
      setState(() {
        _airports = airports;
        _airportsReady = true;
        _south = querySouth;
        _north = queryNorth;
        _west = queryWest;
        _east = queryEast;
        _loadingAirports = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final bounds = camera.visibleBounds;
    final tileZoom = camera.zoom.floor().clamp(0, widget.maxTileZoom);
    final detail = tileZoom >= airspaceDetailZoom;
    if (detail) {
      _loadAirports(bounds.south, bounds.north, bounds.west, bounds.east);
    }
    final labels = _source.labels(
      north: bounds.north,
      south: bounds.south,
      west: bounds.west,
      east: bounds.east,
      centerLat: camera.center.latitude,
      centerLon: camera.center.longitude,
      tileZoom: tileZoom,
      airports: detail ? _airports : const [],
      placeNamesAtAirports: detail && _airports.isNotEmpty,
    );
    final markers = <Marker>[];
    final placed = <Offset>[];
    for (final label in labels) {
      final screen = camera.latLngToScreenOffset(label.point);
      var slot = 0;
      for (; slot < 4; slot++) {
        final shifted = screen.translate(0, slot * 36);
        final blocked = placed.any((other) => (other.dx - shifted.dx).abs() < 80 && (other.dy - shifted.dy).abs() < 34);
        if (!blocked) {
          break;
        }
      }
      placed.add(screen.translate(0, slot * 36));
      final lines = label.text.split('\n');
      final height = lines.length > 1 ? 40.0 : 22.0;
      markers.add(Marker(
        key: ValueKey('${label.kind}:${label.text}@${label.point.latitude.toStringAsFixed(2)},${label.point.longitude.toStringAsFixed(2)}'),
        point: label.point,
        width: 128,
        height: height,
        alignment: Marker.computePixelAlignment(
          width: 128,
          height: height,
          left: 64,
          top: height / 2 - slot * 36,
        ),
        rotate: true,
        child: Text(
          label.text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: label.kind == 'B' ? 12 : label.kind == 'C' ? 11 : 10,
            fontWeight: FontWeight.w500,
            height: 1.15,
            shadows: _labelHalo(_labelHaloColor(label.kind)),
          ),
        ),
      ));
    }
    return MarkerLayer(markers: markers);
  }
}

Color _labelHaloColor(String kind) {
  switch (kind) {
    case 'B':
      return const Color(0xFF0000FF);
    case 'C':
      return const Color(0xFFFF00FF);
    case 'D':
      return const Color(0xFF0088FF);
    case 'MOA':
      return const Color(0xFF996633);
    case 'RESTRICTED':
      return const Color(0xFF0066FF);
    case 'WARNING':
      return const Color(0xFF0088FF);
    case 'ALERT':
      return const Color(0xFFFF8800);
    case 'PROHIBITED':
      return const Color(0xFFFF0000);
    case 'NSA':
      return const Color(0xFF228B22);
    default:
      return const Color(0xFF222222);
  }
}

List<Shadow> _labelHalo(Color color) {
  const shift = 0.7;
  return [
    for (final offset in const [
      Offset(-shift, -shift),
      Offset(-shift, shift),
      Offset(shift, -shift),
      Offset(shift, shift),
    ])
      Shadow(color: color, offset: offset),
    Shadow(color: color, blurRadius: 1.2),
  ];
}
