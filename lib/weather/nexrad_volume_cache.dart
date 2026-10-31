import 'dart:async';
import 'dart:math' as math;
import 'package:avaremp/weather/nexrad_level2.dart';
import 'package:avaremp/weather/nexrad_sites.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// Decoded 3D radar for the 3D view, a loop of the last half hour. Level II volumes
/// come straight from the free NOAA archive on AWS (`unidata-nexrad-level2`), are
/// decoded on this device and cut down to small grids, so no server of ours is involved.
class NexradVolumeCache extends ChangeNotifier {
  NexradVolumeCache._();

  static final NexradVolumeCache instance = NexradVolumeCache._();

  static const String _bucket = 'https://unidata-nexrad-level2.s3.amazonaws.com';

  /// Grid half-width. The 3D view shows 25 NM, the rest lets the aircraft move
  /// without a reload.
  static const double gridRadiusNm = 60;

  /// How far the view center may drift from the grid center before a rebuild.
  static const double _regridNm = 30;

  /// A radar with no volume newer than this is treated as offline.
  static const Duration _maxAge = Duration(minutes: 90);

  /// Length of the loop, back from the newest volume.
  static const Duration loopLength = Duration(minutes: 30);

  /// A second radar's volume this close in time is paired with the first one's.
  static const Duration _pairWindow = Duration(minutes: 8);

  /// How long a build stays on screen. After this the radar must be built again.
  static const Duration buildLife = Duration(minutes: 10);

  /// Replaced in tests so nothing touches the network.
  @visibleForTesting
  Future<http.Response> Function(Uri uri) getter = (uri) =>
      http.get(uri, headers: {'User-Agent': 'AvareX'}).timeout(
          const Duration(seconds: 90));

  final Map<String, NexradGrid> _frames = {};
  List<NexradGrid> _sorted = const [];
  String? _message;
  bool _loading = false;
  String _status = '';
  int _loaded = 0;
  int _expected = 0;
  DateTime? _builtAt;
  Future<void>? _running;

  /// Oldest first, newest last.
  List<NexradGrid> get frames => _sorted;

  /// The newest frame.
  NexradGrid? get grid => _sorted.isEmpty ? null : _sorted.last;

  /// Tallest echo top over the loop, so the 3D box does not change size while it plays.
  double get echoTopFt {
    var top = 0.0;
    for (final frame in _sorted) {
      if (frame.echoTopFt > top) {
        top = frame.echoTopFt;
      }
    }
    return top;
  }

  /// When the loop was last confirmed against the NOAA archive, or null.
  DateTime? get builtAt => _builtAt;

  /// True once the build is older than [buildLife].
  bool get expired {
    final built = _builtAt;
    return built != null && DateTime.now().difference(built) > buildLife;
  }

  /// Time left before the build expires, never negative. Null with no build.
  Duration? get lifeLeft {
    final built = _builtAt;
    if (built == null) {
      return null;
    }
    final left = buildLife - DateTime.now().difference(built);
    return left.isNegative ? Duration.zero : left;
  }

  /// Whether the aircraft has moved far enough that the grids no longer cover it.
  bool needsRegrid(double lat, double lon) {
    final newest = grid;
    return newest != null && _driftNm(newest, lat, lon) >= _regridNm;
  }

  /// Why there is no picture, or null.
  String? get message => _message;

  bool get loading => _loading;

  /// What the loader is doing right now.
  String get status => _status;

  /// Frames in this load that are done, and how many it will make.
  int get loadedCount => _loaded;
  int get expectedCount => _expected;

  void _resort() {
    _sorted = _frames.values.toList()..sort((a, b) => a.time.compareTo(b.time));
  }

  @visibleForTesting
  void debugSet(
      {NexradGrid? grid,
      List<NexradGrid>? frames,
      String? message,
      DateTime? builtAt,
      bool loading = false}) {
    _builtAt = builtAt;
    _frames.clear();
    for (final frame in frames ?? [if (grid != null) grid]) {
      _frames['debug${_frames.length}'] = frame;
    }
    _resort();
    _message = message;
    _loading = loading;
    notifyListeners();
  }

