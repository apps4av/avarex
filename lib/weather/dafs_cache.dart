import 'dart:async';
import 'dart:math' as math;

import 'package:avaremp/weather/grib2.dart';
import 'package:avaremp/weather/weather_snapshot.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Which hazard a [HazardGrid] holds.
enum Hazard { icing, turbulence }

/// A hazard volume cut out of NOAA's CONUS guidance, on the same kind of grid as the radar.
/// Cell `(level, row, col)` is at `values[(level * cols + row) * cols + col]`. Level 0
/// is centered on [firstLevelFt], and each level above is [levelFt] higher.
///
/// Icing holds the severity code, 0 none, 1 trace, 2 light, 3 moderate, 4 heavy.
/// Turbulence holds the eddy dissipation rate times 100, so 15 is an EDR of 0.15.
class HazardGrid {
  final Hazard hazard;
  final DateTime validTime;
  final double centerLat;
  final double centerLon;
  final double radiusNm;
  final double cellNm;
  final double levelFt;
  final double firstLevelFt;
  final int cols;
  final int levels;
  final Uint8List values;

  HazardGrid({
    required this.hazard,
    required this.validTime,
    required this.centerLat,
    required this.centerLon,
    required this.radiusNm,
    required this.cellNm,
    required this.levelFt,
    required this.firstLevelFt,
    required this.cols,
    required this.levels,
    required this.values,
  });

  /// The highest level with a cell at or above [minValue], in feet, or 0.
  double topFt(int minValue) {
    final slab = cols * cols;
    for (var level = levels - 1; level >= 0; level--) {
      final base = level * slab;
      for (var i = 0; i < slab; i++) {
        if (values[base + i] >= minValue) {
          return firstLevelFt + (level + 1) * levelFt - levelFt / 2;
        }
      }
    }
    return 0;
  }
}

/// Icing and turbulence for the 3D Weather screen, from NOAA's Digital Aviation
/// Forecast System (DAFS) on NOMADS: the In-Flight Icing (IFI) severity and the
/// Graphical Turbulence Guidance (GTG) eddy dissipation rate, both 3 km hourly
/// grids with many altitudes. Only the altitudes shown are downloaded, using the
/// index file next to each forecast, and they are cut down to a small grid here.
class DafsCache extends SnapshotCache {
  DafsCache._(this.hazard);

  static final DafsCache icing = DafsCache._(Hazard.icing);
  static final DafsCache turbulence = DafsCache._(Hazard.turbulence);

  static const String _base = 'https://nomads.ncep.noaa.gov/pub/data/nccf/com/dafs/prod';

  static const double gridRadiusNm = 60;
  static const double cellNm = 2;
  static const double levelFt = 1000;

  /// Altitudes of the 1000 foot levels the grid holds: 1000 to 30,000 ft.
  static const int levelCount = 30;

  /// The guidance is hourly, so a build is good for an hour.
  static const Duration buildLife = Duration(minutes: 60);

  static const double _regridNm = 25;
  static const int _parallel = 2;

  /// Turbulence altitudes downloaded, in feet. The levels between are blended.
  static const List<int> turbulenceFeet = [
    1000, 3000, 6000, 9000, 12000, 15000, 18000, 21000, 24000, 27000, 30000,
  ];

  final Hazard hazard;

  /// Replaced in tests so nothing touches the network. [range] is a `bytes=a-b` header or null.
  @visibleForTesting
  Future<http.Response> Function(Uri uri, {String? range}) getter =
      (uri, {String? range}) => http.get(uri, headers: {
            'User-Agent': 'AvareX',
            if (range != null) 'Range': range,
          }).timeout(const Duration(seconds: 90));

  HazardGrid? _grid;
  DateTime? _builtAt;
  String? _message;
  bool _loading = false;
  int _loaded = 0;
  int _expected = 0;
  Future<void>? _running;

  HazardGrid? get grid => _grid;

  @override
  DateTime? get builtAt => _builtAt;

