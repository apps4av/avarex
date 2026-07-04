import 'dart:typed_data';

import 'package:avaremp/avidyne/avidyne_crc32.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/plan/plan_route.dart';

/// Builds the binary "stored route" file that the Avidyne IFD expects on an
/// upload over the FMS Wi-Fi channel.
///
/// The layout is a faithful port of `AviSdk::StoredRoute::Upload`:
///   - route name           : 16 bytes (null padded)
///   - number of records    : 1 byte
///   - 128 procedure records: 39 bytes each (real records then zero padding)
///   - CRC-32               : 4 bytes, big-endian, over everything above
///
/// The total file is therefore always 16 + 1 + (128 * 39) + 4 = 5013 bytes.
/// A single point in a route to be uploaded to the IFD.
class AvidyneRoutePoint {
  final String id;
  final double latitude;
  final double longitude;

  /// One of the `AvidyneStoredRoute.fix*` constants.
  final int fixKind;

  const AvidyneRoutePoint({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.fixKind,
  });
}

/// A route parsed back out of a stored-route file downloaded from the IFD.
class AvidyneParsedRoute {
  final String name;
  final List<AvidyneRoutePoint> points;

  const AvidyneParsedRoute({required this.name, required this.points});
}

class AvidyneStoredRoute {
  // Procedure kinds (Procedure::KindType).
  static const int _kindOrigin = 1;
  static const int _kindDestArpt = 2;
  static const int _kindDirect = 3;
  static const int _kindStarAppDest = 10;

  // Fix kinds (Procedure::FixKindType).
  static const int fixNone = 0;
  static const int fixVhfNavaid = 1;
  static const int fixNdbNavaid = 2;
  static const int fixAirport = 3;
  static const int fixWaypoint = 4;
  static const int fixUserWaypoint = 5;
  static const int fixFix = 6;

  // Backwards-compatible private aliases used throughout this file.
  static const int _fixNone = fixNone;
  static const int _fixVhfNavaid = fixVhfNavaid;
  static const int _fixNdbNavaid = fixNdbNavaid;
  static const int _fixAirport = fixAirport;
  static const int _fixWaypoint = fixWaypoint;
  static const int _fixUserWaypoint = fixUserWaypoint;
  static const int _fixFix = fixFix;

  static const int _routeNameLen = 16;
  static const int _maxRecords = 128;
  static const int _recordLen = 39;
  static const int _nameLen = 7;
  static const int _ref1Len = 12;
  static const int _ref2Len = 12;
  static const int _ref3Len = 6;

  /// The maximum number of waypoints the IFD will accept in one route.
  static const int maxWaypoints = _maxRecords;

  /// Builds the upload file for the given route. Returns null if there are not
  /// enough usable waypoints.
  static Uint8List? buildRouteFile(PlanRoute route) {
    return buildRouteFileFromPoints(
        route.name, route.getAllDestinations().map(_toPoint).toList());
  }

  /// Builds the upload file from a plain list of route points. Exposed so the
  /// wire format can be verified independently of the app database.
  static Uint8List? buildRouteFileFromPoints(
      String name, List<AvidyneRoutePoint> points) {
    if (points.length < 2) {
      return null;
    }

    final List<Uint8List> records = [];
    for (int i = 0; i < points.length && records.length < _maxRecords; i++) {
      final AvidyneRoutePoint p = points[i];
      // The very first airport becomes the route origin; everything else is a
      // simple "direct" leg. The IFD navigates by the embedded lat/lon so this
      // reliably reproduces the AvareX flight plan on the IFD ("stick route").
      if (i == 0 && p.fixKind == _fixAirport) {
        records.add(_packOrigin(p));
      } else {
        records.add(_packDirect(p));
      }
    }

    if (records.length < 2) {
      return null;
    }

    final int numRecords = records.length;
    final BytesBuilder builder = BytesBuilder();

    // Route name (16 bytes). Fall back to the IFD default name if empty.
    final String rawName = _sanitizeRouteName(name);
    final Uint8List nameBytes = _fixedField(
        rawName.isEmpty ? 'UPLOADED ROUTE' : rawName, _routeNameLen);
    builder.add(nameBytes);

    builder.addByte(numRecords & 0xFF);

    for (int i = 0; i < _maxRecords; i++) {
      if (i < numRecords) {
        builder.add(records[i]);
      } else {
        builder.add(Uint8List(_recordLen)); // zero padding
      }
    }

    final Uint8List body = builder.toBytes();
    final int crc = AvidyneCrc32.compute(body);

    final BytesBuilder full = BytesBuilder();
    full.add(body);
    full.addByte((crc >> 24) & 0xFF);
    full.addByte((crc >> 16) & 0xFF);
    full.addByte((crc >> 8) & 0xFF);
    full.addByte(crc & 0xFF);

    return full.toBytes();
  }

