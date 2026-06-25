
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Helpers for reading files that, on native platforms, live on the local
/// filesystem but on web are served as static assets from the server's serving
/// folder (the same folder that hosts the built web app: charts under `tiles/`,
/// approach plates under `plates/`, CSUP under `afd/`, and the SQLite
/// databases at the root).
///
/// On web there is no filesystem, so paths that the rest of the app builds
/// against [Storage.dataDir] (which is "/" on web) are turned into HTTP URLs
/// resolved relative to the page's base href. That lets a path such as
/// `/plates/KBOS/PLATE.png` be fetched from `<serving-folder>/plates/KBOS/PLATE.png`.
class WebIo {

  /// Convert an app data path (e.g. `/plates/KBOS/FOO.png` or `plates/KBOS/FOO.png`)
  /// into an absolute URL served from the same origin/base href as the web app.
  static Uri resolve(String dataPath) {
    // Strip leading slashes so the path is resolved relative to the app's base
    // href (supports deployment under a sub-path). dataDir is "/" on web, so
    // built paths can contain a single or double leading slash.
    final String rel = dataPath.replaceFirst(RegExp(r'^/+'), '');
    return Uri.base.resolve(rel);
  }

  /// Fetch the bytes for [dataPath] from the serving folder. Returns null on any
  /// error (missing file, network failure, non-200). Web only.
  static Future<Uint8List?> readBytes(String dataPath) async {
    if (!kIsWeb) {
      return null;
    }
    try {
      final http.Response r = await http.get(resolve(dataPath));
      if (r.statusCode == 200) {
        return r.bodyBytes;
      }
    }
    catch (_) {
      // fall through
    }
    return null;
  }
}
