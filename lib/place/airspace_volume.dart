import 'dart:math' as math;
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';
import 'package:mbtiles/mbtiles.dart';
import 'package:sqflite/sqflite.dart';
import 'package:universal_io/io.dart';
import 'package:vector_tile/raw/raw_vector_tile.dart' as vtraw;
import 'package:vector_tile/util/command.dart';
import 'package:vector_tile/vector_tile.dart';

/// Local east/north position in nautical miles from the long-press point.
class NmPoint {
  final double e;
  final double n;

  const NmPoint(this.e, this.n);
}

/// One polygon ring. [tileCut] marks edges that are only a vector-tile boundary.
class AirspaceRing {
  final List<NmPoint> points;

  /// Edge i joins [points] i to the next point, wrapping at the end.
  final List<bool> tileCut;

  const AirspaceRing(this.points, this.tileCut);

  bool hides(int index) => index >= 0 && index < tileCut.length && tileCut[index];
}

/// One Class B, C, or D shelf, in nautical miles east/north of [AirspaceScene]'s center.
class AirspaceShelf {
  final String airspaceClass;
  final String name;
  String ident;
  final String sector;
  final double floorFt;
  final double ceilingFt;
  final List<AirspaceRing> rings;
  final bool containsCenter;
  final double area;

  /// Ceiling is unlimited (`UNL`). [ceilingFt] is only the height drawn in the view.
  final bool unlimitedCeiling;
  bool showLabel;

  /// On-shelf altitude, such as `25-43`. Airport names are drawn on the ground.
  String label;

  AirspaceShelf({
    required this.airspaceClass,
    required this.name,
    required this.ident,
    required this.sector,
    required this.floorFt,
    required this.ceilingFt,
    required this.rings,
    required this.containsCenter,
    required this.area,
    this.unlimitedCeiling = false,
    this.showLabel = false,
    this.label = '',
  });

  String get identity => '$airspaceClass|$ident|$sector|$floorFt|$ceilingFt|$unlimitedCeiling';

  String get displayIdent => ident.isEmpty ? airspaceClass : ident;

  /// `2000–4000` is `20-40`. `500` is `05`. Surface is `SF`. Unlimited is `UNL`.
  static String altitudeRange(double floorFt, double ceilingFt, {bool unlimited = false}) =>
      unlimited ? '${altitudeHundreds(floorFt)}-UNL' : '${altitudeHundreds(floorFt)}-${altitudeHundreds(ceilingFt)}';

  /// Hundreds of feet MSL, at least two digits. `2500` is `25`. `500` is `05`. Surface is `SF`.
  static String altitudeHundreds(double ft) => ft <= 0 ? 'SF' : (ft / 100).round().toString().padLeft(2, '0');
}

/// `MHT` is shown as `KMHT`. Idents that are already longer are left as stored.
String airspaceIdent(String? raw) {
  final id = (raw ?? '').trim().toUpperCase();
  if (RegExp(r'^[A-Z]{3}$').hasMatch(id)) {
    return 'K$id';
  }
  return id;
}

/// Chart name for a MOA, such as `DEMO 3` from `DEMO 3 MOA, VA`.
String suaChartName(String? name) {
  var title = (name ?? '').trim().toUpperCase();
  final comma = title.indexOf(',');
  if (comma > 0) {
    title = title.substring(0, comma).trim();
  }
  title = title.replaceFirst(RegExp(r'\s+MOA$'), '');
  return title;
}

/// Class C shelves and their names appear at this map zoom. Below it, only Class B.
const airspaceClassCZoom = 7;

/// MOAs, restricted areas, and warning areas appear at this map zoom.
const airspaceLargeSuaZoom = 6;

/// Class D, small special-use areas, and per-sector altitude labels appear here.
const airspaceDetailZoom = 9;

/// `R4101A` is shown as `R-4101A`.
String suaDesignator(String? raw) {
  final id = (raw ?? '').trim().toUpperCase();
  final match = RegExp(r'^([A-Z])-?(\d.*)$').firstMatch(id);
  if (match == null) {
    return id;
  }
  return '${match.group(1)}-${match.group(2)}';
}

/// Special-use altitude. `UNL` is flagged and given the view cap so it still draws.
({double feet, bool unlimited})? parseSuaLimit(String? limit, String? uom, String? ref) {
  final token = (limit ?? '').trim().toUpperCase();
  final reference = (ref ?? '').trim().toUpperCase();
  if (token == 'UNL') {
    return (feet: airspaceDisplayCapFt, unlimited: true);
  }
  if (token.isEmpty) {
    return null;
  }
  if (token == 'GND' || token == 'SFC' || reference == 'SFC') {
    return (feet: 0, unlimited: false);
  }
  final feet = parseAirspaceAltitude(token, null, uom);
  if (feet == null) {
    return null;
  }
  return (feet: feet, unlimited: false);
}

/// Airport drawn on the ground under its surface airspace.
class AirspaceAirport {
  final String ident;
  final String airspaceClass;
  final double e;
  final double n;

  const AirspaceAirport({
    required this.ident,
    required this.airspaceClass,
    required this.e,
    required this.n,
  });
}

/// One obstacle from `main.db` `obs`, in nautical miles east/north of the long-press point.
/// [heightFt] is the obstacle top in feet MSL.
class AirspaceObstacle {
  final double e;
  final double n;
  final double heightFt;

  const AirspaceObstacle({required this.e, required this.n, required this.heightFt});

  /// Hundreds of feet MSL. `1548` is `15`.
  String get label => AirspaceShelf.altitudeHundreds(heightFt);
}

class AirspaceScene {
  final double radiusNm;
  final List<AirspaceShelf> shelves;
  final List<AirspaceAirport> airports;
  final List<AirspaceObstacle> obstacles;
  final String? message;

  const AirspaceScene({
    required this.radiusNm,
    required this.shelves,
    this.airports = const [],
    this.obstacles = const [],
    this.message,
  });

  AirspaceScene copyWith({List<AirspaceObstacle>? obstacles}) => AirspaceScene(
        radiusNm: radiusNm,
        shelves: shelves,
        airports: airports,
        obstacles: obstacles ?? this.obstacles,
        message: message,
      );

  double get maxAltitudeFt {
    var maxFt = 4000.0;
    for (final shelf in shelves) {
      final shown = math.min(shelf.ceilingFt, airspaceDisplayCapFt);
      if (shelf.floorFt < shown && shown > maxFt) {
        maxFt = shown;
      }
    }
    for (final obstacle in obstacles) {
      final shown = math.min(obstacle.heightFt, airspaceDisplayCapFt);
      if (shown > maxFt) {
        maxFt = shown;
      }
    }
    return maxFt;
  }

  List<AirspaceShelf> get shelvesAtCenter {
    final seen = <String>{};
    final here = <AirspaceShelf>[];
    for (final shelf in shelves) {
      if (!shelf.containsCenter || !seen.add(shelf.identity)) {
        continue;
      }
      here.add(shelf);
    }
    here.sort((a, b) {
      final byFloor = a.floorFt.compareTo(b.floorFt);
      if (byFloor != 0) {
        return byFloor;
      }
      return a.airspaceClass.compareTo(b.airspaceClass);
    });
    return here;
  }
}

/// Feet MSL. `SFC` is 0. Flight levels (`FL`) are hundreds of feet.
double? parseAirspaceAltitude(String? value, String? code, String? uom) {
  if (code == 'SFC') {
    return 0;
  }
  if (value == null) {
    return null;
  }
  final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(value.trim());
  if (match == null) {
    return null;
  }
  final n = double.parse(match.group(0)!);
  if (uom == 'FL') {
    return n * 100;
  }
  return n;
}

/// Closed-polygon clip to the square [-limit, limit] on both axes.
List<NmPoint> clipPolygon(List<NmPoint> ring, double limit) {
  if (limit <= 0) {
    return const [];
  }
  return clipPolygonRect(ring, -limit, -limit, limit, limit);
}

/// Closed-polygon clip to an axis-aligned rectangle.
List<NmPoint> clipPolygonRect(List<NmPoint> ring, double minE, double minN, double maxE, double maxN) {
  if (ring.length < 3 || minE >= maxE || minN >= maxN) {
    return const [];
  }
  var output = ring;
  output = _clipEdge(output, (p) => p.e >= minE, (a, b) => _hitE(a, b, minE));
  output = _clipEdge(output, (p) => p.e <= maxE, (a, b) => _hitE(a, b, maxE));
  output = _clipEdge(output, (p) => p.n >= minN, (a, b) => _hitN(a, b, minN));
  output = _clipEdge(output, (p) => p.n <= maxN, (a, b) => _hitN(a, b, maxN));
  return _dedup(output);
}

/// Douglas–Peucker on an open or closed ring. Drops a duplicated closing vertex.
List<NmPoint> simplifyOpenRing(List<NmPoint> pts, double epsilon) {
  if (pts.length <= 2 || epsilon <= 0) {
    return pts;
  }
  var work = pts;
  if (_dist(work.first, work.last) < 1e-6) {
    work = work.sublist(0, work.length - 1);
  }
  if (work.length > 140) {
    work = _stride(work, 140);
  }
  if (work.length <= 2) {
    return work;
  }
  return _dp(work, epsilon);
}

/// Even-odd containment across exterior and hole rings.
bool polygonContains(List<List<NmPoint>> rings, double e, double n) {
  var inside = false;
  for (final ring in rings) {
    if (_ringContains(ring, e, n)) {
      inside = !inside;
    }
  }
  return inside;
}

const double airspaceViewRadiusNm = 25;

/// Shelves are drawn only up to this altitude. Anything higher is a fading crown, not a solid lid.
const double airspaceDisplayCapFt = 10000;

