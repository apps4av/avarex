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

    final minZ = _metadata?.minZoom?.toInt() ?? 0;
    final maxZ = _metadata?.maxZoom?.toInt() ?? 14;

    final provider = MbTilesVectorTileProvider(
      mbtiles: _mbtiles!,
      maxZoom: maxZ,
      minZoom: minZ,
    );

    return Opacity(
      opacity: opacity,
      child: VectorTileLayer(
        key: const ValueKey('mbtiles_vector_layer'),
        tileProviders: TileProviders({
          'mbtiles': provider,
        }),
        theme: _buildTheme(_layerNames),
        layerMode: VectorTileLayerMode.vector,
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
      if (layerName == 'class_airspace') {
        layers.addAll(_buildClassAirspaceThemeLayers(layerName));
      } else if (layerName == 'sua_airspace') {
        layers.addAll(_buildSuaAirspaceThemeLayers(layerName));
      } else if (layerName == 'class_airspace_labels') {
        layers.addAll(_buildClassAirspaceLabelLayers(layerName));
      } else if (layerName == 'sua_airspace_labels') {
        layers.addAll(_buildSuaAirspaceLabelLayers(layerName));
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
          'line-width': 3,
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
          'line-width': 3,
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
          'line-width': 2.5,
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
          'line-width': 0.5,
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
        'filter': ['==', 'TYPE', 'MOA'],
        'paint': {
          'fill-color': '#996633',
          'fill-opacity': 0.1,
        }
      },
      {
        'id': '${layerName}_moa_line',
        'type': 'line',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'TYPE', 'MOA'],
        'paint': {
          'line-color': '#996633',
          'line-width': 1.5,
        }
      },
      // Restricted Area - Blue hatched
      {
        'id': '${layerName}_restricted_fill',
        'type': 'fill',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'TYPE', 'RESTRICTED'],
        'paint': {
          'fill-color': '#0066FF',
          'fill-opacity': 0.15,
        }
      },
      {
        'id': '${layerName}_restricted_line',
        'type': 'line',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'TYPE', 'RESTRICTED'],
        'paint': {
          'line-color': '#0066FF',
          'line-width': 2,
        }
      },
      // Warning Area - Blue hatched (offshore)
      {
        'id': '${layerName}_warning_fill',
        'type': 'fill',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'TYPE', 'WARNING'],
        'paint': {
          'fill-color': '#0088FF',
          'fill-opacity': 0.1,
        }
      },
      {
        'id': '${layerName}_warning_line',
        'type': 'line',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'TYPE', 'WARNING'],
        'paint': {
          'line-color': '#0088FF',
          'line-width': 2,
        }
      },
      // Alert Area - Orange
      {
        'id': '${layerName}_alert_fill',
        'type': 'fill',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'TYPE', 'ALERT'],
        'paint': {
          'fill-color': '#FF8800',
          'fill-opacity': 0.1,
        }
      },
      {
        'id': '${layerName}_alert_line',
        'type': 'line',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'TYPE', 'ALERT'],
        'paint': {
          'line-color': '#FF8800',
          'line-width': 1.5,
        }
      },
      // Prohibited Area - Red (no-fly zone)
      {
        'id': '${layerName}_prohibited_fill',
        'type': 'fill',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'TYPE', 'PROHIBITED'],
        'paint': {
          'fill-color': '#FF0000',
          'fill-opacity': 0.25,
        }
      },
      {
        'id': '${layerName}_prohibited_line',
        'type': 'line',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'TYPE', 'PROHIBITED'],
        'paint': {
          'line-color': '#FF0000',
          'line-width': 2,
        }
      },
      // NSA (National Security Area) - Green
      {
        'id': '${layerName}_nsa_fill',
        'type': 'fill',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'TYPE', 'NSA'],
        'paint': {
          'fill-color': '#228B22',
          'fill-opacity': 0.1,
        }
      },
      {
        'id': '${layerName}_nsa_line',
        'type': 'line',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'TYPE', 'NSA'],
        'paint': {
          'line-color': '#228B22',
          'line-width': 1.5,
        }
      },
    ];
  }

  static List<Map<String, dynamic>> _buildClassAirspaceLabelLayers(String layerName) {
    return [
      {
        'id': '${layerName}_class_b',
        'type': 'symbol',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'CLASS', 'B'],
        'layout': {
          'text-field': '{NAME}',
          'text-size': 12,
          'text-font': ['Roboto Regular'],
        },
        'paint': {
          'text-color': '#FFFFFF',
          'text-halo-color': '#0000FF',
          'text-halo-width': 2,
        }
      },
      {
        'id': '${layerName}_class_c',
        'type': 'symbol',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'CLASS', 'C'],
        'layout': {
          'text-field': '{NAME}',
          'text-size': 11,
          'text-font': ['Roboto Regular'],
        },
        'paint': {
          'text-color': '#FFFFFF',
          'text-halo-color': '#FF00FF',
          'text-halo-width': 2,
        }
      },
      {
        'id': '${layerName}_class_d',
        'type': 'symbol',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'CLASS', 'D'],
        'layout': {
          'text-field': '{NAME}',
          'text-size': 10,
          'text-font': ['Roboto Regular'],
        },
        'paint': {
          'text-color': '#FFFFFF',
          'text-halo-color': '#0088FF',
          'text-halo-width': 2,
        }
      },
    ];
  }

  static List<Map<String, dynamic>> _buildSuaAirspaceLabelLayers(String layerName) {
    return [
      {
        'id': '${layerName}_moa',
        'type': 'symbol',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'TYPE', 'MOA'],
        'layout': {
          'text-field': '{NAME}',
          'text-size': 10,
          'text-font': ['Roboto Regular'],
        },
        'paint': {
          'text-color': '#FFFFFF',
          'text-halo-color': '#996633',
          'text-halo-width': 2,
        }
      },
      {
        'id': '${layerName}_restricted',
        'type': 'symbol',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'TYPE', 'RESTRICTED'],
        'layout': {
          'text-field': '{NAME}',
          'text-size': 10,
          'text-font': ['Roboto Regular'],
        },
        'paint': {
          'text-color': '#FFFFFF',
          'text-halo-color': '#0066FF',
          'text-halo-width': 2,
        }
      },
      {
        'id': '${layerName}_warning',
        'type': 'symbol',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'TYPE', 'WARNING'],
        'layout': {
          'text-field': '{NAME}',
          'text-size': 10,
          'text-font': ['Roboto Regular'],
        },
        'paint': {
          'text-color': '#FFFFFF',
          'text-halo-color': '#0088FF',
          'text-halo-width': 2,
        }
      },
      {
        'id': '${layerName}_alert',
        'type': 'symbol',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'TYPE', 'ALERT'],
        'layout': {
          'text-field': '{NAME}',
          'text-size': 10,
          'text-font': ['Roboto Regular'],
        },
        'paint': {
          'text-color': '#FFFFFF',
          'text-halo-color': '#FF8800',
          'text-halo-width': 2,
        }
      },
      {
        'id': '${layerName}_prohibited',
        'type': 'symbol',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'TYPE', 'PROHIBITED'],
        'layout': {
          'text-field': '{NAME}',
          'text-size': 11,
          'text-font': ['Roboto Regular'],
        },
        'paint': {
          'text-color': '#FFFFFF',
          'text-halo-color': '#FF0000',
          'text-halo-width': 2,
        }
      },
      {
        'id': '${layerName}_nsa',
        'type': 'symbol',
        'source': 'mbtiles',
        'source-layer': layerName,
        'filter': ['==', 'TYPE', 'NSA'],
        'layout': {
          'text-field': '{NAME}',
          'text-size': 10,
          'text-font': ['Roboto Regular'],
        },
        'paint': {
          'text-color': '#FFFFFF',
          'text-halo-color': '#228B22',
          'text-halo-width': 2,
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
