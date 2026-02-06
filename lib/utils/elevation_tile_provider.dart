import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:avaremp/utils/epsg900913.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

// tile provider that evicts tiles based on altitude changes, and colors the loaded tiles based on altitude
class ElevationTileProvider extends TileProvider {

  final Map<String, ElevationImageProvider> _cache = {};
  int _lastCalled = DateTime.now().millisecondsSinceEpoch;
  double _lastAltitude = 0.0;
  static const AssetImage assetImage = AssetImage("assets/images/512.png");

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

    for(var value in _cache.values) {
      value.evict();
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

    // find x, y, z of tile from dlUrl, use regexp
    RegExp regExp = RegExp(r'tiles\/\d/(\d+)/(\d+)/(\d+)\..*$');
    Match? match = regExp.firstMatch(dlUrl);
    if(match == null || match.groupCount != 3) {
      return assetImage;
    }
    int z = int.parse(match.group(1)!);
    int x = int.parse(match.group(2)!);
    int y = int.parse(match.group(3)!);

    Epsg900913 proj = Epsg900913.fromLatLon(
        Storage().position.latitude,
        Storage().position.longitude, z.toDouble());

    int currentTileX = proj.getTilex();
    int currentTileY = proj.getTiley();

    // return empty image for tiles that are +-3 from current tile
    if((x < (currentTileX - 3)) || (x > (currentTileX + 3)) ||
       (y < (currentTileY - 3)) || (y > (currentTileY + 3))) {
      return assetImage;
    }

    File f = File(dlUrl);
    if(f.existsSync()) {
      ElevationImageProvider p = ElevationImageProvider(f);
      // add for eviction, not for reuse
      _cache[dlUrl] = p;
      return p;
    }

    return assetImage;
  }
}

class ElevationImageProvider extends ImageProvider<ElevationImageProvider> {
  ElevationImageProvider(this.file);

  final File file;

  static const double altitudeFtElevationPerPixelSlopeBase = 80.4711845056;
  static const double altitudeFtElevationPerPixelIntercept = -364.431597044586;

  static const int _transparentClass = 0;
  static const int _yellowClass = 1;
  static const int _redClass = 2;

  @override
  Future<ElevationImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<ElevationImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(ElevationImageProvider key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(_loadAsync(key));
  }

  Future<ImageInfo> _loadAsync(ElevationImageProvider key) async {
    final Uint8List encodedBytes = await file.readAsBytes();
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(encodedBytes);
    final ui.Codec codec = await ui.instantiateImageCodecFromBuffer(buffer);
    final ui.FrameInfo frame = await codec.getNextFrame();
    codec.dispose();

    final ui.Image image = frame.image;
    final ByteData? pixelData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (pixelData == null) {
      return ImageInfo(image: image, scale: 1.0);
    }

    final Uint8List pixels = pixelData.buffer.asUint8List(
      pixelData.offsetInBytes,
      pixelData.lengthInBytes,
    );
    final double currentAltitude = GeoCalculations.convertAltitude(Storage().position.altitude);
    final List<int> classByRed = _buildClassByRed(currentAltitude);
    _applyElevationColors(pixels, classByRed);

    final ui.Image coloredImage = await _imageFromPixels(
      pixels,
      image.width,
      image.height,
    );
    return ImageInfo(image: coloredImage, scale: 1.0);
  }

  static List<int> _buildClassByRed(double currentAltitude) {
    final List<int> classes = List<int>.filled(256, _transparentClass);
    final double base = currentAltitude - altitudeFtElevationPerPixelIntercept;
    final double threshold1000 = (base - 1000) / altitudeFtElevationPerPixelSlopeBase;
    final double threshold500 = (base - 500) / altitudeFtElevationPerPixelSlopeBase;
    for (int red = 0; red < 256; red++) {
      if (red < threshold1000) {
        classes[red] = _transparentClass;
      } else if (red < threshold500) {
        classes[red] = _yellowClass;
      } else {
        classes[red] = _redClass;
      }
    }
    return classes;
  }

  static void _applyElevationColors(Uint8List pixels, List<int> classByRed) {
    for (int i = 0; i < pixels.length; i += 4) {
      final int red = pixels[i];
      final int classification = classByRed[red];
      if (classification == _transparentClass) {
        pixels[i + 2] = 0x0; // blue
        pixels[i + 3] = 0x0; // alpha
      } else if (classification == _yellowClass) {
        pixels[i] = 0xFF;
        pixels[i + 1] = 0xFF;
        pixels[i + 2] = 0x0;
        pixels[i + 3] = 0xFF;
      } else {
        pixels[i] = 0xFF;
        pixels[i + 1] = 0x0;
        pixels[i + 2] = 0x0;
        pixels[i + 3] = 0xFF;
      }
    }
  }

  static Future<ui.Image> _imageFromPixels(
    Uint8List pixels,
    int width,
    int height,
  ) {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (ui.Image image) => completer.complete(image),
      rowBytes: width * 4,
    );
    return completer.future;
  }

  @override
  bool operator ==(Object other) {
    return other is ElevationImageProvider && other.file.path == file.path;
  }

  @override
  int get hashCode => file.path.hashCode;
}