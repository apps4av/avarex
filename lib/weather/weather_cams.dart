import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// One camera of an FAA WeatherCams site.
class WeatherCamCamera {
  final int cameraId;
  final String name;
  final String direction; // e.g. "North", "SouthWest"
  final double? bearing;
  final bool inMaintenance;
  final bool outOfOrder;
  final int displayOrder;

  const WeatherCamCamera({
    required this.cameraId,
    required this.name,
    required this.direction,
    required this.bearing,
    required this.inMaintenance,
    required this.outOfOrder,
    required this.displayOrder,
  });

  factory WeatherCamCamera.fromJson(Map<String, dynamic> j) {
    return WeatherCamCamera(
      cameraId: (j['cameraId'] as num).toInt(),
      name: (j['cameraName'] ?? '').toString(),
      direction: (j['cameraDirection'] ?? '').toString(),
      bearing: (j['cameraBearing'] as num?)?.toDouble(),
      inMaintenance: j['cameraInMaintenance'] == true,
      outOfOrder: j['cameraOutOfOrder'] == true,
      displayOrder: (j['displayOrder'] as num?)?.toInt() ?? 0,
    );
  }

  /// Human readable label such as "North (Camera 1)".
  String get label {
    if (direction.isEmpty) {
      return name;
    }
    return name.isEmpty ? direction : "$direction ($name)";
  }
}

/// The latest picture of a camera.
class WeatherCamImage {
  final int cameraId;
  final String url;
  final DateTime time;

  const WeatherCamImage({
    required this.cameraId,
    required this.url,
    required this.time,
  });

  factory WeatherCamImage.fromJson(Map<String, dynamic> j) {
    return WeatherCamImage(
      cameraId: (j['cameraId'] as num).toInt(),
      url: j['imageUri'].toString(),
      time: DateTime.parse(j['imageDatetime'].toString()).toUtc(),
    );
  }
}

/// A camera site with its cameras. [images] is filled by
/// [WeatherCams.loadImages], keyed by camera id.
class WeatherCamSite {
  final int siteId;
  final String name;
  final String identifier;
  final String icao;
  final String state;
  final LatLng coordinate;
  final bool inMaintenance;
  final bool active;
  final List<WeatherCamCamera> cameras;
  final Map<int, WeatherCamImage> images = {};

  WeatherCamSite({
    required this.siteId,
    required this.name,
    required this.identifier,
    required this.icao,
    required this.state,
    required this.coordinate,
    required this.inMaintenance,
    required this.active,
    required this.cameras,
  });

  factory WeatherCamSite.fromJson(Map<String, dynamic> j) {
    final List<WeatherCamCamera> cams = [];
    for (final dynamic c in (j['cameras'] as List<dynamic>? ?? const [])) {
      try {
        cams.add(WeatherCamCamera.fromJson(c as Map<String, dynamic>));
      } catch (_) {}
    }
    cams.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return WeatherCamSite(
      siteId: (j['siteId'] as num).toInt(),
      name: (j['siteName'] ?? '').toString(),
      identifier: (j['siteIdentifier'] ?? '').toString().toUpperCase(),
      icao: (j['icao'] ?? '').toString().toUpperCase(),
      state: (j['state'] ?? '').toString(),
      coordinate: LatLng((j['latitude'] as num).toDouble(),
          (j['longitude'] as num).toDouble()),
      inMaintenance: j['siteInMaintenance'] == true,
      active: j['siteActive'] != false,
      cameras: cams,
    );
  }
}

/// Client for the public FAA WeatherCams service (weathercams.faa.gov).
///
/// This is the same unauthenticated JSON API the FAA web page uses. It is not
/// a documented API and refuses requests that have no `Referer`, so one is
/// always sent. Browsers do not let a page set `Referer`, so it is not
/// available on web builds.
class WeatherCams {
  static const String _api = "https://weathercams.faa.gov/api";
  static const Map<String, String> _headers = {
    "Referer": "https://weathercams.faa.gov/cameras/",
    "Accept": "application/json",
  };

