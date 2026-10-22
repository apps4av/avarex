import 'dart:collection';
import 'package:universal_io/universal_io.dart';

import 'package:avaremp/chart/chart.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/elevation_tile_provider.dart';
import 'package:avaremp/utils/epsg900913.dart';
import 'package:latlong2/latlong.dart';
import 'package:image/image.dart' as img;

class ElevationCache {

  static final LinkedHashMap<String, img.Image> _cache = LinkedHashMap();
  static final int _cacheSize = 25;

  static String _tilePath(int zoom, int x, int y) =>
      "${Storage().dataDir}/tiles/"
      "${ChartCategory.chartTypeToIndex(ChartCategory.elevation)}/"
      "$zoom/$x/$y."
      "${ChartCategory.chartTypeToExtension(ChartCategory.elevation)}";

  static Future<img.Image?> _loadTile(String tileName) async {
    if (_cache.containsKey(tileName)) {
      final img.Image hit = _cache.remove(tileName)!;
      _cache[tileName] = hit;
      return hit;
    }
    final File tile = File(tileName);
    if (!tile.existsSync()) return null;
    final img.Image? decoded = img.decodeImage(await tile.readAsBytes());
    if (decoded != null) {
      while (_cache.length >= _cacheSize) {
        _cache.remove(_cache.keys.first);
      }
      _cache[tileName] = decoded;
    }
    return decoded;
  }

  static double? _sample(img.Image decoded, double pixelX, double pixelY) {
    try {
      final img.Pixel p = decoded.getPixel(pixelX.toInt(), pixelY.toInt());
      if (p.a as int == 0 && p.r as int == 255) {
        return null;
      }
      return (p.r as int) *
          ElevationImageProvider.altitudeFtElevationPerPixelSlopeBase +
          ElevationImageProvider.altitudeFtElevationPerPixelIntercept;
    } catch (_) {
      return null;
    }
  }

  static double? _elevAt(LatLng position, int zoom) {
    final double zd = zoom.toDouble();
    final Epsg900913 proj =
        Epsg900913.fromLatLon(position.latitude, position.longitude, zd);
    final img.Image? decoded =
        _cache[_tilePath(zoom, proj.getTilex(), proj.getTiley())];
    if (decoded == null) return null;
    final double pixelX =
        Epsg900913.getOffsetX(proj.getLonUpperLeft(), position.longitude, zd);
    final double pixelY =
        Epsg900913.getOffsetY(proj.getLatUpperLeft(), position.latitude, zd);
    return _sample(decoded, pixelX, pixelY);
  }

  static Future<double?> getElevation(LatLng position) async {
    final int zoom = ChartCategory.chartTypeToZoom(ChartCategory.elevation);
    final Epsg900913 proj = Epsg900913.fromLatLon(
        position.latitude, position.longitude, zoom.toDouble());
    await _loadTile(_tilePath(zoom, proj.getTilex(), proj.getTiley()));
    return _elevAt(position, zoom);
  }

  /// Load each unique tile once, then sample every point from memory.
  /// The shared cache keeps only [_cacheSize] tiles and drops the oldest.
  /// This route can cross more tiles than that, so the images stay in a local
  /// map until every point has been read. Otherwise the start of the route
  /// is sampled after its tiles have already been dropped.
  static Future<List<double?>> getElevationOfPoints(List<LatLng> position) async {
    if (position.isEmpty) return [];
    final int zoom = ChartCategory.chartTypeToZoom(ChartCategory.elevation);
    final double zd = zoom.toDouble();
    final List<Epsg900913> projections = [
      for (final LatLng p in position)
        Epsg900913.fromLatLon(p.latitude, p.longitude, zd),
    ];
    final Map<String, img.Image?> tiles = {};
    for (final Epsg900913 proj in projections) {
      final String name = _tilePath(zoom, proj.getTilex(), proj.getTiley());
      if (tiles.containsKey(name)) {
        continue;
      }
      tiles[name] = await _loadTile(name);
    }
    return [
      for (int i = 0; i < position.length; i++)
        _sampleHeld(tiles, projections[i], position[i], zoom),
    ];
  }

  static double? _sampleHeld(Map<String, img.Image?> tiles, Epsg900913 proj,
      LatLng position, int zoom) {
    final img.Image? decoded =
        tiles[_tilePath(zoom, proj.getTilex(), proj.getTiley())];
    if (decoded == null) return null;
    final double zd = zoom.toDouble();
    final double pixelX =
        Epsg900913.getOffsetX(proj.getLonUpperLeft(), position.longitude, zd);
    final double pixelY =
        Epsg900913.getOffsetY(proj.getLatUpperLeft(), position.latitude, zd);
    return _sample(decoded, pixelX, pixelY);
  }
}