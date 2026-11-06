import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Downloads winds aloft from the AviationWeather.gov GFA forecast and reads
/// them at the winds aloft stations.
///
/// The legacy FD text product (`/api/data/windtemp`) no longer has data for the
/// US, so this uses what the GFA map is drawn from: `/api/data/wind` is numeric,
/// with direction and speed on a lattice, one level and one forecast hour per
/// request. The lattice is read at each station and written as FD wind groups,
/// so the rest of the app keeps working with station reports.
class GfaWinds {

  static const String _host = "https://aviationweather.gov";

  /// Zoom picks the wind lattice spacing: 2^(9 - zoom) * 0.125 degrees. Zoom 5
  /// is 2 degrees, about the spacing of the old FD stations, and a reply is
  /// under 8 KB.
  static const int _zoom = 5;

  /// One box for CONUS, Alaska, Hawaii and Puerto Rico: lat0,lon0,lat1,lon1.
  static const String _bbox = "17,-180,72,-60";

  /// Forecast hours kept by the app, matching the "06H", "12H" and "24H" keys.
  static const List<int> forecastHours = [6, 12, 24];

  static const int _parallel = 12;
  static const Duration _timeout = Duration(seconds: 20);
  static const Map<String, String> _headers = {"User-Agent": "AvareX"};
  static const String _tag = '{"gfa":';

  static const List<int> _levelFeet = [0, 3000, 6000, 9000, 12000, 18000, 24000, 30000, 36000, 42000];

  /// GFA level names for [_levelFeet]: surface, then hundreds of feet.
  static final List<String> _levelNames = [
    for (final int feet in _levelFeet) feet == 0 ? "sfc" : (feet ~/ 100).toString().padLeft(3, "0"),
  ];

  // ---- download -----------------------------------------------------------

  /// Downloads in a background isolate and reads the winds at [stations]. [have]
  /// maps a forecast hour to the model run already held for it, so a run that has
  /// not changed is not fetched again.
  ///
  /// Each element is JSON: the winds at the stations for a new run
  /// (`{"gfa":1,"fore":6,"run":"...","s":{"BOS":["2720",...]}}`), or a note
  /// `{"gfa":0,"fore":6}` that the held one is still the newest. Stations are
  /// given as id, latitude and longitude. Groups are 3, 6, 9, 12, 18, 24, 30,
  /// 34 and 39 thousand feet.
  static Future<List<Uint8List>> fetch(List<(String, double, double)> stations, Map<int, String> have) {
    return Isolate.run(() => _fetch(DateTime.now().toUtc(), stations, have));
  }

  static bool isGfa(Uint8List data) {
    if (data.length < _tag.length) {
      return false;
    }
    for (int i = 0; i < _tag.length; i++) {
      if (data[i] != _tag.codeUnitAt(i)) {
        return false;
      }
    }
    return true;
  }

  static Future<List<Uint8List>> _fetch(DateTime now, List<(String, double, double)> stations, Map<int, String> have) async {
    final http.Client client = http.Client();
    try {
      final DateTime? cycle = await _latestCycle(client, now);
      if (cycle == null) {
        return [];
      }
      final List<Uint8List> out = [];
      final Map<int, _Slot> slots = {};

      // Settle which run each forecast hour comes from with the first request.
      await Future.wait(forecastHours.map((int fore) async {
        for (final _Run run in _candidates(cycle, fore)) {
          if (have[fore] == run.label) {
            out.add(Uint8List.fromList(utf8.encode('${_tag}0,"fore":$fore}'))); // already current
            return;
          }
          final Uint8List? body = await _get(client, run.windUri(0));
          if (body != null) {
            slots[fore] = _Slot(run)..winds[0] = body;
            return;
          }
        }
      }));

      final List<Future<void> Function()> tasks = [];
      for (final _Slot slot in slots.values) {
        for (int level = 0; level < _levelNames.length; level++) {
          if (level > 0) {
            tasks.add(() async {
              final Uint8List? body = await _get(client, slot.run.windUri(level));
              if (body != null) {
                slot.winds[level] = body;
              }
            });
          }
        }
      }
      await _runPool(tasks, _parallel);

      for (final MapEntry<int, _Slot> e in slots.entries) {
        final Uint8List? built = build(e.key, e.value.run.label, [for (int l = 0; l < _levelNames.length; l++) e.value.winds[l]], stations);
        if (built != null) {
          out.add(built);
        }
      }
      return out;
    }
    finally {
      client.close();
    }
  }

  /// Newest hourly GFA run that has been published.
  static Future<DateTime?> _latestCycle(http.Client client, DateTime now) async {
    final Uint8List? body = await _get(client, Uri.parse("$_host/api/info/gfa?date=${now.millisecondsSinceEpoch ~/ 1000}"));
    if (body == null) {
      return null;
    }
    try {
      final String? datim = (jsonDecode(utf8.decode(body)) as Map<String, dynamic>)["datim"] as String?; // 20261105_23
      if (datim == null || datim.length < 11) {
        return null;
      }
      return DateTime.utc(
          int.parse(datim.substring(0, 4)),
          int.parse(datim.substring(4, 6)),
          int.parse(datim.substring(6, 8)),
          int.parse(datim.substring(9, 11)));
    }
    catch (e) {
      return null;
    }
  }