/// East/north nautical miles from [center] when [ownship] is inside the 3D view.
/// Returns null when the aircraft is outside that square.
NmPoint? ownshipOffsetNm(LatLng center, LatLng ownship, {double radiusNm = airspaceViewRadiusNm}) {
  final cosLat = math.cos(center.latitude * math.pi / 180).abs().clamp(0.2, 1.0);
  final east = (ownship.longitude - center.longitude) * 60.0 * cosLat;
  final north = (ownship.latitude - center.latitude) * 60.0;
  if (east.abs() > radiusNm || north.abs() > radiusNm) {
    return null;
  }
  return NmPoint(east, north);
}

/// Obstacles inside the 25 NM square. Rows are `obs` columns `ARPLatitude`, `ARPLongitude`, and `Height` (feet MSL).
List<AirspaceObstacle> obstaclesInView(List<Map<String, Object?>> rows, LatLng center, {double radiusNm = airspaceViewRadiusNm}) {
  final cosLat = math.cos(center.latitude * math.pi / 180).abs().clamp(0.2, 1.0);
  final obstacles = <AirspaceObstacle>[];
  for (final row in rows) {
    final lat = _asDouble(row['ARPLatitude']);
    final lon = _asDouble(row['ARPLongitude']);
    final height = _asDouble(row['Height']);
    if (lat == null || lon == null || height == null || height <= 0) {
      continue;
    }
    final east = (lon - center.longitude) * 60.0 * cosLat;
    final north = (lat - center.latitude) * 60.0;
    if (east.abs() > radiusNm || north.abs() > radiusNm) {
      continue;
    }
    obstacles.add(AirspaceObstacle(e: east, n: north, heightFt: height));
  }
  return obstacles;
}

double? _asDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

/// Obstacles within [airspaceViewRadiusNm] of [center] from the main database `obs` table.
///
/// A missing file or a database without `obs` yields an empty list so the airspace view still opens.
Future<List<AirspaceObstacle>> loadObstacles(String dbPath, LatLng center) async {
  if (!File(dbPath).existsSync()) {
    return const [];
  }
  Database? db;
  try {
    db = await openDatabase(dbPath, readOnly: true, singleInstance: false);
    final lat = center.latitude;
    final lon = center.longitude;
    final cosLat = math.cos(lat * math.pi / 180).abs().clamp(0.2, 1.0);
    final dLat = airspaceViewRadiusNm / 60.0;
    final dLon = airspaceViewRadiusNm / (60.0 * cosLat);
    final rows = await db.rawQuery(
      'select ARPLatitude, ARPLongitude, Height from obs '
      'where ARPLatitude > ? and ARPLatitude < ? and ARPLongitude > ? and ARPLongitude < ?',
      [lat - dLat, lat + dLat, lon - dLon, lon + dLon],
    );
    return obstaclesInView(rows, center);
  } catch (_) {
    return const [];
  } finally {
    try {
      await db?.close();
    } catch (_) {}
  }
}

/// Label for one vector-map airspace feature, in the same form as the 3D view.
///
/// A shelf is `25-43`. The airport ident is included only for the surface
/// shelf at the center (`KMHT` over `SF-43`).
/// Special-use areas keep the designator, such as `R-4101A SF-25`.
String? vectorAirspaceLabel(Map<String, String> props, {required bool sua, bool airportAtCenter = false}) {
  if (props['EXCLUSION'] == '1') {
    return null;
  }
  if (!sua) {
    final code = props['CLASS'];
    if (code != 'B' && code != 'C' && code != 'D') {
      return null;
    }
    final floor = parseAirspaceAltitude(props['LOWER_VAL'], props['LOWER_CODE'], props['LOWER_UOM']);
    final ceiling = parseAirspaceAltitude(props['UPPER_VAL'], props['UPPER_CODE'], props['UPPER_UOM']);
    if (floor == null || ceiling == null || ceiling <= floor) {
      return null;
    }
    final range = AirspaceShelf.altitudeRange(floor, ceiling);
    if (!airportAtCenter || floor > 0) {
      return range;
    }
    final ident = airspaceIdent(props['IDENT']);
    if (ident.isEmpty) {
      return range;
    }
    return '$ident\n$range';
  }
  final type = props['TYPE'] ?? '';
  if (type != 'RESTRICTED' && type != 'WARNING' && type != 'PROHIBITED' && type != 'MOA' && type != 'ALERT' && type != 'NSA') {
    return null;
  }
  final floor = parseSuaLimit(props['LOWER_LIMIT'], props['LOWER_UOM'], props['LOWER_REF']);
  final ceiling = parseSuaLimit(props['UPPER_LIMIT'], props['UPPER_UOM'], props['UPPER_REF']);
  if (floor == null || ceiling == null) {
    final name = (props['NAME'] ?? '').trim();
    return name.isEmpty ? null : name;
  }
  final range = AirspaceShelf.altitudeRange(floor.feet, ceiling.feet, unlimited: ceiling.unlimited);
  final chart = type == 'MOA' ? suaChartName(props['NAME']) : '';
  final ident = chart.isEmpty ? suaDesignator(props['DESIGNATOR']) : chart;
  if (ident.isEmpty) {
    return range;
  }
  return '$ident $range';
}

/// A towered airport used to place a surface-shelf name on the field itself.
class ChartAirport {
  final String ident;
  final double latitude;
  final double longitude;

  const ChartAirport(this.ident, this.latitude, this.longitude);
}

/// Towered airports inside [south]/[north]/[west]/[east], from the main database.
///
/// A missing file or a database without `airports` yields an empty list.
Future<List<ChartAirport>> loadChartAirports(
  String dbPath, {
  required double south,
  required double north,
  required double west,
  required double east,
}) async {
  if (!File(dbPath).existsSync()) {
    return const [];
  }
  Database? db;
  try {
    db = await openDatabase(dbPath, readOnly: true, singleInstance: false);
    final rows = await db.rawQuery(
      'select LocationID, ARPLatitude, ARPLongitude from airports '
      'where Type = ? and ATCT = ? and ARPLatitude > ? and ARPLatitude < ? and ARPLongitude > ? and ARPLongitude < ?',
      ['AIRPORT', 'Y', south, north, west, east],
    );
    return [
      for (final row in rows)
        if (row['LocationID'] is String && row['ARPLatitude'] is num && row['ARPLongitude'] is num)
          ChartAirport(row['LocationID'] as String, (row['ARPLatitude'] as num).toDouble(), (row['ARPLongitude'] as num).toDouble()),
    ];
  } catch (_) {
    return const [];
  } finally {
    try {
      await db?.close();
    } catch (_) {}
  }
}

/// One airspace label placed in geographic coordinates for the vector map.
class AirspaceMapLabel {
  final LatLng point;
  final String text;
  final String kind;

  const AirspaceMapLabel(this.point, this.text, this.kind);
}

/// Parsed vector-map shelves, cached by tile, with labels placed for the current view.
///
/// The tile renderer keeps a single copy of each label and drops it unless the
/// whole text box sits inside the tile. KBOS falls on a tile edge at some zooms,
/// so that copy disappears while the fill remains. These labels follow the view.
class AirspaceLabelSource {
  final MbTiles db;
  final Map<String, Map<String, _MapShelf>> _tiles = {};

  AirspaceLabelSource(this.db);

  List<AirspaceMapLabel> labels({
    required double north,
    required double south,
    required double west,
    required double east,
    required double centerLat,
    required double centerLon,
    required int tileZoom,
    List<ChartAirport> airports = const [],
    bool placeNamesAtAirports = false,
  }) {
    if (tileZoom < airspaceLargeSuaZoom || north <= south || east <= west) {
      return const [];
    }
    final z = tileZoom.clamp(0, 22);
    final detail = z >= airspaceDetailZoom;
    final span = _tileSpan(z, north, south, west, east, centerLat, centerLon);
    final merged = <String, _MapShelf>{};
    for (var x = span.$1; x <= span.$2; x++) {
      for (var y = span.$3; y <= span.$4; y++) {
        final shelves = _tileShelves(z, x, y);
        for (final shelf in shelves.values) {
          final group = merged.putIfAbsent(shelf.key, () => shelf.bare());
          group.absorb(shelf);
        }
      }
    }
    return _placeShelves(
      merged.values,
      north,
      south,
      west,
      east,
      centerLat,
      centerLon,
      airports: detail ? airports : const [],
      placeNamesAtAirports: detail && placeNamesAtAirports,
      sectorLabels: detail,
    );
  }

  (int, int, int, int) _tileSpan(int z, double north, double south, double west, double east, double centerLat, double centerLon) {
    final nw = _xyz(north, west, z);
    final se = _xyz(south, east, z);
    var x0 = math.min(nw.$1, se.$1);
    var x1 = math.max(nw.$1, se.$1);
    var y0 = math.min(nw.$2, se.$2);
    var y1 = math.max(nw.$2, se.$2);
    final count = (x1 - x0 + 1) * (y1 - y0 + 1);
    if (count > 25) {
      final center = _xyz(centerLat, centerLon, z);
      x0 = center.$1 - 2;
      x1 = center.$1 + 2;
      y0 = center.$2 - 2;
      y1 = center.$2 + 2;
    } else {
      x0 -= 1;
      x1 += 1;
      y0 -= 1;
      y1 += 1;
    }
    final n = (1 << z) - 1;
    return (x0.clamp(0, n), x1.clamp(0, n), y0.clamp(0, n), y1.clamp(0, n));
  }

  Map<String, _MapShelf> _tileShelves(int z, int x, int y) {
    final key = '$z/$x/$y';
    final cached = _tiles[key];
    if (cached != null) {
      return cached;
    }
    if (_tiles.length > 80) {
      _tiles.clear();
    }
    final bytes = db.getTile(z: z, x: x, y: (1 << z) - 1 - y);
    final shelves = <String, _MapShelf>{};
    if (bytes != null && bytes.isNotEmpty) {
      try {
        _readMapShelves(VectorTile.fromBytes(bytes: bytes), z, x, y, shelves, zoom: z);
      } catch (_) {}
    }
    _tiles[key] = shelves;
    return shelves;
  }
}

class _MapShelf {
  final String key;
  final String altitude;
  final String named;
  final String kind;
  LatLng? nameAt;
  final List<List<List<List<double>>>> polygons = [];
  double minLat = 90;
  double maxLat = -90;
  double minLon = 180;
  double maxLon = -180;

