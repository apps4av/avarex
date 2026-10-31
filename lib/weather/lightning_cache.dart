import 'dart:async';
import 'dart:math' as math;

import 'package:avaremp/weather/hdf5_lite.dart';
import 'package:avaremp/weather/weather_snapshot.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// One lightning flash seen from space. The GOES lightning mapper reports where a
/// flash is and when, not how high, so there is no altitude.
class LightningFlash {
  final double lat;
  final double lon;
  final DateTime time;

  const LightningFlash(this.lat, this.lon, this.time);
}

/// Lightning for the 3D Weather screen: the last [window] of flashes from the GOES
/// Geostationary Lightning Mapper, read straight from NOAA's public AWS bucket and
/// decoded on this device. Flashes are kept for [buildLife], then the layer must be
/// built again.
class LightningCache extends SnapshotCache {
  LightningCache._();

  static final LightningCache instance = LightningCache._();

  /// How far back flashes are shown.
  static const Duration window = Duration(minutes: 10);

  static const Duration buildLife = Duration(minutes: 10);

  /// Flashes farther than this from the build point are dropped. The grid used by
  /// the other layers is 60 NM, and this keeps a margin so a short drift still shows them.
  static const double radiusNm = 75;

  /// How far the view center may drift from the build point before a rebuild.
  static const double _regridNm = 25;

  /// Files fetched at once.
  static const int _parallel = 6;

  /// Replaced in tests so nothing touches the network.
  @visibleForTesting
  Future<http.Response> Function(Uri uri) getter = (uri) =>
      http.get(uri, headers: {'User-Agent': 'AvareX'}).timeout(
          const Duration(seconds: 60));

  List<LightningFlash> _flashes = const [];
  DateTime? _builtAt;
  double? _centerLat;
  double? _centerLon;
  String? _satellite;
  String? _message;
  bool _loading = false;
  int _loaded = 0;
  int _expected = 0;
  Future<void>? _running;

  /// Oldest first.
  List<LightningFlash> get flashes => _flashes;

  /// The GOES satellite the flashes came from, such as `GOES-19`.
  String? get satellite => _satellite;

  @override
  DateTime? get builtAt => _builtAt;

  @override
  Duration get life => buildLife;

  @override
  bool get loading => _loading;

  @override
  String? get message => _message;

  @override
  bool get hasPicture => _builtAt != null;

  @override
  String? get progress {
    if (!_loading) {
      return null;
    }
    return _expected > 0
        ? 'Building ${math.min(_loaded + 1, _expected)}/$_expected'
        : 'Finding flashes';
  }

  @override
  bool needsRegrid(double lat, double lon) {
    final cLat = _centerLat;
    final cLon = _centerLon;
    if (cLat == null || cLon == null || _builtAt == null) {
      return false;
    }
    final east = (lon - cLon) * 60 * math.cos(cLat * math.pi / 180);
    final north = (lat - cLat) * 60;
    return math.sqrt(east * east + north * north) >= _regridNm;
  }

  @visibleForTesting
  void debugSet(
      {List<LightningFlash>? flashes,
      DateTime? builtAt,
      String? message,
      bool loading = false,
      double? lat,
      double? lon}) {
    _flashes = flashes ?? const [];
    _builtAt = builtAt;
    _message = message;
    _loading = loading;
    _centerLat = lat;
    _centerLon = lon;
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
      final satellite = satelliteFor(lon);
      final now = DateTime.now().toUtc();
      final since = now.subtract(window);
      final keys = <String>[];
      var listed = false;
      for (final hour in _hours(since, now)) {
        final prefix = 'GLM-L2-LCFA/${hour.year}/${_three(_dayOfYear(hour))}/'
            '${_two(hour.hour)}/';
        final response = await getter(Uri.parse(
            'https://${satellite.bucket}.s3.amazonaws.com/?list-type=2&prefix=$prefix'));
        if (response.statusCode == 200) {
          listed = true;
          keys.addAll(glmKeys(response.body, since));
        }
      }
      if (!listed) {
        _message = 'Lightning unavailable: check the connection';
        return;
      }
      keys.sort();
      _expected = keys.length;
      notifyListeners();

      final found = <LightningFlash>[];
      var failed = 0;
      var next = 0;
      Future<void> worker() async {
        while (next < keys.length) {
          final key = keys[next++];
          final flashes = await _flashesIn(satellite.bucket, key, lat, lon);
          if (flashes == null) {
            failed++;
          } else {
            found.addAll(flashes);
          }
          _loaded++;
          notifyListeners();
        }
      }

      await Future.wait([
        for (var i = 0; i < _parallel; i++) worker(),
      ]);
      if (keys.isNotEmpty && failed == keys.length) {
        _message = 'Lightning download failed';
        return;
      }
      found.sort((a, b) => a.time.compareTo(b.time));
      _flashes = found;
      _satellite = satellite.name;
      _centerLat = lat;
      _centerLon = lon;
      _builtAt = DateTime.now();
      _message = null;
    } catch (_) {
      _message = 'Lightning unavailable: check the connection';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<List<LightningFlash>?> _flashesIn(
      String bucket, String key, double lat, double lon) async {
    try {
      final response = await getter(Uri.parse('https://$bucket.s3.amazonaws.com/$key'));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        return null;
      }
      final time = glmKeyTime(key);
      if (time == null) {
        return null;
      }
      final found = await compute(
        _decode,
        _GlmJob(response.bodyBytes, lat, lon),
      );
      return [
        for (var i = 0; i < found.length; i += 2)
          LightningFlash(found[i], found[i + 1], time),
      ];
    } catch (_) {
      return null;
    }
  }