  /// Runs that can supply [fore] hours after [cycle], best first.
  static List<_Run> _candidates(DateTime cycle, int fore) {
    if (fore <= 18) {
      return [_Run(cycle, fore)]; // every hourly run goes out 18 hours
    }
    // Past 18 hours only the 00Z and 12Z runs have data, at 24, 36 and 48 hours.
    // The newest of them may not be complete yet, so also offer the one before.
    final DateTime target = cycle.add(Duration(hours: fore));
    final DateTime newest = DateTime.utc(cycle.year, cycle.month, cycle.day, cycle.hour < 12 ? 0 : 12);
    final List<_Run> runs = [];
    for (int i = 0; i < 2; i++) {
      final DateTime run = newest.subtract(Duration(hours: 12 * i));
      int best = 24;
      for (final int step in const [24, 36, 48]) {
        final int d = run.add(Duration(hours: step)).difference(target).inMinutes.abs();
        if (d < run.add(Duration(hours: best)).difference(target).inMinutes.abs()) {
          best = step;
        }
      }
      runs.add(_Run(run, best));
    }
    return runs;
  }

  /// A reply body, or null if the item is not published or the server failed twice.
  static Future<Uint8List?> _get(http.Client client, Uri uri) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final http.Response r = await client.get(uri, headers: _headers).timeout(_timeout);
        if (r.statusCode == 200) {
          return r.bodyBytes;
        }
        if (r.statusCode == 204 || r.statusCode == 400 || r.statusCode == 404) {
          return null; // not published, retrying will not help
        }
      }
      catch (e) {
        // timeout or connection trouble, try once more
      }
    }
    return null;
  }

  static Future<void> _runPool(List<Future<void> Function()> tasks, int workers) async {
    int next = 0;
    Future<void> worker() async {
      while (next < tasks.length) {
        final Future<void> Function() task = tasks[next++];
        await task();
      }
    }
    await Future.wait(List.generate(workers, (_) => worker()));
  }

  // ---- build the grid -----------------------------------------------------

  /// Winds at [stations] from the wind replies of every level (see [_levelNames]),
  /// as the JSON described at [fetch]. Null if there is no wind at all.
  static Uint8List? build(int fore, String run, List<Uint8List?> bodies, List<(String, double, double)> stations) {
    final List<List<({double lat, double lon, int packed})>> points = [
      for (int l = 0; l < _levelNames.length; l++) _windPoints(l < bodies.length ? bodies[l] : null),
    ];
    final List<double> lats = _distinct([for (final p in points) for (final q in p) q.lat]);
    final List<double> lons = _distinct([for (final p in points) for (final q in p) q.lon]);
    if (lats.isEmpty || lons.isEmpty) {
      return null;
    }
    final _Lattice lattice = _Lattice(points, lats, lons);

    final Map<String, List<String>> out = {};
    for (final (String id, double lat, double lon) in stations) {
      final List<(double, double)?> uv = [for (int l = 0; l < _levelNames.length; l++) lattice.uv(l, lat, lon)];
      if (uv.skip(1).every(((double, double)? w) => w == null)) {
        continue; // outside the forecast
      }
      String code((double, double)? w) => w == null ? "" : encodeWind(w.$1, w.$2);
      out[id] = [
        for (int l = 1; l <= 7; l++) code(uv[l]),                       // 3000 to 30000 ft
        code(_blend(uv[7], uv[8], (34000 - 30000) / 6000)),             // 34000 ft
        code(_blend(uv[8], uv[9], (39000 - 36000) / 6000)),             // 39000 ft
      ];
    }
    if (out.isEmpty) {
      return null;
    }
    return Uint8List.fromList(utf8.encode(jsonEncode({"gfa": 1, "fore": fore, "run": run, "s": out})));
  }

  static (double, double)? _blend((double, double)? a, (double, double)? b, double t) {
    if (a == null) {
      return b;
    }
    if (b == null) {
      return a;
    }
    return (a.$1 + (b.$1 - a.$1) * t, a.$2 + (b.$2 - a.$2) * t);
  }

  /// FD wind group from east and north components in knots, the way the air
  /// moves: direction it comes from in tens of degrees then speed, 9900 under
  /// 5 knots, and 50 added to the direction at 100 knots or more.
  static String encodeWind(double u, double v) {
    final double speed = math.sqrt(u * u + v * v);
    if (speed < 4.5) {
      return "9900";
    }
    double degrees = math.atan2(-u, -v) * 180 / math.pi;
    if (degrees < 0) {
      degrees += 360;
    }
    int tens = (degrees / 10).round() % 36;
    if (tens == 0) {
      tens = 36;
    }
    int knots = speed.round();
    if (knots >= 100) {
      tens += 50;
      knots = math.min(knots - 100, 99);
    }
    return "${tens.toString().padLeft(2, "0")}${knots.toString().padLeft(2, "0")}";
  }

  static List<({double lat, double lon, int packed})> _windPoints(Uint8List? body) {
    final List<({double lat, double lon, int packed})> out = [];
    if (body == null) {
      return out;
    }
    try {
      final Map<String, dynamic> collection = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      for (final dynamic feature in collection["features"] as List<dynamic>) {
        final Map<String, dynamic> f = feature as Map<String, dynamic>;
        final dynamic coordinates = (f["geometry"] as Map<String, dynamic>)["coordinates"];
        final Map<String, dynamic> properties = f["properties"] as Map<String, dynamic>;
        final dynamic dir = properties["wdir"];
        final dynamic speed = properties["wspd"];
        if (coordinates is! List || dir is! num || speed is! num) {
          continue;
        }
        final int d = dir.round().clamp(0, 360);
        final int s = speed.round().clamp(0, 999);
        out.add((lat: (coordinates[1] as num).toDouble(), lon: (coordinates[0] as num).toDouble(), packed: d * 1000 + s));
      }
    }
    catch (e) {
      return [];
    }
    return out;
  }

  static List<double> _distinct(Iterable<double> values) => (values.toSet().toList()..sort());

  /// Spacing of a sorted lattice axis: the smallest gap between neighbors.
  static double _spacing(List<double> sorted) {
    double gap = 0;
    for (int i = 1; i < sorted.length; i++) {
      final double d = sorted[i] - sorted[i - 1];
      if (gap == 0 || d < gap) {
        gap = d;
      }
    }
    return gap == 0 ? 2.0 : gap;
  }
}

