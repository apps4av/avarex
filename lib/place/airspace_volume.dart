import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:mbtiles/mbtiles.dart';
import 'package:sqflite/sqflite.dart';
import 'package:universal_io/io.dart';
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

  /// `2000–4000` is `20-40`. Surface is `00`. Unlimited is `UNL`.
  static String altitudeRange(double floorFt, double ceilingFt, {bool unlimited = false}) =>
      unlimited ? '${altitudeHundreds(floorFt)}-UNL' : '${altitudeHundreds(floorFt)}-${altitudeHundreds(ceilingFt)}';

  /// Hundreds of feet MSL. `2500` is `25`. Surface is `00`.
  static String altitudeHundreds(double ft) => ft <= 0 ? '00' : (ft / 100).round().toString();

  static String shortSector(String sector) {
    final trimmed = sector.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed.replaceFirst(RegExp(r'^AREA\s+'), '');
  }
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
  final dup = <String, int>{};
  for (final shelf in numbered) {
    final key = '${shelf.displayIdent}|${shelf.floorFt}|${shelf.ceilingFt}';
    dup.update(key, (n) => n + 1, ifAbsent: () => 1);
  }
  for (var i = 0; i < numbered.length; i++) {
    final shelf = numbered[i];
    final key = '${shelf.displayIdent}|${shelf.floorFt}|${shelf.ceilingFt}';
    final sector = (dup[key] ?? 0) > 1 ? AirspaceShelf.shortSector(shelf.sector) : '';
    final range = AirspaceShelf.altitudeRange(shelf.floorFt, shelf.ceilingFt, unlimited: shelf.unlimitedCeiling);
    final airport = shelf.airspaceClass == 'B' || shelf.airspaceClass == 'C' || shelf.airspaceClass == 'D';
    shelf.showLabel = true;
    if (airport) {
      shelf.label = sector.isEmpty ? range : '$sector $range';
    } else {
      shelf.label = sector.isEmpty ? '${shelf.displayIdent} $range' : '${shelf.displayIdent} $sector $range';
    }
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
