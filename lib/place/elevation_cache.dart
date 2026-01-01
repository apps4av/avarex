import 'dart:collection';
import 'package:universal_io/universal_io.dart';
import 'dart:typed_data';

import 'package:avaremp/chart/chart.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/elevation_tile_provider.dart';
import 'package:avaremp/utils/epsg900913.dart';
import 'package:latlong2/latlong.dart';
import 'package:image/image.dart' as img;

class ElevationCache {

  static final LinkedHashMap<String, img.Image> _cache = LinkedHashMap();
  static final int _cacheSize = 9;

  static Future<double?> getElevation(LatLng position) async {
    int zoom = ChartCategory.chartTypeToZoom(ChartCategory.elevation);
    // find elevation from tile
    Epsg900913 proj = Epsg900913.fromLatLon(position.latitude, position.longitude, zoom.toDouble());
    int x = proj.getTilex();
    int y = proj.getTiley();
    double pixelX = Epsg900913.getOffsetX(proj.getLonUpperLeft(), position.longitude, zoom.toDouble());
    double pixelY = Epsg900913.getOffsetY(proj.getLatUpperLeft(), position.latitude, zoom.toDouble());

    // cache elevation tile image at maximum zoom
    String tileName =
        "${Storage().dataDir}/tiles/"
        "${ChartCategory.chartTypeToIndex(ChartCategory.elevation)}/"
        "$zoom/"
        "$x/$y."
        "${ChartCategory.chartTypeToExtension(ChartCategory.elevation)}";

    img.Image? decodedImage;
    double? elevation;
    if(_cache.containsKey(tileName)) {
      // for LRU remove then add at the end
      decodedImage = _cache.remove(tileName);
      _cache[tileName] = decodedImage!;
    }
    else {
      File tile = File(tileName);
      if (!tile.existsSync()) {
        return null;
      }
      // elevation tile exists
      final Uint8List inputImg = await tile.readAsBytes();

      // 2. Use the 'image' package to decode the compressed image data
      // The decodeImage function automatically detects the format (JPEG, PNG, etc.)
      decodedImage = img.decodeImage(inputImg);
      if(decodedImage != null) {
        if(_cache.length > _cacheSize) {
          // limit cache size
          _cache.remove(_cache.keys.first);
        }
        _cache[tileName] = decodedImage;
      }
    }

    if(decodedImage != null) {
      // 3. Get the raw pixel data in RGB format
      // The getBytes method returns a single-depth Uint8List of all pixel values
      // (R, G, B, R, G, B, ...)
      try {
        img.Pixel p = decodedImage.getPixel(pixelX.toInt(), pixelY.toInt());
        if(p.a as int == 0 && p.r as int == 255) {
          return null; // alpha 0 means no data when 255, we run over into abyss
        }
        elevation = (p.r as int) *
            ElevationImageProvider.altitudeFtElevationPerPixelSlopeBase +
            ElevationImageProvider.altitudeFtElevationPerPixelIntercept;
      }
      catch(e) {
        elevation = null;
      }
    }
    return elevation;
  }

  static Future<List<double?>> getElevationOfPoints(List<LatLng> position) async {
    List<double?> elevations = [];
    for(LatLng pos in position) {
      double? elevation = await getElevation(pos);
      elevations.add(elevation);
    }
    return elevations;
  }
}