  @override
  Duration get life => buildLife;

  @override
  bool get loading => _loading;

  @override
  String? get message => _message;

  @override
  bool get hasPicture => _grid != null;

  String get _name => hazard == Hazard.icing ? 'icing' : 'turbulence';

  @override
  String? get progress {
    if (!_loading) {
      return null;
    }
    return _expected > 0
        ? 'Building ${math.min(_loaded + 1, _expected)}/$_expected'
        : 'Finding forecast';
  }

  @override
  bool needsRegrid(double lat, double lon) {
    final grid = _grid;
    if (grid == null) {
      return false;
    }
    final east = (lon - grid.centerLon) * 60 * math.cos(grid.centerLat * math.pi / 180);
    final north = (lat - grid.centerLat) * 60;
    return math.sqrt(east * east + north * north) >= _regridNm;
  }

  @visibleForTesting
  void debugSet(
      {HazardGrid? grid,
      DateTime? builtAt,
      String? message,
      bool loading = false}) {
    _grid = grid;
    _builtAt = builtAt;
    _message = message;
    _loading = loading;
    notifyListeners();
  }

  @override
  Future<void> refresh(double lat, double lon, {bool force = false}) {
    final running = _running;
    if (running != null) {
      return running;
    }
    final future = _refresh(lat, lon).whenComplete(() {
      _running = null;
    });
    _running = future;
    return future;
  }