class _Run {
  final String dref; // yyyymmdd
  final String tref; // hh
  final String fhr;
  _Run(DateTime run, int fhr)
      : dref = "${run.year.toString().padLeft(4, "0")}${run.month.toString().padLeft(2, "0")}${run.day.toString().padLeft(2, "0")}",
        tref = run.hour.toString().padLeft(2, "0"),
        fhr = fhr.toString().padLeft(2, "0");

  /// Names this run and forecast hour, like "20261106_00_F06".
  String get label => "${dref}_${tref}_F$fhr";

  Uri windUri(int level) => Uri.parse("${GfaWinds._host}/api/data/wind").replace(queryParameters: {
        "model": "gfaak",
        "level": GfaWinds._levelNames[level],
        "bbox": GfaWinds._bbox,
        "zoom": "${GfaWinds._zoom}",
        "density": "0",
        "wrap": "true",
        "dref": dref,
        "tref": tref,
        "fhr": fhr,
      });
}

class _Slot {
  final _Run run;
  final Map<int, Uint8List> winds = {}; // by level index
  _Slot(this.run);
}

/// Wind on the regular lattice the GFA reply is given on, readable anywhere inside it.
class _Lattice {
  final double lat0;
  final double lon0;
  final double dLat;
  final double dLon;
  final int rows;
  final int cols;
  final List<Int32List> wind = []; // per level, row by row: direction * 1000 + knots, or -1

  _Lattice(List<List<({double lat, double lon, int packed})>> points, List<double> lats, List<double> lons)
      : lat0 = lats.first,
        lon0 = lons.first,
        dLat = GfaWinds._spacing(lats),
        dLon = GfaWinds._spacing(lons),
        rows = ((lats.last - lats.first) / GfaWinds._spacing(lats)).round() + 1,
        cols = ((lons.last - lons.first) / GfaWinds._spacing(lons)).round() + 1 {
    for (final List<({double lat, double lon, int packed})> level in points) {
      final Int32List w = Int32List(rows * cols)..fillRange(0, rows * cols, -1);
      for (final p in level) {
        final int i = ((p.lat - lat0) / dLat).round();
        final int j = ((p.lon - lon0) / dLon).round();
        if (i >= 0 && j >= 0 && i < rows && j < cols) {
          w[i * cols + j] = p.packed;
        }
      }
      wind.add(w);
    }
  }

  /// East and north wind in knots (toward which the air moves), or null where
  /// the lattice has no data around the point.
  (double, double)? uv(int level, double lat, double lon) {
    final double fi = (lat - lat0) / dLat;
    final double fj = (lon - lon0) / dLon;
    final int i0 = fi.floor();
    final int j0 = fj.floor();
    final double a = fi - i0;
    final double b = fj - j0;
    double u = 0, v = 0, weight = 0;
    for (int di = 0; di < 2; di++) {
      for (int dj = 0; dj < 2; dj++) {
        final int i = i0 + di;
        final int j = j0 + dj;
        if (i < 0 || j < 0 || i >= rows || j >= cols) {
          continue;
        }
        final double w = (di == 0 ? 1 - a : a) * (dj == 0 ? 1 - b : b);
        final int packed = wind[level][i * cols + j];
        if (w <= 0 || packed < 0) {
          continue;
        }
        final double radians = (packed ~/ 1000) * math.pi / 180;
        final double knots = (packed % 1000).toDouble();
        u += -knots * math.sin(radians) * w;
        v += -knots * math.cos(radians) * w;
        weight += w;
      }
    }
    return weight < 0.5 ? null : (u / weight, v / weight);
  }
}