  static Iterable<DateTime> _hours(DateTime from, DateTime to) sync* {
    var hour = DateTime.utc(from.year, from.month, from.day, from.hour);
    while (!hour.isAfter(to)) {
      yield hour;
      hour = hour.add(const Duration(hours: 1));
    }
  }

  static int _dayOfYear(DateTime t) =>
      t.difference(DateTime.utc(t.year)).inDays + 1;

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String _three(int v) => v.toString().padLeft(3, '0');
}

/// The GOES satellite whose lightning mapper covers [lon]: GOES-East over the
/// Americas and the Atlantic, GOES-West over the Pacific and the western states.
@visibleForTesting
({String name, String bucket}) satelliteFor(double lon) {
  return lon >= -105
      ? (name: 'GOES-19', bucket: 'noaa-goes19')
      : (name: 'GOES-18', bucket: 'noaa-goes18');
}

/// Keys of lightning files in an S3 listing that start at or after [since].
@visibleForTesting
List<String> glmKeys(String listingXml, DateTime since) {
  final keys = <String>[];
  for (final element in XmlDocument.parse(listingXml).findAllElements('Key')) {
    final key = element.innerText;
    final time = glmKeyTime(key);
    if (time != null && !time.isBefore(since)) {
      keys.add(key);
    }
  }
  return keys;
}

/// Start time encoded in `OR_GLM-L2-LCFA_G19_s20263041500000_e....nc`.
@visibleForTesting
DateTime? glmKeyTime(String key) {
  final match =
      RegExp(r'_s(\d{4})(\d{3})(\d{2})(\d{2})(\d{2})\d_e').firstMatch(key);
  if (match == null) {
    return null;
  }
  final v = [for (var i = 1; i <= 5; i++) int.parse(match.group(i)!)];
  return DateTime.utc(v[0]).add(Duration(
      days: v[1] - 1, hours: v[2], minutes: v[3], seconds: v[4]));
}

class _GlmJob {
  final Uint8List bytes;
  final double lat;
  final double lon;

  const _GlmJob(this.bytes, this.lat, this.lon);
}

/// Latitude and longitude pairs of the flashes inside the radius, flat.
@visibleForTesting
List<double> decodeGlmFlashes(Uint8List bytes, double lat, double lon,
    {double radiusNm = LightningCache.radiusNm}) {
  final file = Hdf5Lite(bytes);
  final lats = file.vector('flash_lat');
  final lons = file.vector('flash_lon');
  if (lats == null || lons == null || lats.length != lons.length) {
    throw const FormatException('Lightning file has no flashes list');
  }
  final cosLat = math.cos(lat * math.pi / 180).abs().clamp(0.2, 1.0);
  final out = <double>[];
  for (var i = 0; i < lats.length; i++) {
    final north = (lats[i] - lat) * 60;
    final east = (lons[i] - lon) * 60 * cosLat;
    if (north * north + east * east <= radiusNm * radiusNm) {
      out
        ..add(lats[i])
        ..add(lons[i]);
    }
  }
  return out;
}

List<double> _decode(_GlmJob job) =>
    decodeGlmFlashes(job.bytes, job.lat, job.lon);
