// Offline storage + fetch for FlyBrief per-country NOTAM (and obstacle) GeoJSON.
//
// Files are saved under {dataDir}/flybrief/<slug>_notams.geojson so they are
// available offline. Fetch is done in a background isolate. All parsing is
// delegated to the pure FlybriefNotams helpers so this file only does I/O.

import 'dart:isolate';

import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/app_log.dart';
import 'package:avaremp/weather/flybrief_notams.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:universal_io/io.dart';

class FlybriefStore {
  FlybriefStore._();

  static String _dir() => path.join(Storage().dataDir, 'flybrief');

  static String notamPath(FbCountry c) =>
      path.join(_dir(), '${c.slug}_notams.geojson');

  static String obstaclePath(FbCountry c) =>
      path.join(_dir(), '${c.slug}_obstacles.geojson');

  // True if an offline NOTAM file exists for the country.
  static bool hasOffline(FbCountry c) => File(notamPath(c)).existsSync();

  // Downloads and stores the country's NOTAM (and optionally obstacle) GeoJSON
  // for offline use. Returns the parsed NOTAM count, or null on failure.
  static Future<int?> downloadCountry(
    FbCountry c, {
    bool includeObstacles = true,
    void Function(double progress, String message)? onProgress,
  }) async {
    try {
      await Directory(_dir()).create(recursive: true);

      onProgress?.call(0.1, 'Downloading NOTAMs for ${c.path}...');
      final notamBody = await _get(FlybriefNotams.notamUrl(c));
      if (notamBody == null) {
        return null;
      }
      // Validate it parses before persisting.
      final notams = FlybriefNotams.parse(notamBody);
      await File(notamPath(c)).writeAsString(notamBody);

      if (includeObstacles) {
        onProgress?.call(0.6, 'Downloading obstacles for ${c.path}...');
        final obsBody = await _get(FlybriefNotams.obstacleUrl(c));
        if (obsBody != null) {
          await File(obstaclePath(c)).writeAsString(obsBody);
        }
      }
      onProgress?.call(1.0, 'Stored ${notams.length} NOTAMs for ${c.path}.');
      return notams.length;
    } catch (e) {
      AppLog.logMessage('FlybriefStore.downloadCountry failed: $e');
      return null;
    }
  }

  // Loads offline NOTAMs for a country, if present.
  static Future<List<FbNotam>> loadOffline(FbCountry c) async {
    try {
      final f = File(notamPath(c));
      if (!f.existsSync()) return const [];
      return FlybriefNotams.parse(await f.readAsString());
    } catch (e) {
      AppLog.logMessage('FlybriefStore.loadOffline failed: $e');
      return const [];
    }
  }

  // Removes stored offline files for a country.
  static Future<void> removeCountry(FbCountry c) async {
    for (final p in [notamPath(c), obstaclePath(c)]) {
      try {
        final f = File(p);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
  }

  // Returns nearby NOTAMs for a point: offline first, else fetches the country
  // file live (and caches it). Empty when no FlyBrief country covers the point.
  static Future<List<FbNotam>> nearbyForPoint(
    double lat,
    double lon, {
    double radiusNm = FlybriefNotams.defaultRadiusNm,
  }) async {
    final c = FlybriefNotams.forPoint(lat, lon);
    if (c == null) return const [];
    List<FbNotam> all = await loadOffline(c);
    if (all.isEmpty) {
      final body = await _get(FlybriefNotams.notamUrl(c));
      if (body != null) {
        all = FlybriefNotams.parse(body);
        try {
          await Directory(_dir()).create(recursive: true);
          await File(notamPath(c)).writeAsString(body);
        } catch (_) {}
      }
    }
    if (all.isEmpty) return const [];
    return FlybriefNotams.nearby(all, lat, lon, radiusNm: radiusNm);
  }

  // HTTP GET in a background isolate; returns the body or null.
  static Future<String?> _get(Uri uri) async {
    try {
      final http.Response r = await Isolate.run(() => http.get(uri));
      if (r.statusCode != 200) {
        AppLog.logMessage('FlybriefStore GET ${uri.path} -> ${r.statusCode}');
        return null;
      }
      return r.body;
    } catch (e) {
      AppLog.logMessage('FlybriefStore GET failed: $e');
      return null;
    }
  }
}