  _MapShelf(this.key, this.altitude, this.named, this.kind);

  _MapShelf bare() => _MapShelf(key, altitude, named, kind);

  void absorb(_MapShelf other) {
    polygons.addAll(other.polygons);
    nameAt ??= other.nameAt;
    if (other.polygons.isEmpty) {
      return;
    }
    minLat = math.min(minLat, other.minLat);
    maxLat = math.max(maxLat, other.maxLat);
    minLon = math.min(minLon, other.minLon);
    maxLon = math.max(maxLon, other.maxLon);
  }

  bool contains(double lat, double lon) {
    for (final polygon in polygons) {
      var inside = false;
      for (final ring in polygon) {
        if (ring.length >= 3 && _lonLatRingContains(ring, lon, lat)) {
          inside = !inside;
        }
      }
      if (inside) {
        return true;
      }
    }
    return false;
  }

  /// Airport ident for a class shelf. Empty for special-use airspace.
  String get ident {
    final parts = key.split('|');
    return parts.length >= 3 && parts[0] == 'C' ? parts[2] : '';
  }

  /// Floor in hundreds of feet. Surface (`SF`) is `0`.
  double get floorHundreds {
    final head = altitude.split('\n').last.split('-').first.trim();
    if (head == 'SF' || head == '00') {
      return 0;
    }
    return double.tryParse(head) ?? double.infinity;
  }
}

bool _shownAtZoom(String kind, int zoom) {
  switch (kind) {
    case 'B':
      return true;
    case 'C':
      return zoom >= airspaceClassCZoom;
    case 'MOA':
    case 'RESTRICTED':
    case 'WARNING':
      return zoom >= airspaceLargeSuaZoom;
    default:
      return zoom >= airspaceDetailZoom;
  }
}

void _readMapShelves(VectorTile tile, int z, int x, int y, Map<String, _MapShelf> shelves, {required int zoom}) {
  for (final layer in tile.layers) {
    final sua = layer.name == 'sua_airspace';
    if (layer.name != 'class_airspace' && !sua) {
      continue;
    }
    final extent = layer.extent == 0 ? 4096 : layer.extent;
    for (final feature in layer.features) {
      final props = _stringProps(feature);
      final altitude = vectorAirspaceLabel(props, sua: sua);
      if (altitude == null || altitude.isEmpty) {
        continue;
      }
      final kind = sua ? (props['TYPE'] ?? '') : (props['CLASS'] ?? '');
      if (!_shownAtZoom(kind, zoom)) {
        continue;
      }
      final polygons = _latLonPolygons(feature.decodeGeometry(), z, x, y, extent);
      if (polygons.isEmpty) {
        continue;
      }
      final named = vectorAirspaceLabel(props, sua: sua, airportAtCenter: true) ?? altitude;
      final key = _shelfKey(props, sua);
      final shelf = shelves.putIfAbsent(
        key,
        () => _MapShelf(key, altitude, named, kind),
      );
      for (final polygon in polygons) {
        shelf.polygons.add(polygon);
        for (final ring in polygon) {
          for (final point in ring) {
            shelf.minLat = math.min(shelf.minLat, point[1]);
            shelf.maxLat = math.max(shelf.maxLat, point[1]);
            shelf.minLon = math.min(shelf.minLon, point[0]);
            shelf.maxLon = math.max(shelf.maxLon, point[0]);
          }
        }
      }
    }
  }
  for (final layer in tile.layers) {
    final sua = layer.name == 'sua_airspace_labels';
    if (layer.name != 'class_airspace_labels' && !sua) {
      continue;
    }
    final extent = layer.extent == 0 ? 4096 : layer.extent;
    for (final feature in layer.features) {
      final props = _stringProps(feature);
      final altitude = vectorAirspaceLabel(props, sua: sua);
      if (altitude == null || altitude.isEmpty) {
        continue;
      }
      final kind = sua ? (props['TYPE'] ?? '') : (props['CLASS'] ?? '');
      if (!_shownAtZoom(kind, zoom)) {
        continue;
      }
      final at = _labelLatLng(feature.geometryList, z, x, y, extent);
      if (at == null) {
        continue;
      }
      final named = vectorAirspaceLabel(props, sua: sua, airportAtCenter: true) ?? altitude;
      final key = _shelfKey(props, sua);
      final shelf = shelves.putIfAbsent(
        key,
        () => _MapShelf(key, altitude, named, kind),
      );
      shelf.nameAt ??= at;
    }
  }
}

List<AirspaceMapLabel> _placeOverview(List<_MapShelf> shelves, double north, double south, double west, double east, double centerLat, double centerLon) {
  final labels = <AirspaceMapLabel>[];
  for (final shelf in shelves) {
    if ((shelf.kind != 'B' && shelf.kind != 'C') || shelf.floorHundreds != 0) {
      continue;
    }
    final nameAt = shelf.nameAt;
    if (nameAt == null || nameAt.latitude > north || nameAt.latitude < south || nameAt.longitude < west || nameAt.longitude > east) {
      continue;
    }
    labels.add(AirspaceMapLabel(nameAt, shelf.named, shelf.kind));
  }
  if (labels.length > 40) {
    labels.sort((a, b) {
      final da = (a.point.latitude - centerLat).abs() + (a.point.longitude - centerLon).abs();
      final db = (b.point.latitude - centerLat).abs() + (b.point.longitude - centerLon).abs();
      return da.compareTo(db);
    });
    labels.removeRange(40, labels.length);
  }
  return labels;
}

List<AirspaceMapLabel> _placeShelves(
  Iterable<_MapShelf> shelves,
  double north,
  double south,
  double west,
  double east,
  double centerLat,
  double centerLon, {
  required List<ChartAirport> airports,
  required bool placeNamesAtAirports,
  required bool sectorLabels,
}) {
  final all = shelves.toList(growable: false);
  if (!sectorLabels) {
    return _placeOverview(all, north, south, west, east, centerLat, centerLon);
  }
  final labels = <AirspaceMapLabel>[];
  final airportNames = placeNamesAtAirports ? _namesAtAirports(all, airports, north, south, west, east) : const <AirspaceMapLabel>[];
  labels.addAll(airportNames);
  for (final shelf in all) {
    if (shelf.polygons.isNotEmpty && (shelf.maxLat < south || shelf.minLat > north || shelf.maxLon < west || shelf.minLon > east)) {
      continue;
    }
    final nameAt = shelf.nameAt;
    final nameInView = !placeNamesAtAirports &&
        nameAt != null &&
        nameAt.latitude <= north &&
        nameAt.latitude >= south &&
        nameAt.longitude >= west &&
        nameAt.longitude <= east &&
        !_lowerShelfCovers(all, shelf, nameAt.latitude, nameAt.longitude);
    if (nameInView) {
      labels.add(AirspaceMapLabel(nameAt, shelf.named, shelf.kind));
    }
    final anchor = _visibleAnchor(all, shelf, north, south, west, east, centerLat, centerLon);
    if (anchor == null) {
      continue;
    }
    if (nameInView && (anchor.latitude - nameAt.latitude).abs() < 0.12 && (anchor.longitude - nameAt.longitude).abs() < 0.16) {
      continue;
    }
    if (nameInView && shelf.named == shelf.altitude) {
      continue;
    }
    if (_airportNameCovers(airportNames, shelf, anchor)) {
      continue;
    }
    labels.add(AirspaceMapLabel(anchor, shelf.altitude, shelf.kind));
  }
  if (labels.length > 60) {
    labels.sort((a, b) {
      final name = (a.text.contains('\n') ? 0 : 1).compareTo(b.text.contains('\n') ? 0 : 1);
      if (name != 0) {
        return name;
      }
      final da = (a.point.latitude - centerLat).abs() + (a.point.longitude - centerLon).abs();
      final db = (b.point.latitude - centerLat).abs() + (b.point.longitude - centerLon).abs();
      return da.compareTo(db);
    });
    labels.removeRange(60, labels.length);
  }
  labels.sort((a, b) => (a.text.contains('\n') ? 0 : 1).compareTo(b.text.contains('\n') ? 0 : 1));
  return labels;
}

List<AirspaceMapLabel> _namesAtAirports(List<_MapShelf> shelves, List<ChartAirport> airports, double north, double south, double west, double east) {
  final labels = <AirspaceMapLabel>[];
  final seen = <String>{};
  for (final airport in airports) {
    if (airport.latitude > north || airport.latitude < south || airport.longitude < west || airport.longitude > east) {
      continue;
    }
    final ident = airspaceIdent(airport.ident);
    if (ident.isEmpty || !seen.add(ident)) {
      continue;
    }
    _MapShelf? matched;
    _MapShelf? containing;
    for (final shelf in shelves) {
      if (shelf.floorHundreds != 0 || (shelf.kind != 'B' && shelf.kind != 'C' && shelf.kind != 'D')) {
        continue;
      }
      if (shelf.polygons.isEmpty || !shelf.contains(airport.latitude, airport.longitude)) {
        continue;
      }
      if (airspaceIdent(shelf.ident) == ident) {
        matched = shelf;
        break;
      }
      containing ??= shelf;
    }
    final shelf = matched ?? containing;
    if (shelf == null) {
      continue;
    }
    labels.add(AirspaceMapLabel(LatLng(airport.latitude, airport.longitude), '$ident\n${shelf.altitude}', shelf.kind));
  }
  return labels;
}

bool _airportNameCovers(List<AirspaceMapLabel> names, _MapShelf shelf, LatLng anchor) {
  for (final name in names) {
    if (!name.text.endsWith(shelf.altitude)) {
      continue;
    }
    if ((name.point.latitude - anchor.latitude).abs() < 0.12 && (name.point.longitude - anchor.longitude).abs() < 0.16) {
      return true;
    }
  }
  return false;
}