  Future<void> _refresh(double lat, double lon) async {
    _loading = true;
    _loaded = 0;
    _expected = 0;
    notifyListeners();
    try {
      final found = await _newestIndex();
      if (found == null) {
        _message = 'No $_name forecast found, or no connection';
        return;
      }
      final wanted = pickLevels(found.index, hazard);
      if (wanted.isEmpty) {
        _message = 'The $_name forecast has no levels';
        return;
      }
      _expected = wanted.length;
      notifyListeners();

      final slices = <int, Uint8List>{};
      var next = 0;
      var failed = 0;
      Future<void> worker() async {
        while (next < wanted.length) {
          final level = wanted[next++];
          final slice = await _levelSlice(found.url, level, lat, lon);
          if (slice == null) {
            failed++;
          } else {
            slices[level.feet] = slice;
          }
          _loaded++;
          notifyListeners();
        }
      }

      await Future.wait([for (var i = 0; i < _parallel; i++) worker()]);
      if (slices.isNotEmpty && slices.values.every((slice) => slice.isEmpty)) {
        _message = 'No $_name guidance here: it covers the continental US';
        return;
      }
      // A missing level is bridged from its neighbors, but too many missing is no picture.
      if (slices.length < math.max(2, wanted.length ~/ 2) || failed > wanted.length ~/ 2) {
        _message = 'The $_name download failed';
        return;
      }
      _grid = buildHazardGrid(
        hazard: hazard,
        slices: slices,
        validTime: found.valid,
        centerLat: lat,
        centerLon: lon,
      );
      _builtAt = DateTime.now();
      _message = null;
    } catch (_) {
      _message = 'The $_name forecast is unavailable: check the connection';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// The newest forecast cycle whose index can be read, with the hour nearest to now.
  Future<({String url, DateTime valid, List<DafsLevel> index})?>
      _newestIndex() async {
    final now = DateTime.now().toUtc();
    final target = DateTime.utc(now.year, now.month, now.day, now.hour)
        .add(Duration(hours: now.minute >= 30 ? 1 : 0));
    final kind = hazard == Hazard.icing ? 'ifi' : 'gtg';
    for (var back = 0; back <= 6; back++) {
      final cycle = DateTime.utc(now.year, now.month, now.day, now.hour)
          .subtract(Duration(hours: back));
      var hours = target.difference(cycle).inHours;
      if (hours < 1) {
        hours = 1;
      }
      if (hours > 18) {
        break;
      }
      final url = forecastUrl(cycle, kind, hours);
      final response = await getter(Uri.parse('$url.idx'));
      if (response.statusCode != 200) {
        continue;
      }
      final index = parseDafsIndex(response.body);
      if (index.isNotEmpty) {
        return (url: url, valid: cycle.add(Duration(hours: hours)), index: index);
      }
    }
    return null;
  }

  Future<Uint8List?> _levelSlice(
      String url, DafsLevel level, double lat, double lon) async {
    try {
      final response = await getter(Uri.parse(url),
          range: 'bytes=${level.start}-${level.end == null ? '' : level.end! - 1}');
      if ((response.statusCode != 206 && response.statusCode != 200) ||
          response.bodyBytes.isEmpty) {
        return null;
      }
      var bytes = response.bodyBytes;
      // A server that ignores the range sends the whole file: take our part.
      if (response.statusCode == 200 && bytes.length > (level.end ?? bytes.length) - level.start) {
        bytes = Uint8List.sublistView(
            bytes, level.start, level.end ?? bytes.length);
      }
      return await compute(
        _cutLevel,
        _DafsJob(bytes, lat, lon, hazard == Hazard.icing),
      );
    } catch (_) {
      return null;
    }
  }
}

/// `https://.../dafs.20261031/dafs.t14z.ifi.3km.conus.f001.grib2`
@visibleForTesting
String forecastUrl(DateTime cycle, String kind, int hours) {
  String two(int v) => v.toString().padLeft(2, '0');
  final day = '${cycle.year}${two(cycle.month)}${two(cycle.day)}';
  return '${DafsCache._base}/dafs.$day/dafs.t${two(cycle.hour)}z.$kind.3km.conus.'
      'f${hours.toString().padLeft(3, '0')}.grib2';
}

/// One message in a forecast file, by byte range. [end] is null for the last one.
class DafsLevel {
  final int start;
  final int? end;
  final String parameter;

  /// Level height in meters, NaN for messages that are not at a height above sea level.
  final double meters;

  /// The 1000 foot level this message was chosen for, when it was chosen.
  final int? nominalFeet;

  const DafsLevel(this.start, this.end, this.parameter, this.meters,
      [this.nominalFeet]);

  int get feet => nominalFeet ?? (meters / 0.3048).round();
}

/// Reads a wgrib2 style `.idx` file: `n:offset:d=date:PARAM:level:forecast:`.
@visibleForTesting
List<DafsLevel> parseDafsIndex(String text) {
  final rows = <({int start, String parameter, double meters})>[];
  for (final line in text.split('\n')) {
    final parts = line.split(':');
    if (parts.length < 6) {
      continue;
    }
    final start = int.tryParse(parts[1]);
    if (start == null) {
      continue;
    }
    final match = RegExp(r'^([\d.]+) m above mean sea level').firstMatch(parts[4]);
    rows.add((
      start: start,
      parameter: parts[3],
      meters: match == null ? double.nan : double.parse(match.group(1)!),
    ));
  }
  // The index lists every message in file order, so a message ends where the next begins.
  return [
    for (var i = 0; i < rows.length; i++)
      DafsLevel(rows[i].start, i + 1 < rows.length ? rows[i + 1].start : null,
          rows[i].parameter, rows[i].meters),
  ];
}

/// The messages to download: icing severity every 1000 ft, turbulence at [DafsCache.turbulenceFeet].
@visibleForTesting
List<DafsLevel> pickLevels(List<DafsLevel> index, Hazard hazard) {
  final targets = hazard == Hazard.icing
      ? [for (var k = 1; k <= DafsCache.levelCount; k++) k * 1000]
      : DafsCache.turbulenceFeet;
  final out = <DafsLevel>[];
  for (final feet in targets) {
    final meters = feet * 0.3048;
    DafsLevel? best;
    for (final level in index) {
      final isParameter = hazard == Hazard.icing
          ? level.parameter.contains('parm=37')
          : level.parameter == 'EDPARM';
      if (!isParameter ||
          level.meters.isNaN ||
          (level.meters - meters).abs() > 1.5) {
        continue;
      }
      best = level;
      break;
    }
    if (best != null) {
      out.add(DafsLevel(best.start, best.end, best.parameter, best.meters, feet));
    }
  }
  return out;
}

class _DafsJob {
  final Uint8List bytes;
  final double lat;
  final double lon;
  final bool categories;

  const _DafsJob(this.bytes, this.lat, this.lon, this.categories);
}

Uint8List _cutLevel(_DafsJob job) =>
    cutLevel(job.bytes, job.lat, job.lon, categories: job.categories);

/// One level of the guidance sampled onto the [DafsCache.cellNm] grid around a place.
/// Icing keeps whole severity codes. Turbulence is blended and stored as EDR times 100.
/// Empty when the place is outside the guidance.
@visibleForTesting
Uint8List cutLevel(Uint8List grib, double centerLat, double centerLon,
    {required bool categories}) {
  final messages = readGrib2(grib);
  if (messages.isEmpty) {
    throw const FormatException('No GRIB2 message');
  }
  final message = messages.first;
  if (!message.covers(centerLat, centerLon)) {
    return Uint8List(0);
  }
  const radius = DafsCache.gridRadiusNm;
  const cell = DafsCache.cellNm;
  final cols = (2 * radius / cell).round();
  final cosLat = math.cos(centerLat * math.pi / 180).abs().clamp(0.2, 1.0);
  final out = Uint8List(cols * cols);
  for (var row = 0; row < cols; row++) {
    final north = -radius + (row + 0.5) * cell;
    for (var col = 0; col < cols; col++) {
      final east = -radius + (col + 0.5) * cell;
      final value = message.sample(
        centerLat + north / 60,
        centerLon + east / (60 * cosLat),
        nearest: categories,
      );
      if (value.isNaN) {
        continue;
      }
      out[row * cols + col] = categories
          ? value.round().clamp(0, 4)
          : (value * 100).round().clamp(0, 100);
    }
  }
  return out;
}

/// Puts the downloaded levels on the 1000 foot grid. Icing levels are already there.
/// Turbulence is blended between the levels that were downloaded.
@visibleForTesting
HazardGrid buildHazardGrid({
  required Hazard hazard,
  required Map<int, Uint8List> slices,
  required DateTime validTime,
  required double centerLat,
  required double centerLon,
}) {
  const cols = 60; // 2 * gridRadiusNm / cellNm
  final slab = cols * cols;
  const levels = DafsCache.levelCount;
  final values = Uint8List(levels * slab);
  final feet = slices.keys.toList()..sort();
  for (var level = 0; level < levels; level++) {
    final altitude = (level + 1) * DafsCache.levelFt;
    final exact = slices[altitude.round()];
    if (exact != null) {
      values.setRange(level * slab, (level + 1) * slab, exact);
      continue;
    }
    if (hazard == Hazard.icing || feet.isEmpty) {
      // Severity codes are not blended. A missing level stays clear.
      continue;
    }
    int? below;
    int? above;
    for (final f in feet) {
      if (f <= altitude) {
        below = f;
      } else {
        above ??= f;
      }
    }
    if (below == null && above == null) {
      continue;
    }
    final lower = slices[below ?? above!]!;
    final upper = slices[above ?? below!]!;
    final span = (above ?? below!) - (below ?? above!);
    final t = span == 0 ? 0.0 : (altitude - (below ?? above!)) / span;
    for (var i = 0; i < slab; i++) {
      values[level * slab + i] = (lower[i] * (1 - t) + upper[i] * t).round();
    }
  }
  return HazardGrid(
    hazard: hazard,
    validTime: validTime,
    centerLat: centerLat,
    centerLon: centerLon,
    radiusNm: DafsCache.gridRadiusNm,
    cellNm: DafsCache.cellNm,
    levelFt: DafsCache.levelFt,
    firstLevelFt: DafsCache.levelFt,
    cols: cols,
    levels: levels,
    values: values,
  );
}
