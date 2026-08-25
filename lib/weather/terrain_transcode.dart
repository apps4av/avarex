// Pure terrain-tile transcoding and enumeration.
//
// AvareX renders terrain from elevation tiles stored at
//   {dataDir}/tiles/6/{z}/{x}/{y}.png
// as 512x512 8-bit gray+alpha PNGs where
//   elevationFt = gray * 80.4711845056 - 364.431597044586
// (see ElevationImageProvider / ElevationCache). The tile grid uses standard
// slippy X but a TMS (flipped) Y: yTile = 2^z - 1 - yXyz. Alpha 0 marks
// no-data (ocean); gray 0 there.
//
// Outside the US, these tiles are not distributed. This transcoder builds them
// on-device from open, public-domain AWS Terrain Tiles ("terrarium" RGB PNG,
// 256x256, standard slippy XYZ) where
//   elevationMeters = R*256 + G + B/256 - 32768.
//
// Everything here is PURE and unit-tested (no I/O): the network fetch and file
// writing live in terrain_download_manager.dart.
//
// Terrain data © AWS Terrain Tiles / Mapzen contributors (public domain / CC0
// and permissively licensed sources). Advisory only.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

// AvareX elevation encoding constants (must match ElevationImageProvider).
const double kElevSlope = 80.4711845056;
const double kElevIntercept = -364.431597044586;

// AvareX elevation pyramid zoom range and native (max) zoom.
const int kTerrainMinZoom = 1;
const int kTerrainMaxZoom = 10;

// A single tile address in AvareX's grid (slippy X, TMS Y).
class TerrainTile {
  final int z;
  final int x;
  final int yTms; // AvareX/TMS y as stored on disk
  const TerrainTile(this.z, this.x, this.yTms);

  // The corresponding slippy/XYZ y used by terrarium.
  int get yXyz => (1 << z) - 1 - yTms;

  @override
  bool operator ==(Object other) =>
      other is TerrainTile && other.z == z && other.x == x && other.yTms == yTms;

  @override
  int get hashCode => Object.hash(z, x, yTms);

  @override
  String toString() => '$z/$x/$yTms';
}

class TerrainTranscode {
  TerrainTranscode._();

  // Terrarium (AWS Terrain Tiles) URL for a slippy XYZ tile.
  static Uri terrariumUrl(int z, int x, int yXyz) => Uri.https(
      's3.amazonaws.com', '/elevation-tiles-prod/terrarium/$z/$x/$yXyz.png');

  // Encodes an elevation in feet to an AvareX gray byte (0..255), clamped.
  static int encodeGray(double elevationFt) {
    final g = ((elevationFt - kElevIntercept) / kElevSlope).round();
    if (g < 0) return 0;
    if (g > 255) return 255;
    return g;
  }

  // Decodes an AvareX gray byte back to feet (inverse of encodeGray, ignoring
  // clamping/quantization). Used by tests to assert round-trip fidelity.
  static double decodeGray(int gray) => gray * kElevSlope + kElevIntercept;

  // Slippy X tile index for a longitude at zoom z.
  static int lonToTileX(double lon, int z) {
    final n = 1 << z;
    var x = ((lon + 180.0) / 360.0 * n).floor();
    if (x < 0) x = 0;
    if (x > n - 1) x = n - 1;
    return x;
  }

  // Slippy (XYZ) Y tile index for a latitude at zoom z.
  static int latToTileYXyz(double lat, int z) {
    final n = 1 << z;
    final r = math.log(math.tan(_rad(lat)) + 1 / math.cos(_rad(lat)));
    var y = ((1 - r / math.pi) / 2 * n).floor();
    if (y < 0) y = 0;
    if (y > n - 1) y = n - 1;
    return y;
  }

  // Enumerates every AvareX tile (all zooms kTerrainMinZoom..kTerrainMaxZoom)
  // covering a lat/lon bounding box.
  static List<TerrainTile> tilesForBounds(
    double minLat,
    double maxLat,
    double minLon,
    double maxLon, {
    int minZoom = kTerrainMinZoom,
    int maxZoom = kTerrainMaxZoom,
  }) {
    final tiles = <TerrainTile>[];
    for (var z = minZoom; z <= maxZoom; z++) {
      final x0 = lonToTileX(minLon, z);
      final x1 = lonToTileX(maxLon, z);
      // North latitude -> smaller slippy y.
      final yTop = latToTileYXyz(maxLat, z);
      final yBottom = latToTileYXyz(minLat, z);
      for (var x = math.min(x0, x1); x <= math.max(x0, x1); x++) {
        for (var yx = math.min(yTop, yBottom); yx <= math.max(yTop, yBottom); yx++) {
          tiles.add(TerrainTile(z, x, (1 << z) - 1 - yx));
        }
      }
    }
    return tiles;
  }

  // Counts tiles for a bounding box without allocating them all.
  static int countTilesForBounds(
    double minLat,
    double maxLat,
    double minLon,
    double maxLon, {
    int minZoom = kTerrainMinZoom,
    int maxZoom = kTerrainMaxZoom,
  }) {
    var total = 0;
    for (var z = minZoom; z <= maxZoom; z++) {
      final x0 = lonToTileX(minLon, z);
      final x1 = lonToTileX(maxLon, z);
      final yTop = latToTileYXyz(maxLat, z);
      final yBottom = latToTileYXyz(minLat, z);
      final nx = (x1 - x0).abs() + 1;
      final ny = (yBottom - yTop).abs() + 1;
      total += nx * ny;
    }
    return total;
  }

  // Transcodes terrarium PNG bytes into AvareX elevation-tile PNG bytes.
  // Returns null if the input cannot be decoded. The output is a 512x512 PNG
  // with a gray channel (elevation) and an alpha channel (255 = data).
  static List<int>? transcodeTerrarium(List<int> terrariumPng) {
    final Uint8List bytes = terrariumPng is Uint8List
        ? terrariumPng
        : Uint8List.fromList(terrariumPng);
    final src = img.decodePng(bytes);
    if (src == null) return null;

    // Build a 512x512 grayscale-with-alpha output by sampling the source
    // (typically 256x256) with nearest-neighbour scaling.
    const int outSize = 512;
    final out = img.Image(width: outSize, height: outSize, numChannels: 2);
    final double sx = src.width / outSize;
    final double sy = src.height / outSize;

    for (var oy = 0; oy < outSize; oy++) {
      final int syi = (oy * sy).floor().clamp(0, src.height - 1);
      for (var ox = 0; ox < outSize; ox++) {
        final int sxi = (ox * sx).floor().clamp(0, src.width - 1);
        final p = src.getPixel(sxi, syi);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();
        final double meters = r * 256.0 + g + b / 256.0 - 32768.0;
        final double feet = meters * 3.28084;
        // Terrarium has no alpha/no-data; treat deep-ocean sentinel as no-data
        // so the app renders nothing there (matches US tiles' ocean handling).
        final bool noData = meters <= -11000; // below the deepest ocean trench
        final int gray = noData ? 0 : encodeGray(feet);
        final int alpha = noData ? 0 : 255;
        out.setPixelRgba(ox, oy, gray, gray, gray, alpha);
      }
    }
    // Encode as gray+alpha PNG to match the US tiles' LA format.
    return img.encodePng(out);
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
}