LatLng? _visibleAnchor(List<_MapShelf> shelves, _MapShelf shelf, double north, double south, double west, double east, double centerLat, double centerLon) {
  final nameAt = shelf.nameAt;
  if (nameAt != null &&
      nameAt.latitude <= north &&
      nameAt.latitude >= south &&
      nameAt.longitude >= west &&
      nameAt.longitude <= east &&
      !_lowerShelfCovers(shelves, shelf, nameAt.latitude, nameAt.longitude)) {
    return nameAt;
  }
  if (_anchorInShelf(shelves, shelf, centerLat, centerLon)) {
    return LatLng(centerLat, centerLon);
  }
  LatLng? best;
  var bestDistance = double.infinity;
  for (var row = 0; row < 5; row++) {
    for (var col = 0; col < 5; col++) {
      final lat = south + (north - south) * (row + 0.5) / 5;
      final lon = west + (east - west) * (col + 0.5) / 5;
      if (!_anchorInShelf(shelves, shelf, lat, lon)) {
        continue;
      }
      final distance = (lat - centerLat).abs() + (lon - centerLon).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = LatLng(lat, lon);
      }
    }
  }
  return best;
}

/// A fallback point has to lie in this shelf, and near the shelf's own label.
///
/// Low-zoom polygons are coarse. Without the distance limit a shelf from
/// another state can contain the camera and its name is drawn here.
bool _anchorInShelf(List<_MapShelf> shelves, _MapShelf shelf, double lat, double lon) {
  if (!shelf.contains(lat, lon) || _lowerShelfCovers(shelves, shelf, lat, lon)) {
    return false;
  }
  final nameAt = shelf.nameAt;
  final latReach = math.min(1.0, math.max(0.15, shelf.polygons.isEmpty ? 0.15 : (shelf.maxLat - shelf.minLat) * 0.6));
  final lonReach = math.min(1.0, math.max(0.15, shelf.polygons.isEmpty ? 0.15 : (shelf.maxLon - shelf.minLon) * 0.6));
  if (nameAt != null) {
    return (lat - nameAt.latitude).abs() <= latReach && (lon - nameAt.longitude).abs() <= lonReach;
  }
  return lat >= shelf.minLat - latReach && lat <= shelf.maxLat + latReach && lon >= shelf.minLon - lonReach && lon <= shelf.maxLon + lonReach;
}

/// True when a lower shelf of the same airport already covers [lat]/[lon].
///
/// Outer KBOS shelves are drawn as disks, so the airport is inside `SF-70`,
/// `20-70`, and `30-70`. Only the lowest floor is labeled there.
bool _lowerShelfCovers(List<_MapShelf> shelves, _MapShelf shelf, double lat, double lon) {
  if (shelf.kind != 'B' && shelf.kind != 'C' && shelf.kind != 'D') {
    return false;
  }
  final ident = shelf.ident;
  if (ident.isEmpty) {
    return false;
  }
  final floor = shelf.floorHundreds;
  for (final other in shelves) {
    if (identical(other, shelf) || other.kind != shelf.kind || other.ident != ident || other.floorHundreds >= floor) {
      continue;
    }
    if (other.contains(lat, lon)) {
      return true;
    }
  }
  return false;
}

String _shelfKey(Map<String, String> props, bool sua) {
  if (sua) {
    return 'S|${props['TYPE']}|${props['DESIGNATOR']}|${props['NAME']}|${props['LOWER_LIMIT']}|${props['UPPER_LIMIT']}';
  }
  return 'C|${props['CLASS']}|${props['IDENT']}|${props['SECTOR']}|${props['LOWER_VAL']}|${props['UPPER_VAL']}';
}

Map<String, String> _stringProps(VectorTileFeature feature) {
  final props = <String, String>{};
  feature.decodeProperties().forEach((key, value) {
    final text = value.stringValue ?? value.dartIntValue?.toString() ?? value.dartDoubleValue?.toString();
    if (text != null) {
      props[key] = text;
    }
  });
  return props;
}

List<List<List<List<double>>>> _latLonPolygons(Geometry? geometry, int z, int x, int y, int extent) {
  final source = <List<List<List<double>>>>[];
  if (geometry is GeometryPolygon) {
    source.add(geometry.coordinates);
  } else if (geometry is GeometryMultiPolygon) {
    source.addAll(geometry.coordinates ?? const []);
  }
  final polygons = <List<List<List<double>>>>[];
  for (final polygon in source) {
    final rings = <List<List<double>>>[];
    for (final ring in polygon) {
      final converted = <List<double>>[];
      for (final point in ring) {
        if (point.length < 2) {
          continue;
        }
        final at = _tileToLatLng(z, x, y, point[0], point[1], extent);
        converted.add([at.longitude, at.latitude]);
      }
      if (converted.length >= 3) {
        rings.add(converted);
      }
    }
    if (rings.isNotEmpty) {
      polygons.add(rings);
    }
  }
  return polygons;
}

LatLng? _labelLatLng(List<int>? geometry, int z, int x, int y, int extent) {
  if (geometry == null || geometry.length < 3 || (geometry[0] & 7) != 1) {
    return null;
  }
  return _tileToLatLng(z, x, y, Command.zigZagDecode(geometry[1]).toDouble(), Command.zigZagDecode(geometry[2]).toDouble(), extent);
}

LatLng _tileToLatLng(int z, int x, int y, double px, double py, int extent) {
  final n = 1 << z;
  final lon = (x + px / extent) / n * 360.0 - 180.0;
  final mercator = math.pi * (1 - 2 * (y + py / extent) / n);
  final lat = math.atan((math.exp(mercator) - math.exp(-mercator)) / 2) * 180.0 / math.pi;
  return LatLng(lat, lon);
}

(int, int) _xyz(double lat, double lon, int z) {
  final n = 1 << z;
  final x = ((lon + 180.0) / 360.0 * n).floor().clamp(0, n - 1);
  final latRad = lat.clamp(-85.0, 85.0) * math.pi / 180.0;
  final y = ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2 * n).floor().clamp(0, n - 1);
  return (x, y);
}

bool _lonLatRingContains(List<List<double>> ring, double lon, double lat) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final xi = ring[i][0];
    final yi = ring[i][1];
    final xj = ring[j][0];
    final yj = ring[j][1];
    final crosses = (yi > lat) != (yj > lat) && lon < (xj - xi) * (lat - yi) / (yj - yi) + xi;
    if (crosses) {
      inside = !inside;
    }
  }
  return inside;
}

/// True when a label point sits inside the tile, not on a tile-edge fragment.
bool vectorLabelPointInside(List<int> geometry, int extent) {
  if (geometry.length < 3 || (geometry[0] & 7) != 1 || extent <= 0) {
    return false;
  }
  final x = Command.zigZagDecode(geometry[1]);
  final y = Command.zigZagDecode(geometry[2]);
  final margin = math.max(48, extent ~/ 24);
  return x >= margin && y >= margin && x <= extent - margin && y <= extent - margin;
}

/// Interior points spread through a sector, in tile units.
///
/// One centroid disappears once zoom crosses into a part of the sector that
/// does not contain it. A short grid keeps an altitude in view.
List<List<int>> airspaceLabelGrid(List<List<List<int>>> rings, int extent) {
  if (rings.isEmpty || rings.first.length < 3 || extent <= 0) {
    return const [];
  }
  var minX = rings.first.first[0];
  var maxX = minX;
  var minY = rings.first.first[1];
  var maxY = minY;
  for (final point in rings.first) {
    minX = math.min(minX, point[0]);
    maxX = math.max(maxX, point[0]);
    minY = math.min(minY, point[1]);
    maxY = math.max(maxY, point[1]);
  }
  final margin = math.max(128, extent ~/ 20);
  minX = math.max(minX, margin);
  maxX = math.min(maxX, extent - margin);
  minY = math.max(minY, margin);
  maxY = math.min(maxY, extent - margin);
  if (minX >= maxX || minY >= maxY) {
    return _gridCentroid(rings);
  }
  const cells = 4;
  final stepX = (maxX - minX) / cells;
  final stepY = (maxY - minY) / cells;
  final points = <List<int>>[];
  for (var row = 0; row < cells; row++) {
    for (var col = 0; col < cells; col++) {
      final x = (minX + (col + 0.5) * stepX).round();
      final y = (minY + (row + 0.5) * stepY).round();
      if (_ringsContain(rings, x, y)) {
        points.add([x, y]);
      }
    }
  }
  if (points.isEmpty) {
    return _gridCentroid(rings);
  }
  return points;
}

List<List<int>> _gridCentroid(List<List<List<int>>> rings) {
  final ring = rings.first;
  var x = 0;
  var y = 0;
  for (final point in ring) {
    x += point[0];
    y += point[1];
  }
  final at = [x ~/ ring.length, y ~/ ring.length];
  if (_ringsContain(rings, at[0], at[1])) {
    return [at];
  }
  return const [];
}

bool _ringsContain(List<List<List<int>>> rings, int x, int y) {
  var inside = false;
  for (final ring in rings) {
    if (_tileRingContains(ring, x, y)) {
      inside = !inside;
    }
  }
  return inside;
}

bool _tileRingContains(List<List<int>> ring, int x, int y) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final xi = ring[i][0];
    final yi = ring[i][1];
    final xj = ring[j][0];
    final yj = ring[j][1];
    final crosses = (yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi;
    if (crosses) {
      inside = !inside;
    }
  }
  return inside;
}

