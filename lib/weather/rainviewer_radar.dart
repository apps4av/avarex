import 'dart:convert';

import 'package:avaremp/constants.dart';
import 'package:avaremp/utils/app_log.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Fetches the RainViewer weather-maps index and exposes animated global radar
/// frames as flutter_map tile-URL templates.
///
/// RainViewer serves standard {z}/{x}/{y} PNG tiles, so the map renders them
/// with a plain [TileLayer] just like the Iowa Mesonet mosaic — no bitmap
/// decoding or coordinate math. The free public API needs no key and no login.
///
/// API: https://www.rainviewer.com/api/weather-maps-api.html
///   GET https://api.rainviewer.com/public/weather-maps.json
///   -> { host, radar: { past: [ { time, path }, ... ] } }
/// Tile URL: {host}{path}/{size}/{z}/{x}/{y}/{color}/{smooth}_{snow}.png
class RainViewerRadar {
  RainViewerRadar._();
  static final RainViewerRadar instance = RainViewerRadar._();

  static const String _indexUrl =
      'https://api.rainviewer.com/public/weather-maps.json';

  static const String attribution = 'Radar © RainViewer.com';

  // Notifies listeners when a fresh index has been loaded.
  final ValueNotifier<int> change = ValueNotifier<int>(0);

  String _host = '';
  // Ordered oldest -> newest frame base paths (e.g. "/v2/radar/1609401600").
  List<String> _framePaths = const [];
  DateTime? _lastFetch;

  /// Whether at least one radar frame is available to draw.
  bool get hasFrames => _host.isNotEmpty && _framePaths.isNotEmpty;

  /// Number of animation frames currently available.
  int get frameCount => _framePaths.length;

  /// Fetches the latest index. Safe to call repeatedly; it no-ops when the
  /// current data is younger than [minInterval]. Returns true on success.
  Future<bool> refresh(
      {Duration minInterval = const Duration(minutes: 5)}) async {
    final now = DateTime.now();
    if (_lastFetch != null &&
        now.difference(_lastFetch!) < minInterval &&
        hasFrames) {
      return true;
    }
    try {
      final response = await http.get(Uri.parse(_indexUrl));
      if (response.statusCode != 200) {
        AppLog.logMessage('RainViewerRadar.refresh: HTTP ${response.statusCode}');
        return false;
      }
      final Map<String, dynamic> data = jsonDecode(response.body);
      final String host = (data['host'] as String?) ?? '';
      final radar = data['radar'];
      final List<dynamic> past =
          (radar is Map && radar['past'] is List) ? radar['past'] as List : const [];
      final List<String> paths = [];
      for (final frame in past) {
        if (frame is Map && frame['path'] is String) {
          paths.add(frame['path'] as String);
        }
      }
      if (host.isEmpty || paths.isEmpty) {
        AppLog.logMessage('RainViewerRadar.refresh: empty index');
        return false;
      }
      _host = host;
      _framePaths = paths;
      _lastFetch = now;
      change.value++;
      return true;
    } catch (e) {
      AppLog.logMessage('RainViewerRadar.refresh failed: $e');
      return false;
    }
  }

  /// Builds a flutter_map tile URL template for the frame at [frameIndex]
  /// (clamped; negative indexes count from the newest frame, so -1 is latest).
  /// [colorScheme] is a RainViewer color ID (0..8). Returns null when no data.
  ///
  /// The returned string still contains the flutter_map {z}/{x}/{y}
  /// placeholders for [TileLayer.urlTemplate].
  String? tileUrlTemplate({
    int frameIndex = -1,
    int colorScheme = 4,
    int size = 256,
    bool smooth = true,
    bool snow = true,
  }) {
    if (!hasFrames) {
      return null;
    }
    int idx = frameIndex < 0 ? _framePaths.length + frameIndex : frameIndex;
    if (idx < 0) idx = 0;
    if (idx >= _framePaths.length) idx = _framePaths.length - 1;
    final int color = colorScheme < 0
        ? 0
        : (colorScheme >= Constants.rainViewerColorSchemes.length
            ? Constants.rainViewerColorSchemes.length - 1
            : colorScheme);
    final String opts = '${smooth ? 1 : 0}_${snow ? 1 : 0}';
    return '$_host${_framePaths[idx]}/$size/{z}/{x}/{y}/$color/$opts.png';
  }
}
