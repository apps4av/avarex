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

class AvidyneStoredRoute {
  // Procedure kinds (Procedure::KindType).
  static const int _kindOrigin = 1;
  static const int _kindDirect = 3;

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
}