/// Adds a `LABEL` property to airspace label points: `xx-yy`, with the airport at the center.
Uint8List annotateVectorAirspaceLabels(Uint8List bytes) {
  if (bytes.isEmpty) {
    return bytes;
  }
  vtraw.VectorTile tile;
  try {
    tile = vtraw.VectorTile.fromBuffer(bytes);
  } catch (_) {
    return bytes;
  }
  var changed = false;
  for (final layer in tile.layers) {
    final sua = layer.name == 'sua_airspace_labels';
    if (layer.name != 'class_airspace_labels' && !sua) {
      continue;
    }
    final extent = layer.extent == 0 ? 4096 : layer.extent;
    final labelKey = layer.keys.length;
    layer.keys.add('LABEL');
    final valueIndex = <String, int>{};
    for (var i = 0; i < layer.values.length; i++) {
      if (layer.values[i].hasStringValue()) {
        valueIndex[layer.values[i].stringValue] = i;
      }
    }
    for (final feature in layer.features) {
      final props = _rawProps(layer, feature);
      final label = vectorAirspaceLabel(
        props,
        sua: sua,
        airportAtCenter: !sua && vectorLabelPointInside(feature.geometry, extent),
      );
      if (label == null || label.isEmpty) {
        continue;
      }
      final existing = valueIndex[label];
      final valueKey = existing ?? layer.values.length;
      if (existing == null) {
        layer.values.add(vtraw.VectorTile_Value(stringValue: label));
        valueIndex[label] = valueKey;
      }
      feature.tags.add(labelKey);
      feature.tags.add(valueKey);
      changed = true;
    }
    if (_repeatSectorLabels(tile, layer, labelKey, valueIndex, sua)) {
      changed = true;
    }
  }
  if (!changed) {
    return bytes;
  }
  return Uint8List.fromList(tile.writeToBuffer());
}

/// Copies each sector polygon onto a grid of label points in the matching label layer.
bool _repeatSectorLabels(
  vtraw.VectorTile tile,
  vtraw.VectorTile_Layer labelLayer,
  int labelKey,
  Map<String, int> valueIndex,
  bool sua,
) {
  final polygonName = sua ? 'sua_airspace' : 'class_airspace';
  vtraw.VectorTile_Layer? polygons;
  for (final layer in tile.layers) {
    if (layer.name == polygonName) {
      polygons = layer;
      break;
    }
  }
  if (polygons == null || polygons.features.isEmpty) {
    return false;
  }
  final decoded = VectorTile(layers: [VectorTileLayer.fromRaw(rawLayer: polygons)]);
  final field = sua ? 'TYPE' : 'CLASS';
  final fieldKey = _ensureKey(labelLayer, field);
  final extent = polygons.extent == 0 ? 4096 : polygons.extent;
  var added = false;
  for (final feature in decoded.layers.single.features) {
    final props = <String, String>{};
    feature.decodeProperties().forEach((key, value) {
      final text = value.stringValue ?? value.dartIntValue?.toString() ?? value.dartDoubleValue?.toString();
      if (text != null) {
        props[key] = text;
      }
    });
    final label = vectorAirspaceLabel(props, sua: sua);
    final fieldValue = props[field];
    if (label == null || label.isEmpty || fieldValue == null || fieldValue.isEmpty) {
      continue;
    }
    final geometry = feature.decodeGeometry();
    final rings = _polygonRings(geometry);
    for (final ring in rings) {
      for (final point in airspaceLabelGrid(ring, extent)) {
        labelLayer.features.add(vtraw.VectorTile_Feature(
          type: vtraw.VectorTile_GeomType.POINT,
          tags: [fieldKey, _ensureValue(labelLayer, valueIndex, fieldValue), labelKey, _ensureValue(labelLayer, valueIndex, label)],
          geometry: [(1 << 3) | 1, Command.zigZagEncode(point[0]), Command.zigZagEncode(point[1])],
        ));
        added = true;
      }
    }
  }
  return added;
}

int _ensureKey(vtraw.VectorTile_Layer layer, String name) {
  final index = layer.keys.indexOf(name);
  if (index >= 0) {
    return index;
  }
  layer.keys.add(name);
  return layer.keys.length - 1;
}

int _ensureValue(vtraw.VectorTile_Layer layer, Map<String, int> valueIndex, String text) {
  final existing = valueIndex[text];
  if (existing != null) {
    return existing;
  }
  final index = layer.values.length;
  layer.values.add(vtraw.VectorTile_Value(stringValue: text));
  valueIndex[text] = index;
  return index;
}

List<List<List<List<int>>>> _polygonRings(Geometry? geometry) {
  if (geometry is GeometryPolygon) {
    return [_ringInts(geometry.coordinates)];
  }
  if (geometry is GeometryMultiPolygon) {
    return [
      for (final polygon in geometry.coordinates ?? <List<List<List<double>>>>[]) _ringInts(polygon),
    ];
  }
  return const [];
}

List<List<List<int>>> _ringInts(List<List<List<double>>> rings) {
  return [
    for (final ring in rings)
      [
        for (final point in ring)
          if (point.length >= 2) [point[0].round(), point[1].round()],
      ],
  ];
}

Map<String, String> _rawProps(vtraw.VectorTile_Layer layer, vtraw.VectorTile_Feature feature) {
  final props = <String, String>{};
  final tags = feature.tags;
  for (var i = 0; i + 1 < tags.length; i += 2) {
    final keyIndex = tags[i];
    final valueIndex = tags[i + 1];
    if (keyIndex < 0 || keyIndex >= layer.keys.length || valueIndex < 0 || valueIndex >= layer.values.length) {
      continue;
    }
    final text = _rawValueText(layer.values[valueIndex]);
    if (text != null) {
      props[layer.keys[keyIndex]] = text;
    }
  }
  return props;
}

String? _rawValueText(vtraw.VectorTile_Value value) {
  if (value.hasStringValue()) {
    return value.stringValue;
  }
  if (value.hasIntValue()) {
    return value.intValue.toString();
  }
  if (value.hasSintValue()) {
    return value.sintValue.toString();
  }
  if (value.hasUintValue()) {
    return value.uintValue.toString();
  }
  if (value.hasDoubleValue()) {
    return value.doubleValue.toString();
  }
  if (value.hasFloatValue()) {
    return value.floatValue.toString();
  }
  return null;
}

const int _airspaceZoom = 10;

/// Class B, C, and D shelves, plus restricted and warning areas, within [airspaceViewRadiusNm] of [center].
///
/// Reads `class_airspace` and `sua_airspace` from the Vector Map MBTiles database.
AirspaceScene loadClassAirspace(String mbtilesPath, LatLng center) {
  MbTiles? db;
  try {
    db = MbTiles(mbtilesPath: mbtilesPath);
    final shelves = _readShelves(db, center);
    return AirspaceScene(
      radiusNm: airspaceViewRadiusNm,
      shelves: shelves,
      airports: _airportsOnGround(shelves),
    );
  } catch (_) {
    return const AirspaceScene(
      radiusNm: airspaceViewRadiusNm,
      shelves: [],
      message: 'Could not read the Vector Map.',
    );
  } finally {
    db?.dispose();
  }
}

List<AirspaceShelf> _readShelves(MbTiles db, LatLng center) {
  final lat = center.latitude.clamp(-85.0, 85.0).toDouble();
  final lon = center.longitude;
  final latRad = lat * math.pi / 180.0;
  final cosLat = math.cos(latRad).abs().clamp(0.2, 1.0);
  final dLat = airspaceViewRadiusNm / 60.0;
  final dLon = airspaceViewRadiusNm / (60.0 * cosLat);
  final minX = _tileX(lon - dLon, _airspaceZoom);
  final maxX = _tileX(lon + dLon, _airspaceZoom);
  final minY = _tileY(lat + dLat, _airspaceZoom);
  final maxY = _tileY(lat - dLat, _airspaceZoom);
  if (minX > maxX || minY > maxY) {
    return const [];
  }

  final lonScale = 60.0 * cosLat;
  const latScale = 60.0;
  final shelves = <AirspaceShelf>[];

  for (var x = minX; x <= maxX; x++) {
    for (var y = minY; y <= maxY; y++) {
      final tmsY = (1 << _airspaceZoom) - 1 - y;
      final bytes = db.getTile(z: _airspaceZoom, x: x, y: tmsY);
      if (bytes == null || bytes.isEmpty) {
        continue;
      }
      final tile = VectorTile.fromBytes(bytes: bytes);
      for (final layer in tile.layers) {
        final isClass = layer.name == 'class_airspace';
        final isSua = layer.name == 'sua_airspace';
        if (!isClass && !isSua) {
          continue;
        }
        final extent = layer.extent == 0 ? 4096 : layer.extent;
        for (final feature in layer.features) {
          final props = feature.decodeProperties();
          final String cls;
          final String ident;
          final String sector;
          final double floor;
          final double ceiling;
          final bool unlimited;
          if (isClass) {
            final code = props['CLASS']?.stringValue;
            if (code == null || (code != 'B' && code != 'C' && code != 'D')) {
              continue;
            }
            if (props['EXCLUSION']?.stringValue == '1') {
              continue;
            }
            final parsedFloor = parseAirspaceAltitude(
              props['LOWER_VAL']?.stringValue,
              props['LOWER_CODE']?.stringValue,
              props['LOWER_UOM']?.stringValue,
            );
            final parsedCeiling = parseAirspaceAltitude(
              props['UPPER_VAL']?.stringValue,
              props['UPPER_CODE']?.stringValue,
              props['UPPER_UOM']?.stringValue,
            );
            if (parsedFloor == null || parsedCeiling == null || parsedCeiling <= parsedFloor || parsedCeiling > 20000) {
              continue;
            }
            cls = code;
            ident = airspaceIdent(props['IDENT']?.stringValue);
            sector = props['SECTOR']?.stringValue ?? '';
            floor = parsedFloor;
            ceiling = parsedCeiling;
            unlimited = false;
          } else {
            final type = props['TYPE']?.stringValue;
            if (type != 'RESTRICTED' && type != 'WARNING' && type != 'PROHIBITED' && type != 'MOA') {
              continue;
            }
            final parsedFloor = parseSuaLimit(
              props['LOWER_LIMIT']?.stringValue,
              props['LOWER_UOM']?.stringValue,
              props['LOWER_REF']?.stringValue,
            );
            final parsedCeiling = parseSuaLimit(
              props['UPPER_LIMIT']?.stringValue,
              props['UPPER_UOM']?.stringValue,
              props['UPPER_REF']?.stringValue,
            );
            if (parsedFloor == null || parsedCeiling == null || parsedFloor.feet >= airspaceDisplayCapFt) {
              continue;
            }
            final top = parsedCeiling.unlimited ? airspaceDisplayCapFt : parsedCeiling.feet;
            if (top <= parsedFloor.feet) {
              continue;
            }
            cls = type!;
            final coded = suaDesignator(props['DESIGNATOR']?.stringValue);
            final chart = type == 'MOA' ? suaChartName(props['NAME']?.stringValue) : '';
            ident = chart.isEmpty ? coded : chart;
            sector = '';
            floor = parsedFloor.feet;
            ceiling = top;
            unlimited = parsedCeiling.unlimited;
          }
          final geom = feature.decodeGeometry();
          if (geom == null) {
            continue;
          }
          for (final polygon in _polygonsOf(geom)) {
            final local = <AirspaceRing>[];
            for (final ring in polygon) {
              final prepared = _ringFromTile(
                ring,
                tileX: x,
                tileY: y,
                extent: extent,
                centerLon: lon,
                centerLat: lat,
                lonScale: lonScale,
                latScale: latScale,
              );
              if (prepared != null) {
                local.add(prepared);
              }
            }
            if (local.isEmpty || !_intersectsSquare(local.first.points, airspaceViewRadiusNm)) {
              continue;
            }
            final contains = polygonContains([for (final ring in local) ring.points], 0, 0);
            shelves.add(AirspaceShelf(
              airspaceClass: cls,
              name: props['NAME']?.stringValue ?? '',
              ident: ident,
              sector: sector,
              floorFt: floor,
              ceilingFt: ceiling,
              rings: local,
              containsCenter: contains,
              area: _absArea(local.first.points),
              unlimitedCeiling: unlimited,
            ));
          }
        }
      }
    }
  }

  final seamE = <double>[
    for (var x = minX; x <= maxX + 1; x++) (_tileEdgeLon(x) - lon) * lonScale,
  ];
  final seamN = <double>[
    for (var y = minY; y <= maxY + 1; y++) (_tileEdgeLat(y) - lat) * latScale,
  ];
  _fillIdents(shelves);
  final merged = _mergeShelves(shelves, seamE, seamN);
  _labelShelves(merged);
  return merged;
}

