// On-device terrain (elevation) tile downloader for a country/region.
//
// Fetches open AWS Terrain Tiles, transcodes them to AvareX's elevation-tile
// format (see terrain_transcode.dart) and writes them to
//   {dataDir}/tiles/6/{z}/{x}/{y}.png
// so the existing terrain profile, elevation readout and GPWS work offline
// outside the US. Nothing is bundled in the app; tiles are built on device for
// the chosen country only.

import 'dart:async';
import 'dart:isolate';

import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/app_log.dart';
import 'package:avaremp/weather/flybrief_notams.dart' show FbCountry, FlybriefNotams;
import 'package:avaremp/weather/terrain_transcode.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:universal_io/io.dart';

class TerrainDownloadManager {
  bool _cancel = false;

  void cancel() => _cancel = true;

  // Estimated download bytes for a country (terrarium tiles average ~136 KB).
  static int estimatedBytes(FbCountry c) =>
      TerrainTranscode.countTilesForBounds(
          c.minLat, c.maxLat, c.minLon, c.maxLon) *
      136 *
      1024;

  static int tileCount(FbCountry c) => TerrainTranscode.countTilesForBounds(
      c.minLat, c.maxLat, c.minLon, c.maxLon);

  static String _tilePath(String dataDir, TerrainTile t) => path.join(
      dataDir, 'tiles', '6', '${t.z}', '${t.x}', '${t.yTms}.png');

  // Whether any terrain tiles are already present for the country (z10 sample).
  static bool hasSome(FbCountry c) {
    final dataDir = Storage().dataDir;
    final tiles = TerrainTranscode.tilesForBounds(
        c.minLat, c.maxLat, c.minLon, c.maxLon,
        minZoom: kTerrainMaxZoom, maxZoom: kTerrainMaxZoom);
    for (final t in tiles.take(20)) {
      if (File(_tilePath(dataDir, t)).existsSync()) return true;
    }
    return false;
  }

  // Downloads and transcodes all terrain tiles for the country. Calls
  // [onProgress] with (0..1, message). Skips tiles already on disk. Returns the
  // number of tiles written, or null if cancelled/failed before completion.
  Future<int?> download(
    FbCountry c, {
    void Function(double progress, String message)? onProgress,
  }) async {
    _cancel = false;
    final dataDir = Storage().dataDir;
    final tiles = TerrainTranscode.tilesForBounds(
        c.minLat, c.maxLat, c.minLon, c.maxLon);
    final total = tiles.length;
    var done = 0;
    var written = 0;
    var lastReport = 0.0;

    onProgress?.call(0, 'Preparing $total terrain tiles for ${c.path}...');

    // Bounded concurrency to keep memory/network sane.
    const int concurrency = 6;
    var index = 0;

    Future<void> worker() async {
      while (true) {
        if (_cancel) return;
        final int i;
        if (index >= tiles.length) return;
        i = index++;
        final t = tiles[i];
        final outPath = _tilePath(dataDir, t);
        try {
          final f = File(outPath);
          if (!f.existsSync()) {
            final bytes = await _fetchAndTranscode(t);
            if (bytes != null) {
              await Directory(path.dirname(outPath)).create(recursive: true);
              await f.writeAsBytes(bytes, flush: false);
              written++;
            }
          } else {
            written++; // already present counts as available
          }
        } catch (e) {
          AppLog.logMessage('Terrain tile $t failed: $e');
        }
        done++;
        final p = done / total;
        if (p - lastReport >= 0.01 || done == total) {
          lastReport = p;
          onProgress?.call(
              p * 0.99, 'Building terrain ${(p * 100).toStringAsFixed(0)}% '
              '($done/$total)...');
        }
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));

    if (_cancel) {
      onProgress?.call(lastReport, 'Cancelled after $written tiles.');
      return null;
    }
    onProgress?.call(1, 'Installed $written terrain tiles for ${c.path}.');
    return written;
  }

  // Fetches a terrarium tile and transcodes it in a background isolate.
  static Future<List<int>?> _fetchAndTranscode(TerrainTile t) async {
    final uri = TerrainTranscode.terrariumUrl(t.z, t.x, t.yXyz);
    return Isolate.run(() async {
      try {
        final r = await http.get(uri);
        if (r.statusCode != 200) return null;
        return TerrainTranscode.transcodeTerrarium(r.bodyBytes);
      } catch (_) {
        return null;
      }
    });
  }

  // Removes downloaded terrain tiles for a country (best-effort).
  static Future<int> remove(FbCountry c) async {
    final dataDir = Storage().dataDir;
    final tiles = TerrainTranscode.tilesForBounds(
        c.minLat, c.maxLat, c.minLon, c.maxLon);
    var removed = 0;
    for (final t in tiles) {
      try {
        final f = File(_tilePath(dataDir, t));
        if (f.existsSync()) {
          await f.delete();
          removed++;
        }
      } catch (_) {}
    }
    return removed;
  }

  // Convenience: the FlyBrief country under a point (shares the bbox table).
  static FbCountry? countryForPoint(double lat, double lon) =>
      FlybriefNotams.forPoint(lat, lon);
}