  /// Name of the map layer in the layer selector and in `AppSettings.getLayers()`.
  static const String layerName = 'Cameras';

  static const Duration _listTtl = Duration(minutes: 60);
  static const Duration _timeout = Duration(seconds: 15);

  static List<WeatherCamSite>? _sites;
  static DateTime? _sitesTime;
  static Future<List<WeatherCamSite>>? _sitesLoading;

  static bool get available => !kIsWeb;

  /// Parses the `/sites` response body. Sites that are not active or have no
  /// cameras are dropped, since there is nothing to show for them.
  static List<WeatherCamSite> parseSites(String body) {
    final dynamic decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
      throw const FormatException("WeatherCams: unsuccessful response");
    }
    final List<WeatherCamSite> sites = [];
    for (final dynamic s in (decoded['payload'] as List<dynamic>? ?? const [])) {
      try {
        final WeatherCamSite site = WeatherCamSite.fromJson(s as Map<String, dynamic>);
        if (site.active && site.cameras.isNotEmpty) {
          sites.add(site);
        }
      } catch (_) {
        // skip a malformed site, keep the rest
      }
    }
    return sites;
  }

  /// Parses a `/sites/{id}/images` response and keeps the newest image of each
  /// camera, keyed by camera id.
  static Map<int, WeatherCamImage> parseLatestImages(String body) {
    final dynamic decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> || decoded['success'] != true) {
      throw const FormatException("WeatherCams: unsuccessful response");
    }
    final Map<int, WeatherCamImage> latest = {};
    for (final dynamic i in (decoded['payload'] as List<dynamic>? ?? const [])) {
      try {
        final WeatherCamImage image =
            WeatherCamImage.fromJson(i as Map<String, dynamic>);
        final WeatherCamImage? old = latest[image.cameraId];
        if (old == null || image.time.isAfter(old.time)) {
          latest[image.cameraId] = image;
        }
      } catch (_) {}
    }
    return latest;
  }

  /// The camera sites loaded so far, or null before the first load finishes.
  static List<WeatherCamSite>? get cachedSites => _sites;

  /// Loads (and caches for an hour) every camera site. Throws when the list
  /// cannot be fetched and there is no older copy to fall back to.
  static Future<List<WeatherCamSite>> loadSites() async {
    if (!available) {
      return [];
    }
    final List<WeatherCamSite>? cached = _sites;
    final DateTime? time = _sitesTime;
    if (cached != null && time != null && DateTime.now().difference(time) < _listTtl) {
      return cached;
    }
    final Future<List<WeatherCamSite>>? inFlight = _sitesLoading;
    if (inFlight != null) {
      return inFlight;
    }
    final Future<List<WeatherCamSite>> f = () async {
      final http.Response r =
          await http.get(Uri.parse("$_api/sites"), headers: _headers).timeout(_timeout);
      if (r.statusCode != 200) {
        throw http.ClientException("WeatherCams sites: HTTP ${r.statusCode}");
      }
      final List<WeatherCamSite> sites = parseSites(utf8.decode(r.bodyBytes));
      _sites = sites;
      _sitesTime = DateTime.now();
      return sites;
    }();
    _sitesLoading = f;
    try {
      return await f;
    } catch (_) {
      // an old list is better than none
      if (cached != null) {
        return cached;
      }
      rethrow;
    } finally {
      _sitesLoading = null;
    }
  }

  /// Fills [site].images with the newest picture of each of its cameras.
  /// A failure leaves the site without pictures rather than failing the lot.
  static Future<void> loadImages(WeatherCamSite site) async {
    try {
      final http.Response r = await http
          .get(Uri.parse("$_api/sites/${site.siteId}/images"), headers: _headers)
          .timeout(_timeout);
      if (r.statusCode != 200) {
        return;
      }
      site.images
        ..clear()
        ..addAll(parseLatestImages(utf8.decode(r.bodyBytes)));
    } catch (_) {}
  }
}
