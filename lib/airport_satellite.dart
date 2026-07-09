import 'dart:math' as math;
import 'dart:typed_data';

import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as path;
import 'package:universal_io/io.dart';

/// Downloads and stores a Google Maps satellite picture for an airport.
///
/// The image is stitched from Google satellite map tiles (no API key needed),
/// georeferenced with an EXIF `UserComment` (same format the app uses for FAA
/// plates) and stored in the airport's plates folder as `APS-AERIAL VIEW.png`,
/// so it shows up with the rest of the airport plates and draws ownship like
/// any other plate.
class AirportSatellite {

  // stored as a plate so it appears in the plate list for the airport
  static const String plateName = "APS-AERIAL VIEW";

  static const int _zoom = 15;
  static const int _tileSize = 256;  // Google map tiles are 256x256
  static const int _imageSize = 1280; // output square in pixels

  /// Path where the satellite image is (or would be) stored for [airportId].
  static Future<String> getPath(String airportId) async {
    // plates are stored under the FAA name, not the ICAO id
    String faa = await MainDatabaseHelper.db.getFaaName(airportId);
    return path.join(Storage().dataDir, "plates", faa, "$plateName.png");
  }

  static Future<bool> exists(String airportId) async {
    if (kIsWeb) {
      return false;
    }
    String p = await getPath(airportId);
    return File(p).exists();
  }

  /// Stitches Google satellite tiles around [center], georeferences the result
  /// and writes it to disk.
  static Future<void> download(String airportId, LatLng center) async {

    final int n = 1 << _zoom;
    final double worldSize = _tileSize.toDouble() * n;

    // world pixel of the airport, and the top-left of the output image
    final (double cx, double cy) = _project(center.latitude, center.longitude, worldSize);
    final double topLeftX = cx - _imageSize / 2.0;
    final double topLeftY = cy - _imageSize / 2.0;

    final int tileMinX = (topLeftX / _tileSize).floor();
    final int tileMaxX = ((topLeftX + _imageSize - 1) / _tileSize).floor();
    final int tileMinY = (topLeftY / _tileSize).floor();
    final int tileMaxY = ((topLeftY + _imageSize - 1) / _tileSize).floor();

    final img.Image out = img.Image(width: _imageSize, height: _imageSize);

    for (int tx = tileMinX; tx <= tileMaxX; tx++) {
      for (int ty = tileMinY; ty <= tileMaxY; ty++) {
        if (ty < 0 || ty >= n) {
          continue; // off the top/bottom of the world
        }
        final int wrappedX = ((tx % n) + n) % n; // wrap around the antimeridian
        final int server = (tx + ty).abs() % 4;
        final String url =
            "https://mt$server.google.com/vt/lyrs=s&x=$wrappedX&y=$ty&z=$_zoom";

        final http.Response r = await http.get(Uri.parse(url),
            headers: {"User-Agent": "Mozilla/5.0"});
        if (r.statusCode != 200) {
          throw Exception("satellite tile download failed (${r.statusCode})");
        }
        final img.Image? tile = img.decodeImage(r.bodyBytes);
        if (tile == null) {
          continue;
        }
        final int dstX = (tx * _tileSize - topLeftX).round();
        final int dstY = (ty * _tileSize - topLeftY).round();
        img.compositeImage(out, tile, dstX: dstX, dstY: dstY);
      }
    }

    // geo-reference: lat/lon of the top-left and bottom-right output pixels.
    // matrix format used by the app: pixelX = (lon - lonTL) * dx, pixelY = (lat - latTL) * dy
    final (double latTopLeft, double lonTopLeft) = _unproject(topLeftX, topLeftY, worldSize);
    final (double latBottomRight, double lonBottomRight) =
        _unproject(topLeftX + _imageSize, topLeftY + _imageSize, worldSize);
    final double dx = out.width / (lonBottomRight - lonTopLeft);
    final double dy = out.height / (latBottomRight - latTopLeft); // negative (lat decreases downward)
    final String userComment = "$dx|$dy|$lonTopLeft|$latTopLeft";

    final Uint8List withExif = encodePngWithGeoref(out, userComment);

    final String p = await getPath(airportId);
    final File f = File(p);
    await f.create(recursive: true);
    await f.writeAsBytes(withExif);
  }

  /// Encodes [image] to PNG with an EXIF `UserComment` georef block. The
  /// [userComment] must be the `dx|dy|lonTopLeft|latTopLeft` matrix string.
  @visibleForTesting
  static Uint8List encodePngWithGeoref(img.Image image, String userComment) {
    final Uint8List png = img.encodePng(image);
    return _injectExif(png, _buildExifBlock(userComment));
  }

  // Web Mercator projection to world pixel coordinates at a given world size.
  static (double, double) _project(double lat, double lon, double worldSize) {
    final double x = (lon + 180.0) / 360.0 * worldSize;
    final double sinLat = math.sin(lat * math.pi / 180.0);
    final double y = (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) * worldSize;
    return (x, y);
  }

  static (double, double) _unproject(double x, double y, double worldSize) {
    final double lon = x / worldSize * 360.0 - 180.0;
    final double n = math.pi - 2 * math.pi * y / worldSize;
    final double lat = 180.0 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
    return (lat, lon);
  }

  /// Builds a TIFF/EXIF block containing the georef in `UserComment`.
  static Uint8List _buildExifBlock(String userComment) {
    final img.ExifData exif = img.ExifData();
    // EXIF UserComment: 8-byte character-code prefix followed by the text
    final List<int> bytes = <int>[
      ...'ASCII\x00\x00\x00'.codeUnits,
      ...userComment.codeUnits,
    ];
    exif.exifIfd[0x9286] = img.IfdValueUndefined.list(bytes);
    final img.OutputBuffer out = img.OutputBuffer(bigEndian: true);
    exif.write(out);
    return out.getBytes();
  }

  /// Inserts an `eXIf` chunk (holding [tiff]) into a PNG right after IHDR.
  static Uint8List _injectExif(Uint8List png, Uint8List tiff) {
    const int sigLen = 8;
    final int ihdrDataLen = _readUint32(png, sigLen);
    final int ihdrEnd = sigLen + 4 + 4 + ihdrDataLen + 4; // len + type + data + crc
    final BytesBuilder bb = BytesBuilder();
    bb.add(png.sublist(0, ihdrEnd));
    bb.add(_makeChunk("eXIf", tiff));
    bb.add(png.sublist(ihdrEnd));
    return bb.toBytes();
  }

  static Uint8List _makeChunk(String type, Uint8List data) {
    final List<int> typeBytes = type.codeUnits;
    final Uint8List typeAndData = Uint8List(typeBytes.length + data.length)
      ..setRange(0, typeBytes.length, typeBytes)
      ..setRange(typeBytes.length, typeBytes.length + data.length, data);
    final BytesBuilder bb = BytesBuilder();
    bb.add(_uint32(data.length));
    bb.add(typeAndData);
    bb.add(_uint32(_crc32(typeAndData)));
    return bb.toBytes();
  }

  static List<int> _uint32(int v) =>
      [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

  static int _readUint32(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static int _crc32(List<int> bytes) {
    int crc = 0xFFFFFFFF;
    for (final int b in bytes) {
      crc ^= b;
      for (int i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88420 : (crc >> 1);
      }
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
