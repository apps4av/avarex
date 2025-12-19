import 'dart:io';
import 'dart:ui' as ui;
import 'package:avaremp/chart.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image/image.dart' as img;

// tile provider that evicts tiles based on altitude changes, and colors the loaded tiles based on altitude
class ElevationTileProvider extends TileProvider {

  final List<ImageProvider> _cache = [];
  int _lastCalled = DateTime.now().millisecondsSinceEpoch;
  double _lastAltitude = 0.0;

  // evict tiles when altitude changes significantly so color map can be updated
  bool evict() {

    if(_cache.isEmpty) {
      return false;
    }

    double currentAltitude = Storage().position.altitude;
    int now = DateTime.now().millisecondsSinceEpoch;
    // evict only when altitude has changed significantly, and 10 evicts have been called
    if(((_lastCalled + 10000) > now) ||
        ((currentAltitude - _lastAltitude).abs() < 30.0)) { // 100 feet
      return false;
    }

    for(var p in _cache) {
      p.evict();
    }

    _cache.clear();
    _lastCalled = DateTime.now().millisecondsSinceEpoch;
    _lastAltitude = currentAltitude;
    return true; // evicted
  }

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    // get rid of annoying tile name error problem by providing a transparent tile
    String url = getTileUrl(coordinates, options);
    // remove cache busting part
    String dlUrl = url.replaceAll(RegExp("\\?.*"), "");
    File f = File(dlUrl);
    if(f.existsSync()) {
      ImageProvider p = CustomImageProvider(FileImage(f));
      // add for eviction
      _cache.add(p);
      return p;
    }

    // get file to download message in tile missing
    String name = Chart.getChartRegion(coordinates.x, coordinates.y, coordinates.z);
    if(name.isEmpty) {
      return const AssetImage("assets/images/512.png");
    }
    return AssetImage("assets/images/dl_$name.png");
  }
}

class CustomImageProvider extends ImageProvider {
  final ImageProvider inner;

  CustomImageProvider(this.inner);

  double altitudeFtElevationPerPixelSlopeBase = 24.5276170372963;
  double altitudeFtElevationPerPixelIntercept = -364.431597044586;

  double elevationFromPixel(int px, {double heightConversion = 1.0}) {
    // px & 0xFF matches Java's (px & 0x000000FF)
    final int pixel = px & 0xFF;

    final double slope =
        altitudeFtElevationPerPixelSlopeBase * heightConversion;

    return pixel * slope + altitudeFtElevationPerPixelIntercept;
  }

  @override
  ImageStreamCompleter loadImage(Object key, ImageDecoderCallback decode) {
    return inner.loadImage(key,
            (ui.ImmutableBuffer buffer, {
      ui.TargetImageSizeCallback? getTargetSize}) async {
      var imageCodec = await ui.instantiateImageCodecFromBuffer(buffer);
      var frame = await imageCodec.getNextFrame();
      ui.Image image = frame.image;
      final ByteData? encodedBytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if(encodedBytes != null) {
        final encodedList = encodedBytes.buffer.asUint8List();
        img.Image? decodedImage = img.decodePng(encodedList);
        if(decodedImage != null) {
          // compare elevation and current altitude then color the tile
          double currentAltitudeMeters = Storage().position.altitude;
          for(int y = 0; y < decodedImage.height; y++) {
            for(int x = 0; x < decodedImage.width; x++) {
              // make transparent pixel white
              img.Pixel p = decodedImage.getPixel(x, y);
              double aglMeters = elevationFromPixel(p.r as int);
              double diff = currentAltitudeMeters - aglMeters;
              if(diff > 300) { // transparent above 1000 feet
                p.r = 0x0;
                p.g = 0x0;
                p.b = 0x0;
                p.a = 0x0;
              }
              else if(diff > 150) { // yellow between 500 and 1000 feet
                p.r = 0xFF;
                p.g = 0xFF;
                p.b = 0x0;
                p.a = 0xFF;
              }
              else { // red below 500 feet
                p.r = 0xFF;
                p.g = 0x0;
                p.b = 0x0;
                p.a = 0xFF;
              }
              decodedImage.setPixel(x, y, p);
            }
          }
          Uint8List reEncodedList = img.encodePng(decodedImage);
          return decode.call(
            await ui.ImmutableBuffer.fromUint8List(reEncodedList),
            getTargetSize: getTargetSize);
        }
      }

      return decode.call(buffer, getTargetSize: getTargetSize);
    });
  }

  @override
  Future<Object> obtainKey(ImageConfiguration configuration) {
    return inner.obtainKey(configuration);
  }
}