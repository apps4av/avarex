import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:mbtiles/mbtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;
import 'package:latlong2/latlong.dart';
import 'dart:io';

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

  Widget? buildVectorTileLayer({double opacity = 1.0}) {
    if (_mbtiles == null || !_isVector) {
      return null;
    }

    final provider = MbTilesVectorTileProvider(
      mbtiles: _mbtiles!,
      maxZoom: _metadata?.maxZoom?.toInt() ?? 14,
      minZoom: _metadata?.minZoom?.toInt() ?? 0,
    );

    return Opacity(
      opacity: opacity,
      child: VectorTileLayer(
        tileProviders: TileProviders({
          'mbtiles': provider,
        }),
        theme: _buildTheme(_layerNames),
        // Allow overzooming: render at map zoom levels higher than tile data
        // The provider's maximumZoom (10) limits tile fetching,
        // but VectorTileLayer's maximumZoom allows rendering at higher map zooms
        maximumZoom: 20,
      ),
    );
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

  static vtr.Theme _buildTheme(List<String> layerNames) {
    final List<Map<String, dynamic>> layers = [];

    for (final layerName in layerNames) {
      if (layerName.toLowerCase().contains('airspace')) {
        layers.addAll(_buildAirspaceThemeLayers(layerName));
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

  static List<Map<String, dynamic>> _buildAirspaceThemeLayers(String layerName) {
    return [
      {
        'id': '${layerName}_class_b_fill',
        'type': 'fill',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'CLASS', 'B'],
        'paint': {
          'fill-color': '#0000FF',
          'fill-opacity': 0.2,
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
          'line-width': 2,
        }
      },
      {
        'id': '${layerName}_class_c_fill',
        'type': 'fill',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'CLASS', 'C'],
        'paint': {
          'fill-color': '#FF00FF',
          'fill-opacity': 0.15,
        }
      },
      {
        'id': '${layerName}_class_c_line',
        'type': 'line',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'CLASS', 'C'],
        'paint': {
          'line-color': '#FF00FF',
          'line-width': 2,
        }
      },
      {
        'id': '${layerName}_class_d_fill',
        'type': 'fill',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'CLASS', 'D'],
        'paint': {
          'fill-color': '#0088FF',
          'fill-opacity': 0.1,
        }
      },
      {
        'id': '${layerName}_class_d_line',
        'type': 'line',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'CLASS', 'D'],
        'paint': {
          'line-color': '#0088FF',
          'line-width': 1.5,
          'line-dasharray': [4, 2],
        }
      },
      {
        'id': '${layerName}_class_e_fill',
        'type': 'fill',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'CLASS', 'E'],
        'paint': {
          'fill-color': '#FF00FF',
          'fill-opacity': 0.05,
        }
      },
      {
        'id': '${layerName}_class_e_line',
        'type': 'line',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'CLASS', 'E'],
        'paint': {
          'line-color': '#FF00FF',
          'line-width': 1,
          'line-dasharray': [2, 2],
        }
      },
      {
        'id': '${layerName}_labels',
        'type': 'symbol',
        'source': 'mbtiles',
        'source-layer': layerName,
        'layout': {
          'text-field': '{NAME}',
          'text-size': 10,
        },
        'paint': {
          'text-color': '#333333',
        }
      },
    ];
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
      // Return empty tile for missing data (overlays don't cover entire world)
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