void _fillIdents(List<AirspaceShelf> shelves) {
  final byName = <String, String>{};
  for (final shelf in shelves) {
    if (shelf.ident.isNotEmpty && shelf.name.isNotEmpty) {
      byName.putIfAbsent(shelf.name, () => shelf.ident);
    }
  }
  for (final shelf in shelves) {
    if (shelf.ident.isEmpty) {
      shelf.ident = byName[shelf.name] ?? '';
    }
  }
}

void _labelShelves(List<AirspaceShelf> shelves) {
  final numbered = [
    for (final shelf in shelves)
      if (shelf.area >= 3 || shelf.containsCenter) shelf,
  ];
  numbered.sort((a, b) {
    final byIdent = a.displayIdent.compareTo(b.displayIdent);
    if (byIdent != 0) {
      return byIdent;
    }
    final byFloor = b.floorFt.compareTo(a.floorFt);
    if (byFloor != 0) {
      return byFloor;
    }
    final byCeiling = b.ceilingFt.compareTo(a.ceilingFt);
    if (byCeiling != 0) {
      return byCeiling;
    }
    return a.sector.compareTo(b.sector);
  });
  for (final shelf in numbered) {
    final range = AirspaceShelf.altitudeRange(shelf.floorFt, shelf.ceilingFt, unlimited: shelf.unlimitedCeiling);
    final airport = shelf.airspaceClass == 'B' || shelf.airspaceClass == 'C' || shelf.airspaceClass == 'D';
    shelf.showLabel = true;
    shelf.label = airport || shelf.displayIdent.isEmpty ? range : '${shelf.displayIdent} $range';
  }
}

/// One ground mark per Class B, C, or D airport that has a surface shelf in view.
List<AirspaceAirport> _airportsOnGround(List<AirspaceShelf> shelves) {
  final surface = <String, AirspaceShelf>{};
  for (final shelf in shelves) {
    if (shelf.airspaceClass != 'B' && shelf.airspaceClass != 'C' && shelf.airspaceClass != 'D') {
      continue;
    }
    if (shelf.floorFt > 0 || shelf.ident.isEmpty || shelf.rings.isEmpty) {
      continue;
    }
    final current = surface[shelf.ident];
    if (current == null || shelf.area < current.area) {
      surface[shelf.ident] = shelf;
    }
  }
  final marks = <AirspaceAirport>[];
  for (final shelf in surface.values) {
    var ring = shelf.rings.first.points;
    var ringArea = _absArea(ring);
    for (final candidate in shelf.rings.skip(1)) {
      final area = _absArea(candidate.points);
      if (area > ringArea) {
        ring = candidate.points;
        ringArea = area;
      }
    }
    final at = _centroid(ring);
    if (at == null || at.e.abs() > airspaceViewRadiusNm || at.n.abs() > airspaceViewRadiusNm) {
      continue;
    }
    marks.add(AirspaceAirport(ident: shelf.ident, airspaceClass: shelf.airspaceClass, e: at.e, n: at.n));
  }
  return marks;
}

NmPoint? _centroid(List<NmPoint> ring) {
  var area = 0.0;
  var e = 0.0;
  var n = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final p = ring[i];
    final q = ring[(i + 1) % ring.length];
    final cross = p.e * q.n - q.e * p.n;
    area += cross;
    e += (p.e + q.e) * cross;
    n += (p.n + q.n) * cross;
  }
  if (area.abs() < 1e-8) {
    return null;
  }
  return NmPoint(e / (3 * area), n / (3 * area));
}

List<AirspaceShelf> _mergeShelves(List<AirspaceShelf> parts, List<double> seamE, List<double> seamN) {
  final groups = <String, List<AirspaceShelf>>{};
  for (final shelf in parts) {
    groups.putIfAbsent(shelf.identity, () => []).add(shelf);
  }
  final merged = <AirspaceShelf>[];
  for (final group in groups.values) {
    final input = <AirspaceRing>[for (final shelf in group) ...shelf.rings];
    final inArea = input.fold<double>(0, (sum, ring) => sum + _absArea(ring.points));
    var rings = input.length < 2 ? input : _stitchRings(input, seamE, seamN);
    final outArea = rings.fold<double>(0, (sum, ring) => sum + _absArea(ring.points));
    if (rings.isEmpty || outArea < inArea * 0.85) {
      rings = input;
    }
    final finished = <AirspaceRing>[];
    for (final ring in rings) {
      final done = _finishRing(ring, seamE, seamN);
      if (done != null) {
        finished.add(done);
      }
    }
    if (finished.isEmpty) {
      continue;
    }
    final sample = group.first;
    var area = 0.0;
    for (final ring in finished) {
      area += _signedArea(ring.points);
    }
    merged.add(AirspaceShelf(
      airspaceClass: sample.airspaceClass,
      name: sample.name,
      ident: sample.ident,
      sector: sample.sector,
      floorFt: sample.floorFt,
      ceilingFt: sample.ceilingFt,
      rings: finished,
      containsCenter: polygonContains([for (final ring in finished) ring.points], 0, 0),
      area: area.abs(),
      unlimitedCeiling: sample.unlimitedCeiling,
    ));
  }
  return merged;
}

/// Drop the vector-tile buffer so neighboring tiles meet on one line.
/// Edges that lie on that line are tile cuts, not airspace walls.
AirspaceRing? _ringFromTile(
  List<List<double>> raw, {
  required int tileX,
  required int tileY,
  required int extent,
  required double centerLon,
  required double centerLat,
  required double lonScale,
  required double latScale,
}) {
  final pixels = <NmPoint>[];
  for (final xy in raw) {
    if (xy.length >= 2) {
      pixels.add(NmPoint(xy[0], xy[1]));
    }
  }
  if (pixels.length >= 2 && _dist(pixels.first, pixels.last) < 1e-4) {
    pixels.removeLast();
  }
  if (pixels.length < 3) {
    return null;
  }
  final clipped = clipPolygonRect(pixels, 0, 0, extent.toDouble(), extent.toDouble());
  if (clipped.length < 3) {
    return null;
  }
  final tileCut = <bool>[];
  for (var i = 0; i < clipped.length; i++) {
    tileCut.add(_onTileEdge(clipped[i], clipped[(i + 1) % clipped.length], extent.toDouble()));
  }
  final nm = <NmPoint>[];
  for (final p in clipped) {
    final geo = _pixelToLatLon(tileX, tileY, p.e, p.n, extent);
    nm.add(NmPoint((geo.$1 - centerLon) * lonScale, (geo.$2 - centerLat) * latScale));
  }
  if (_absArea(nm) < 1e-4) {
    return null;
  }
  return AirspaceRing(nm, tileCut);
}

AirspaceRing? _finishRing(AirspaceRing ring, List<double> seamE, List<double> seamN) {
  var next = _simplifyRing(_thinRuns(ring, 300), 0.12);
  final outside = next.points.any((p) => p.e.abs() > airspaceViewRadiusNm || p.n.abs() > airspaceViewRadiusNm);
  if (outside) {
    final view = clipPolygon(next.points, airspaceViewRadiusNm);
    if (view.length < 3) {
      return null;
    }
    next = AirspaceRing(view, List<bool>.filled(view.length, false));
  }
  next = _hideSeams(next, seamE, seamN);
  if (next.points.length < 3 || _absArea(next.points) < 0.05) {
    return null;
  }
  return next;
}

/// Join tile pieces of one shelf so the shared tile edge is not a wall or a gap.
List<AirspaceRing> _stitchRings(List<AirspaceRing> rings, List<double> seamE, List<double> seamN) {
  final segs = <_Seg>[];
  for (final ring in rings) {
    for (var i = 0; i < ring.points.length; i++) {
      final a = _snapSeam(ring.points[i], seamE, seamN);
      final b = _snapSeam(ring.points[(i + 1) % ring.points.length], seamE, seamN);
      if (_dist(a, b) < 1e-4) {
        continue;
      }
      segs.add(_Seg(a, b, ring.hides(i) || _sameSeam(a, b, seamE, seamN)));
    }
  }
  return _walkRings(_cancelShared(_nodeHidden(segs)));
}