  /// Makes sure the loop covers [lat]/[lon] and ends on the newest volume.
  /// Calls made while a load is running join that load.
  Future<void> refresh(double lat, double lon, {bool force = false}) {
    final running = _running;
    if (running != null) {
      return running;
    }
    final future = _refresh(lat, lon, force).whenComplete(() {
      _running = null;
    });
    _running = future;
    return future;
  }

  Future<void> _refresh(double lat, double lon, bool force) async {
    _loading = true;
    _status = 'Finding radar';
    _loaded = 0;
    _expected = 0;
    notifyListeners();
    try {
      final candidates = nexradSitesNear(lat, lon, count: 5, maxNm: 200);
      if (candidates.isEmpty) {
        _frames.clear();
        _resort();
        _message = 'No NEXRAD radar within 200 NM';
        return;
      }
      final picked = <({NexradSite site, List<String> keys, double distanceNm})>[];
      for (final candidate in candidates) {
        if (picked.length == 2) {
          break;
        }
        // The second radar only helps when the first one is close enough that
        // its top tilt leaves a hole overhead.
        if (picked.length == 1 && picked.first.distanceNm > 35) {
          break;
        }
        final keys = await _recentKeys(candidate.site.id);
        if (keys.isNotEmpty) {
          picked.add((
            site: candidate.site,
            keys: keys,
            distanceNm: candidate.distanceNm
          ));
        }
      }
      if (picked.isEmpty) {
        // Offline or every radar quiet: keep the last loop until it is stale.
        final newest = grid;
        if (newest == null ||
            DateTime.now().toUtc().difference(newest.time) > _maxAge) {
          _frames.clear();
          _resort();
          _builtAt = null;
        }
        _message = 'No recent radar data, or no connection';
        return;
      }

      _builtAt = DateTime.now();
      final newest = grid;
      if (force ||
          (newest != null && _driftNm(newest, lat, lon) >= _regridNm)) {
        _frames.clear();
      }

      // One frame per volume of the nearest radar, each paired with the other
      // radar's volume closest in time.
      final specs = <({String id, List<(NexradSite, String)> parts})>[];
      for (final key in picked.first.keys) {
        final parts = <(NexradSite, String)>[(picked.first.site, key)];
        if (picked.length > 1) {
          final other = _closestKey(picked[1].keys, volumeKeyTime(key));
          if (other != null) {
            parts.add((picked[1].site, other));
          }
        }
        specs.add((id: parts.map((p) => p.$2).join('+'), parts: parts));
      }
      final wantedIds = specs.map((spec) => spec.id).toSet();
      _frames.removeWhere((id, _) => !wantedIds.contains(id));
      _resort();
      _message = null;

      final missing = specs.where((s) => !_frames.containsKey(s.id)).toList();
      _expected = missing.length;
      notifyListeners();
      // Newest first, so the latest picture shows before the older ones arrive.
      for (final spec in missing.reversed) {
        final built = await _buildFrame(spec.parts, lat, lon);
        _loaded++;
        if (built != null) {
          _frames[spec.id] = built;
          _resort();
        }
        notifyListeners();
      }
      if (_frames.isEmpty) {
        _message = 'Radar download failed';
      }
    } catch (e) {
      _message = _frames.isEmpty
          ? 'Radar unavailable: check the connection'
          : 'Could not update radar';
    } finally {
      _loading = false;
      _status = '';
      notifyListeners();
    }
  }