  static AvidyneRoutePoint _toPoint(Destination d) {
    return AvidyneRoutePoint(
      id: d.locationID,
      latitude: d.coordinate.latitude,
      longitude: d.coordinate.longitude,
      fixKind: _fixKindFor(d),
    );
  }

  static Uint8List _packOrigin(AvidyneRoutePoint p) {
    final BytesBuilder b = BytesBuilder();
    b.addByte(_kindOrigin);
    b.addByte(_fixAirport);
    b.add(_packFix(p.id, p.latitude, p.longitude));
    b.add(Uint8List(_ref3Len)); // no runway
    return _padRecord(b.toBytes());
  }

  static Uint8List _packDirect(AvidyneRoutePoint p) {
    final BytesBuilder b = BytesBuilder();
    b.addByte(_kindDirect);
    b.addByte(p.fixKind);
    b.add(_packFix(p.id, p.latitude, p.longitude));
    b.add(Uint8List(_ref3Len)); // no altitude constraint
    return _padRecord(b.toBytes());
  }

  static int _fixKindFor(Destination d) {
    final String type = d.type;
    if (Destination.isAirport(type)) {
      return _fixAirport;
    }
    if (Destination.isNav(type)) {
      // NDB style navaids vs VHF (VOR) navaids.
      if (type.contains('NDB')) {
        return _fixNdbNavaid;
      }
      return _fixVhfNavaid;
    }
    if (Destination.isFix(type)) {
      return _fixFix;
    }
    if (Destination.isGps(type)) {
      return _fixUserWaypoint;
    }
    if (type == Destination.typeAirway || type == Destination.typeProcedure) {
      return _fixWaypoint;
    }
    return _fixNone;
  }

  /// Port of Procedure::PackFix: name (7) + lat (12) + lon (12).
  static Uint8List _packFix(String ident, double lat, double lon) {
    final BytesBuilder b = BytesBuilder();
    b.add(_nameField(ident));
    b.add(_coordinateField(lat, _ref1Len));
    b.add(_coordinateField(lon, _ref2Len));
    return b.toBytes();
  }

  /// A 7 byte, null terminated identifier field (max 6 usable characters).
  static Uint8List _nameField(String ident) {
    final String cleaned = _sanitizeIdent(ident);
    return _fixedField(cleaned, _nameLen, forceNullTerminated: true);
  }

  /// A 12 byte coordinate field formatted as the SDK's `sprintf("%-10.5f", v)`.
  static Uint8List _coordinateField(double value, int len) {
    String s = value.toStringAsFixed(5);
    if (s.length < 10) {
      s = s.padRight(10); // left justified, minimum width 10
    }
    return _fixedField(s, len, forceNullTerminated: true);
  }

  /// Copies up to [len] ASCII bytes of [value] into a zero filled buffer. When
  /// [forceNullTerminated] is set the final byte is always left as 0 (mirrors
  /// the SDK's `buffer[len-1] = 0`).
  static Uint8List _fixedField(String value, int len,
      {bool forceNullTerminated = false}) {
    final Uint8List out = Uint8List(len);
    final int maxCopy = forceNullTerminated ? len - 1 : len;
    for (int i = 0; i < value.length && i < maxCopy; i++) {
      out[i] = value.codeUnitAt(i) & 0xFF;
    }
    return out;
  }

  static Uint8List _padRecord(Uint8List record) {
    if (record.length == _recordLen) {
      return record;
    }
    final Uint8List out = Uint8List(_recordLen);
    out.setRange(0, record.length.clamp(0, _recordLen), record);
    return out;
  }

  static String _sanitizeIdent(String raw) {
    final String cleaned =
        raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return cleaned.isEmpty ? 'WPT' : cleaned;
  }

  static String _sanitizeRouteName(String raw) {
    final String cleaned = raw.trim();
    if (cleaned.length > _routeNameLen - 1) {
      return cleaned.substring(0, _routeNameLen - 1);
    }
    return cleaned;
  }

  // --- Download / parsing ------------------------------------------------