bool _onTileEdge(NmPoint a, NmPoint b, double extent) {
  const eps = 1e-3;
  bool near(double v, double edge) => (v - edge).abs() <= eps;
  if (near(a.e, 0) && near(b.e, 0)) return true;
  if (near(a.e, extent) && near(b.e, extent)) return true;
  if (near(a.n, 0) && near(b.n, 0)) return true;
  if (near(a.n, extent) && near(b.n, extent)) return true;
  return false;
}

bool _onViewEdge(NmPoint a, NmPoint b, double limit) {
  const eps = 1e-3;
  bool near(double v, double edge) => (v - edge).abs() <= eps;
  if (near(a.e, -limit) && near(b.e, -limit)) return true;
  if (near(a.e, limit) && near(b.e, limit)) return true;
  if (near(a.n, -limit) && near(b.n, -limit)) return true;
  if (near(a.n, limit) && near(b.n, limit)) return true;
  return false;
}

class _Seg {
  final NmPoint a;
  final NmPoint b;
  final bool hidden;

  const _Seg(this.a, this.b, this.hidden);
}

double _tileEdgeLon(int x) {
  final n = (1 << _airspaceZoom).toDouble();
  return x / n * 360.0 - 180.0;
}

double _tileEdgeLat(int y) {
  final n = (1 << _airspaceZoom).toDouble();
  final merc = math.pi * (1.0 - 2.0 * y / n);
  return math.atan((math.exp(merc) - math.exp(-merc)) / 2.0) * 180.0 / math.pi;
}

const double _seamEpsNm = 0.01;

bool _sameSeam(NmPoint a, NmPoint b, List<double> seamE, List<double> seamN) {
  for (final e in seamE) {
    if ((a.e - e).abs() <= _seamEpsNm && (b.e - e).abs() <= _seamEpsNm) {
      return true;
    }
  }
  for (final n in seamN) {
    if ((a.n - n).abs() <= _seamEpsNm && (b.n - n).abs() <= _seamEpsNm) {
      return true;
    }
  }
  return false;
}

NmPoint _snapSeam(NmPoint p, List<double> seamE, List<double> seamN) {
  var e = p.e;
  var n = p.n;
  var bestE = _seamEpsNm;
  var bestN = _seamEpsNm;
  for (final seam in seamE) {
    final d = (p.e - seam).abs();
    if (d <= bestE) {
      bestE = d;
      e = seam;
    }
  }
  for (final seam in seamN) {
    final d = (p.n - seam).abs();
    if (d <= bestN) {
      bestN = d;
      n = seam;
    }
  }
  return NmPoint(e, n);
}

AirspaceRing _hideSeams(AirspaceRing ring, List<double> seamE, List<double> seamN) {
  final flags = <bool>[];
  for (var i = 0; i < ring.points.length; i++) {
    final a = ring.points[i];
    final b = ring.points[(i + 1) % ring.points.length];
    flags.add(ring.hides(i) || _onViewEdge(a, b, airspaceViewRadiusNm) || _sameSeam(a, b, seamE, seamN));
  }
  return AirspaceRing(ring.points, flags);
}

String _ptKey(NmPoint p) => '${p.e.toStringAsFixed(4)},${p.n.toStringAsFixed(4)}';

List<_Seg> _nodeHidden(List<_Seg> segs) {
  final vertical = <double, List<int>>{};
  final horizontal = <double, List<int>>{};
  for (var i = 0; i < segs.length; i++) {
    final s = segs[i];
    if (!s.hidden) {
      continue;
    }
    if ((s.a.e - s.b.e).abs() <= 1e-6) {
      vertical.putIfAbsent(s.a.e, () => []).add(i);
    } else if ((s.a.n - s.b.n).abs() <= 1e-6) {
      horizontal.putIfAbsent(s.a.n, () => []).add(i);
    }
  }
  final splitAt = List<List<double>>.generate(segs.length, (_) => <double>[]);
  void collect(Map<double, List<int>> lines, bool verticalLine) {
    for (final entry in lines.entries) {
      final coord = entry.key;
      final cuts = <double>{};
      for (final s in segs) {
        final onA = verticalLine ? (s.a.e - coord).abs() <= 1e-6 : (s.a.n - coord).abs() <= 1e-6;
        final onB = verticalLine ? (s.b.e - coord).abs() <= 1e-6 : (s.b.n - coord).abs() <= 1e-6;
        if (onA) {
          cuts.add(verticalLine ? s.a.n : s.a.e);
        }
        if (onB) {
          cuts.add(verticalLine ? s.b.n : s.b.e);
        }
      }
      for (final index in entry.value) {
        final s = segs[index];
        final from = verticalLine ? s.a.n : s.a.e;
        final to = verticalLine ? s.b.n : s.b.e;
        final lo = math.min(from, to);
        final hi = math.max(from, to);
        for (final cut in cuts) {
          if (cut > lo + 1e-4 && cut < hi - 1e-4) {
            splitAt[index].add(cut);
          }
        }
      }
    }
  }

  collect(vertical, true);
  collect(horizontal, false);
  final out = <_Seg>[];
  for (var i = 0; i < segs.length; i++) {
    final s = segs[i];
    final cuts = splitAt[i];
    if (cuts.isEmpty) {
      out.add(s);
      continue;
    }
    cuts.sort();
    final verticalLine = (s.a.e - s.b.e).abs() <= 1e-6;
    final forward = verticalLine ? s.b.n >= s.a.n : s.b.e >= s.a.e;
    final ordered = forward ? cuts : cuts.reversed.toList();
    var prev = verticalLine ? s.a.n : s.a.e;
    void emit(double next) {
      if ((next - prev).abs() < 1e-4) {
        prev = next;
        return;
      }
      final a = verticalLine ? NmPoint(s.a.e, prev) : NmPoint(prev, s.a.n);
      final b = verticalLine ? NmPoint(s.a.e, next) : NmPoint(next, s.a.n);
      out.add(_Seg(a, b, true));
      prev = next;
    }

    for (final cut in ordered) {
      emit(cut);
    }
    emit(verticalLine ? s.b.n : s.b.e);
  }
  return out;
}

List<_Seg> _cancelShared(List<_Seg> segs) {
  final groups = <String, List<_Seg>>{};
  for (final s in segs) {
    final ka = _ptKey(s.a);
    final kb = _ptKey(s.b);
    if (ka == kb) {
      continue;
    }
    if (!s.hidden) {
      groups.putIfAbsent('v$ka>$kb', () => []).add(s);
      continue;
    }
    final undirected = ka.compareTo(kb) <= 0 ? '$ka|$kb' : '$kb|$ka';
    groups.putIfAbsent('h$undirected', () => []).add(s);
  }
  final out = <_Seg>[];
  for (final entry in groups.entries) {
    final list = entry.value;
    if (entry.key.startsWith('v')) {
      out.add(list.first);
      continue;
    }
    var pos = 0;
    var neg = 0;
    _Seg? posSeg;
    _Seg? negSeg;
    for (final s in list) {
      if (_ptKey(s.a).compareTo(_ptKey(s.b)) <= 0) {
        pos++;
        posSeg = s;
      } else {
        neg++;
        negSeg = s;
      }
    }
    if (pos > neg && posSeg != null) {
      out.add(posSeg);
    } else if (neg > pos && negSeg != null) {
      out.add(negSeg);
    }
  }
  return out;
}

double _ccwAngle(NmPoint incoming, NmPoint outgoing) {
  final cross = incoming.e * outgoing.n - incoming.n * outgoing.e;
  final dot = incoming.e * outgoing.e + incoming.n * outgoing.n;
  final ang = math.atan2(cross, dot);
  return ang < 0 ? ang + math.pi * 2 : ang;
}

List<AirspaceRing> _walkRings(List<_Seg> segs) {
  final byStart = <String, List<int>>{};
  for (var i = 0; i < segs.length; i++) {
    byStart.putIfAbsent(_ptKey(segs[i].a), () => []).add(i);
  }
  final used = List<bool>.filled(segs.length, false);
  final rings = <AirspaceRing>[];
  for (var i = 0; i < segs.length; i++) {
    if (used[i]) {
      continue;
    }
    final pts = <NmPoint>[];
    final hide = <bool>[];
    final start = _ptKey(segs[i].a);
    var cur = i;
    var closed = false;
    for (var guard = 0; guard < segs.length + 2; guard++) {
      if (used[cur]) {
        break;
      }
      used[cur] = true;
      final seg = segs[cur];
      pts.add(seg.a);
      hide.add(seg.hidden);
      if (pts.length > 2 && _ptKey(seg.b) == start) {
        closed = true;
        break;
      }
      final nexts = byStart[_ptKey(seg.b)] ?? const <int>[];
      final inDir = NmPoint(seg.b.e - seg.a.e, seg.b.n - seg.a.n);
      var best = -1;
      var bestAng = 1e9;
      for (final j in nexts) {
        if (used[j]) {
          continue;
        }
        final out = segs[j];
        final ang = _ccwAngle(inDir, NmPoint(out.b.e - out.a.e, out.b.n - out.a.n));
        if (ang < bestAng) {
          bestAng = ang;
          best = j;
        }
      }
      if (best < 0) {
        break;
      }
      cur = best;
    }
    if (closed && pts.length >= 3 && _absArea(pts) >= 0.02) {
      rings.add(AirspaceRing(pts, hide));
    }
  }
  return rings;
}