  Future<NexradGrid?> _buildFrame(
      List<(NexradSite, String)> parts, double lat, double lon) async {
    try {
      final files = <Uint8List>[];
      final sites = <NexradSite>[];
      for (final part in parts) {
        _status = 'Downloading ${part.$1.id} ${_loaded + 1} of $_expected';
        notifyListeners();
        final response = await getter(Uri.parse('$_bucket/${part.$2}'));
        if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
          continue;
        }
        files.add(response.bodyBytes);
        sites.add(part.$1);
      }
      if (files.isEmpty) {
        return null;
      }
      _status = 'Building 3D radar ${_loaded + 1} of $_expected';
      notifyListeners();
      return await compute(
        _buildGrid,
        _NexradJob(
          files: files,
          sites: [
            for (final site in sites) [site.lat, site.lon, site.elevationM]
          ],
          centerLat: lat,
          centerLon: lon,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _closestKey(List<String> keys, DateTime? at) {
    if (at == null) {
      return null;
    }
    String? best;
    var bestGap = _pairWindow;
    for (final key in keys) {
      final time = volumeKeyTime(key);
      if (time == null) {
        continue;
      }
      final gap = time.difference(at).abs();
      if (gap <= bestGap) {
        bestGap = gap;
        best = key;
      }
    }
    return best;
  }

  double _driftNm(NexradGrid grid, double lat, double lon) {
    final cosLat = math.cos(grid.centerLat * math.pi / 180);
    final east = (lon - grid.centerLon) * 60 * cosLat;
    final north = (lat - grid.centerLat) * 60;
    return math.sqrt(east * east + north * north);
  }

  /// Volume keys of [siteId] from the last [loopLength] before its newest one,
  /// oldest first. Empty when the radar has nothing newer than [_maxAge].
  Future<List<String>> _recentKeys(String siteId) async {
    final now = DateTime.now().toUtc();
    final keys = <String>[];
    for (var back = 0; back < 2; back++) {
      final day = now.subtract(Duration(days: back));
      final prefix = '${day.year}/${_two(day.month)}/${_two(day.day)}/$siteId/';
      final response =
          await getter(Uri.parse('$_bucket/?list-type=2&prefix=$prefix'));
      if (response.statusCode == 200) {
        keys.addAll(volumeKeys(response.body, siteId));
      }
      // Yesterday only matters when today has nothing, or the loop reaches back past 00Z.
      final newest = keys.isEmpty ? null : volumeKeyTime(keys.last);
      final midnight = DateTime.utc(day.year, day.month, day.day);
      if (newest != null && !newest.isBefore(midnight.add(loopLength))) {
        break;
      }
    }
    keys.sort();
    final newest = keys.isEmpty ? null : volumeKeyTime(keys.last);
    if (newest == null || now.difference(newest) > _maxAge) {
      return const [];
    }
    return keys.where((key) {
      final time = volumeKeyTime(key);
      return time != null && newest.difference(time) <= loopLength;
    }).toList();
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

/// All full-volume keys in an S3 listing, oldest first, skipping `_MDM` metadata objects.
@visibleForTesting
List<String> volumeKeys(String listingXml, String siteId) {
  final keys = <String>[];
  for (final element in XmlDocument.parse(listingXml).findAllElements('Key')) {
    final key = element.innerText;
    final name = key.split('/').last;
    if (name.startsWith(siteId) && name.endsWith('_V06')) {
      keys.add(key);
    }
  }
  keys.sort();
  return keys;
}

/// Start time encoded in `.../KTLX20240506_221444_V06`.
@visibleForTesting
DateTime? volumeKeyTime(String key) {
  final match = RegExp(r'(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})_V06$')
      .firstMatch(key);
  if (match == null) {
    return null;
  }
  final v = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  return DateTime.utc(v[0], v[1], v[2], v[3], v[4], v[5]);
}

class _NexradJob {
  final List<Uint8List> files;
  final List<List<double>> sites;
  final double centerLat;
  final double centerLon;

  const _NexradJob({
    required this.files,
    required this.sites,
    required this.centerLat,
    required this.centerLon,
  });
}

NexradGrid? _buildGrid(_NexradJob job) {
  final volumes = <NexradVolume>[];
  for (var i = 0; i < job.files.length; i++) {
    final volume = decodeNexradLevel2(
      job.files[i],
      fallbackLat: job.sites[i][0],
      fallbackLon: job.sites[i][1],
      fallbackElevM: job.sites[i][2],
    );
    if (volume != null) {
      volumes.add(volume);
    }
  }
  return voxelizeNexrad(
    volumes,
    centerLat: job.centerLat,
    centerLon: job.centerLon,
    radiusNm: NexradVolumeCache.gridRadiusNm,
  );
}
