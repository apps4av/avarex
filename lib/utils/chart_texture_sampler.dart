import 'dart:collection';
import 'dart:typed_data';

import 'package:avaremp/chart/chart.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/epsg900913.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';
import 'package:universal_io/universal_io.dart';

/// Samples chart tile colors so terrain meshes can be textured with chart data.
class ChartTextureSampler {
  static final LinkedHashMap<String, img.Image> _cache =
      LinkedHashMap<String, img.Image>();
  static const int _cacheSize = 18;

  static Future<Color?> getColor(LatLng point, String chartType) async {
    final String chartIndex = ChartCategory.chartTypeToIndex(chartType);
    if (chartIndex.isEmpty) {
      return null;
    }

    final int zoom = ChartCategory.chartTypeToZoom(chartType);
    final Epsg900913 projection =
        Epsg900913.fromLatLon(point.latitude, point.longitude, zoom.toDouble());

    final int tileX = projection.getTilex();
    final int tileY = projection.getTiley();
    final int pixelX = _clampPixel(Epsg900913.getOffsetX(
      projection.getLonUpperLeft(),
      point.longitude,
      zoom.toDouble(),
    ));
    final int pixelY = _clampPixel(Epsg900913.getOffsetY(
      projection.getLatUpperLeft(),
      point.latitude,
      zoom.toDouble(),
    ));

    final String tilePath =
        "${Storage().dataDir}/tiles/"
        "$chartIndex/"
        "$zoom/"
        "$tileX/$tileY."
        "${ChartCategory.chartTypeToExtension(chartType)}";

    final img.Image? decodedImage = await _loadTile(tilePath);
    if (decodedImage == null) {
      return null;
    }

    try {
      final img.Pixel pixel = decodedImage.getPixel(pixelX, pixelY);
      final int alpha = pixel.a.toInt();
      if (alpha == 0) {
        return null;
      }
      return Color.fromARGB(
        255,
        pixel.r.toInt(),
        pixel.g.toInt(),
        pixel.b.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  static void clear() {
    _cache.clear();
  }

  static Future<img.Image?> _loadTile(String tilePath) async {
    img.Image? decodedImage;

    if (_cache.containsKey(tilePath)) {
      decodedImage = _cache.remove(tilePath);
      if (decodedImage != null) {
        _cache[tilePath] = decodedImage;
      }
      return decodedImage;
    }

    final File tile = File(tilePath);
    if (!tile.existsSync()) {
      return null;
    }

    final Uint8List bytes = await tile.readAsBytes();
    decodedImage = img.decodeImage(bytes);
    if (decodedImage == null) {
      return null;
    }

    if (_cache.length >= _cacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[tilePath] = decodedImage;
    return decodedImage;
  }

  static int _clampPixel(double value) {
    if (!value.isFinite || value.isNaN) {
      return 0;
    }
    if (value < 0) {
      return 0;
    }
    if (value > 511) {
      return 511;
    }
    return value.round();
  }
}