/// Keeps the ends of a long visible run and drops intermediate arc points.
AirspaceRing _thinRuns(AirspaceRing ring, int maxEdges) {
  final pts = ring.points;
  final hide = ring.tileCut;
  if (pts.length <= maxEdges + 1 || hide.length != pts.length) {
    return ring;
  }
  final outPts = <NmPoint>[pts.first];
  final outHide = <bool>[];
  final n = pts.length;
  var i = 0;
  while (i < n) {
    if (i == n - 1) {
      outHide.add(hide[i]);
      break;
    }
    if (hide[i]) {
      outPts.add(pts[i + 1]);
      outHide.add(true);
      i++;
      continue;
    }
    var j = i;
    while (j < n - 1 && !hide[j]) {
      j++;
    }
    final run = j - i;
    if (run <= maxEdges) {
      for (var k = i; k < j; k++) {
        outPts.add(pts[k + 1]);
        outHide.add(false);
      }
    } else {
      final step = (run / maxEdges).ceil();
      var previous = i;
      for (var k = i + step; k < j; k += step) {
        outPts.add(pts[k]);
        outHide.add(false);
        previous = k;
      }
      if (previous != j) {
        outPts.add(pts[j]);
        outHide.add(false);
      }
    }
    i = j;
  }
  if (outHide.length != outPts.length) {
    return ring;
  }
  return AirspaceRing(outPts, outHide);
}

AirspaceRing _simplifyRing(AirspaceRing ring, double epsilon) {
  if (ring.points.length <= 3 || epsilon <= 0 || ring.tileCut.length != ring.points.length) {
    return ring;
  }
  final collapsed = _collapseHidden(ring);
  if (collapsed.points.length <= 3) {
    return collapsed;
  }
  final simplified = _dpRing(
    collapsed.points,
    collapsed.tileCut.sublist(0, collapsed.points.length - 1),
    epsilon,
  );
  return AirspaceRing(simplified.$1, [...simplified.$2, collapsed.tileCut.last]);
}

AirspaceRing _collapseHidden(AirspaceRing ring) {
  final pts = ring.points;
  final hide = ring.tileCut;
  final n = pts.length;
  final outPts = <NmPoint>[pts.first];
  final outHide = <bool>[];
  var i = 0;
  while (i < n) {
    if (i == n - 1) {
      outHide.add(hide[i]);
      break;
    }
    if (!hide[i]) {
      outPts.add(pts[i + 1]);
      outHide.add(false);
      i++;
      continue;
    }
    var j = i;
    while (j < n - 1 && hide[j]) {
      j++;
    }
    outPts.add(pts[j]);
    outHide.add(true);
    i = j;
  }
  return AirspaceRing(outPts, outHide);
}

bool _allHidden(List<bool> hide, int from, int to) {
  for (var k = from; k < to; k++) {
    if (k < 0 || k >= hide.length || !hide[k]) {
      return false;
    }
  }
  return to > from;
}

(List<NmPoint>, List<bool>) _dpRing(List<NmPoint> pts, List<bool> openHide, double epsilon) {
  if (pts.length <= 2) {
    return (pts, openHide);
  }
  var maxD = 0.0;
  var index = 0;
  final a = pts.first;
  final b = pts.last;
  for (var i = 1; i < pts.length - 1; i++) {
    final d = _distToSeg(pts[i], a, b);
    if (d > maxD) {
      maxD = d;
      index = i;
    }
  }
  // A tile cut that passes close to a real boundary must stay on the tile edge.
  // Collapsing the two into one chord draws that chord as a wall (the KPVD wedge).
  final uniform = openHide.isEmpty || openHide.every((flag) => flag == openHide.first);
  final geometric = maxD > epsilon && index > 0;
  if (geometric || !uniform) {
    var splitAt = index;
    if (!geometric) {
      splitAt = 1;
      while (splitAt < openHide.length && openHide[splitAt] == openHide.first) {
        splitAt++;
      }
    }
    if (splitAt > 0 && splitAt < pts.length - 1) {
      final left = _dpRing(pts.sublist(0, splitAt + 1), openHide.sublist(0, splitAt), epsilon);
      final right = _dpRing(pts.sublist(splitAt), openHide.sublist(splitAt), epsilon);
      return (
        [...left.$1.sublist(0, left.$1.length - 1), ...right.$1],
        [...left.$2, ...right.$2],
      );
    }
  }
  return ([a, b], [_allHidden(openHide, 0, openHide.length)]);
}

Iterable<List<List<List<double>>>> _polygonsOf(Geometry geom) sync* {
  if (geom is GeometryPolygon) {
    yield geom.coordinates;
  } else if (geom is GeometryMultiPolygon) {
    for (final polygon in geom.coordinates ?? const <List<List<List<double>>>>[]) {
      yield polygon;
    }
  }
}

int _tileX(double lon, int z) {
  final n = 1 << z;
  return ((lon + 180.0) / 360.0 * n).floor().clamp(0, n - 1);
}

int _tileY(double lat, int z) {
  final n = 1 << z;
  final clamped = lat.clamp(-85.05112878, 85.05112878);
  final rad = clamped * math.pi / 180.0;
  final y = (1.0 - math.log(math.tan(rad) + 1.0 / math.cos(rad)) / math.pi) / 2.0 * n;
  return y.floor().clamp(0, n - 1);
}

(double, double) _pixelToLatLon(int tileX, int tileY, double px, double py, int extent) {
  final n = (1 << _airspaceZoom).toDouble();
  final lon = (tileX + px / extent) / n * 360.0 - 180.0;
  final yNorm = (tileY + py / extent) / n;
  final merc = math.pi * (1.0 - 2.0 * yNorm);
  // Inverse Web Mercator: atan(sinh(merc)).
  final lat = math.atan((math.exp(merc) - math.exp(-merc)) / 2.0) * 180.0 / math.pi;
  return (lon, lat);
}

bool _intersectsSquare(List<NmPoint> ring, double limit) {
  var minE = double.infinity, maxE = -double.infinity;
  var minN = double.infinity, maxN = -double.infinity;
  for (final p in ring) {
    if (p.e < minE) minE = p.e;
    if (p.e > maxE) maxE = p.e;
    if (p.n < minN) minN = p.n;
    if (p.n > maxN) maxN = p.n;
  }
  return maxE >= -limit && minE <= limit && maxN >= -limit && minN <= limit;
}

double _signedArea(List<NmPoint> ring) {
  var sum = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final p = ring[i];
    final q = ring[(i + 1) % ring.length];
    sum += p.e * q.n - q.e * p.n;
  }
  return sum / 2.0;
}

double _absArea(List<NmPoint> ring) => _signedArea(ring).abs();

List<NmPoint> _clipEdge(
  List<NmPoint> input,
  bool Function(NmPoint) inside,
  NmPoint Function(NmPoint, NmPoint) intersect,
) {
  if (input.isEmpty) {
    return input;
  }
  final output = <NmPoint>[];
  var prev = input.last;
  var prevIn = inside(prev);
  for (final cur in input) {
    final curIn = inside(cur);
    if (curIn) {
      if (!prevIn) {
        output.add(intersect(prev, cur));
      }
      output.add(cur);
    } else if (prevIn) {
      output.add(intersect(prev, cur));
    }
    prev = cur;
    prevIn = curIn;
  }
  return output;
}

NmPoint _hitE(NmPoint a, NmPoint b, double e) {
  final de = b.e - a.e;
  final t = de.abs() < 1e-9 ? 0.0 : ((e - a.e) / de).clamp(0.0, 1.0);
  return NmPoint(e, a.n + (b.n - a.n) * t);
}

NmPoint _hitN(NmPoint a, NmPoint b, double n) {
  final dn = b.n - a.n;
  final t = dn.abs() < 1e-9 ? 0.0 : ((n - a.n) / dn).clamp(0.0, 1.0);
  return NmPoint(a.e + (b.e - a.e) * t, n);
}

List<NmPoint> _dedup(List<NmPoint> ring) {
  if (ring.length < 2) {
    return ring.length >= 3 ? ring : const [];
  }
  final out = <NmPoint>[ring.first];
  for (var i = 1; i < ring.length; i++) {
    if (_dist(out.last, ring[i]) > 1e-4) {
      out.add(ring[i]);
    }
  }
  if (out.length >= 2 && _dist(out.first, out.last) < 1e-4) {
    out.removeLast();
  }
  return out.length >= 3 ? out : const [];
}

List<NmPoint> _stride(List<NmPoint> pts, int max) {
  if (pts.length <= max) {
    return pts;
  }
  final step = (pts.length / max).ceil();
  final out = <NmPoint>[];
  for (var i = 0; i < pts.length; i += step) {
    out.add(pts[i]);
  }
  return out;
}

List<NmPoint> _dp(List<NmPoint> pts, double epsilon) {
  if (pts.length <= 2) {
    return pts;
  }
  var maxD = 0.0;
  var index = 0;
  final a = pts.first;
  final b = pts.last;
  for (var i = 1; i < pts.length - 1; i++) {
    final d = _distToSeg(pts[i], a, b);
    if (d > maxD) {
      maxD = d;
      index = i;
    }
  }
  if (maxD > epsilon) {
    final left = _dp(pts.sublist(0, index + 1), epsilon);
    final right = _dp(pts.sublist(index), epsilon);
    return [...left.sublist(0, left.length - 1), ...right];
  }
  return [a, b];
}

double _dist(NmPoint a, NmPoint b) {
  final de = a.e - b.e;
  final dn = a.n - b.n;
  return math.sqrt(de * de + dn * dn);
}

double _distToSeg(NmPoint p, NmPoint a, NmPoint b) {
  final dx = b.e - a.e;
  final dy = b.n - a.n;
  final len2 = dx * dx + dy * dy;
  if (len2 < 1e-12) {
    return _dist(p, a);
  }
  final t = (((p.e - a.e) * dx + (p.n - a.n) * dy) / len2).clamp(0.0, 1.0);
  return _dist(p, NmPoint(a.e + dx * t, a.n + dy * t));
}

bool _ringContains(List<NmPoint> ring, double e, double n) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final pi = ring[i];
    final pj = ring[j];
    final crosses = (pi.n > n) != (pj.n > n);
    if (!crosses || (pj.n - pi.n).abs() < 1e-12) {
      continue;
    }
    final x = (pj.e - pi.e) * (n - pi.n) / (pj.n - pi.n) + pi.e;
    if (e < x) {
      inside = !inside;
    }
  }
  return inside;
}