  /// Parses a stored-route file (as produced by [buildRouteFileFromPoints] or
  /// downloaded from the IFD) back into a name and the list of waypoints that
  /// carry a usable coordinate (origin, destination and direct legs).
  ///
  /// Airway/procedure/hold records are skipped: they reference multi-point
  /// structures rather than a single coordinate, so they cannot be reproduced
  /// as a plain "stick route" waypoint.
  static AvidyneParsedRoute? parseRouteFile(Uint8List bytes) {
    if (bytes.length < _routeNameLen + 1) {
      return null;
    }
    final String name = _readCString(bytes, 0, _routeNameLen).trim();
    final int numRecords = bytes[_routeNameLen];
    final List<AvidyneRoutePoint> points = [];

    int offset = _routeNameLen + 1;
    for (int i = 0; i < numRecords && i < _maxRecords; i++) {
      if (offset + _recordLen > bytes.length) {
        break;
      }
      final int kind = bytes[offset];
      final int fixKind = bytes[offset + 1];
      if (kind == _kindOrigin ||
          kind == _kindDirect ||
          kind == _kindDestArpt ||
          kind == _kindStarAppDest) {
        final int nameStart = offset + 2;
        final String ident = _readCString(bytes, nameStart, _nameLen);
        final double? lat = _parseCoordinate(bytes, nameStart + _nameLen, _ref1Len);
        final double? lon =
            _parseCoordinate(bytes, nameStart + _nameLen + _ref1Len, _ref2Len);
        if (lat != null &&
            lon != null &&
            lat.abs() <= 90.0 &&
            lon.abs() <= 180.0 &&
            !(lat == 0.0 && lon == 0.0)) {
          points.add(AvidyneRoutePoint(
              id: ident, latitude: lat, longitude: lon, fixKind: fixKind));
        }
      }
      offset += _recordLen;
    }

    return AvidyneParsedRoute(name: name, points: points);
  }

  /// Decompresses a file received over the WiFiCrChannel download protocol.
  ///
  /// Downloaded files carry a small header: a 1 byte "is RLE" flag, a 4 byte
  /// big-endian uncompressed length, the (optionally RLE compressed) payload,
  /// and a trailing 2 byte Fletcher-16 checksum. Port of
  /// `WiFiCrChannel::Decompress`.
  static Uint8List? decompressDownload(Uint8List raw) {
    if (raw.length < 7) {
      return null;
    }
    final int isRle = raw[0];
    final int fileSize =
        (raw[1] << 24) | (raw[2] << 16) | (raw[3] << 8) | raw[4];
    if (fileSize <= 0 || fileSize > 1 << 20) {
      return null;
    }
    final int payloadLen = raw.length - 7;
    if (payloadLen < 0) {
      return null;
    }
    final Uint8List payload = Uint8List.sublistView(raw, 5, 5 + payloadLen);

    if (isRle == 1) {
      final List<int> computed = _fletcher16(payload);
      final int c0 = raw[5 + payloadLen];
      final int c1 = raw[5 + payloadLen + 1];
      if (computed[0] != c0 || computed[1] != c1) {
        return null;
      }
      return _rleUncompress(payload, fileSize);
    }

    // Not compressed: the payload is the file (possibly with trailing slack).
    if (payloadLen < fileSize) {
      return null;
    }
    return Uint8List.fromList(payload.sublist(0, fileSize));
  }

  /// Fletcher-16 checksum returning [sum2, sum1] to match `CompUtils::FletcherSum`.
  static List<int> _fletcher16(Uint8List data) {
    int s1 = 0;
    int s2 = 0;
    for (final int b in data) {
      s1 = (s1 + b) % 255;
      s2 = (s1 + s2) % 255;
    }
    return [s2 & 0xFF, s1 & 0xFF];
  }

  /// Run length decoder, port of `CompUtils::RLE_Uncompress2` with diff=false.
  static Uint8List? _rleUncompress(Uint8List input, int outSize) {
    final Uint8List out = Uint8List(outSize);
    final int inSize = input.length;
    int inpos = 0;
    int outpos = 0;

    while (inpos < inSize) {
      final int token = input[inpos];
      if ((token & 0x80) != 0) {
        // A run of raw, non-repeated bytes.
        final int count = token & 0x7f;
        inpos++;
        int i = 0;
        for (; i < count && outpos < outSize && inpos < inSize; i++) {
          out[outpos++] = input[inpos++];
        }
        if (i != count) {
          return null;
        }
      } else if (token >= 2) {
        // A repeated byte.
        if (inpos + 1 >= inSize) {
          return null;
        }
        final int count = input[inpos++];
        final int value = input[inpos++];
        int i = 0;
        for (; i < count && outpos < outSize; i++) {
          out[outpos++] = value;
        }
        if (i != count) {
          return null;
        }
      } else {
        return null; // corrupt token
      }
    }

    if (outpos == outSize) {
      return out;
    }
    // Accept short output by trimming (matches the SDK returning the actual
    // produced length).
    return Uint8List.sublistView(out, 0, outpos);
  }

  static String _readCString(Uint8List bytes, int start, int len) {
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < len && start + i < bytes.length; i++) {
      final int c = bytes[start + i];
      if (c == 0) {
        break;
      }
      sb.writeCharCode(c);
    }
    return sb.toString().trim();
  }

  static double? _parseCoordinate(Uint8List bytes, int start, int len) {
    final String s = _readCString(bytes, start, len).trim();
    if (s.isEmpty) {
      return null;
    }
    return double.tryParse(s);
  }
}
