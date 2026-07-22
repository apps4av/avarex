import 'package:avaremp/constants.dart';
import 'package:avaremp/gdl90/cloud_tops_product.dart';
import 'package:avaremp/gdl90/global_block_product.dart';
import 'package:avaremp/gdl90/nexrad_cache.dart';

/// Cache for FIS-B global-block weather (icing, turbulence, cloud tops, lightning).
/// Same image geometry as [NexradCache]; keyed by product kind + altitude + block.
class FisBlockCache {
  final Map<String, NexradImage> _cache = {};
  /// Cloud tops keep raw intensity indices so the altitude slider can filter.
  final Map<int, _CloudTopsEntry> _cloudTops = {};

  static String _key(String kind, int altitudeFt, int block) =>
      "$kind|$altitudeFt|$block";

  void putImg(GlobalBlockProduct product) {
    if (product.kind == "cloudTops") {
      _putCloudTops(product);
      return;
    }

    if (product.empty.isNotEmpty) {
      for (final int block in product.empty) {
        final String k = _key(product.kind, product.altitudeFt, block);
        _cache.remove(k)?.discard();
      }
    }
    if (product.full.isNotEmpty) {
      final String k = _key(product.kind, product.altitudeFt, product.block);
      _cache.remove(k)?.discard();
      _cache[k] = NexradImage(product.full, product.block, product.isConusScale);
    }

    _expire(_cache);
  }

  void _putCloudTops(GlobalBlockProduct product) {
    if (product.empty.isNotEmpty) {
      for (final int block in product.empty) {
        _cloudTops.remove(block)?.discard();
      }
    }
    if (product.intensities.isNotEmpty) {
      _cloudTops[product.block]?.discard();
      _cloudTops[product.block] = _CloudTopsEntry(
        intensities: List<int>.from(product.intensities),
        block: product.block,
        conus: product.isConusScale,
      );
    }
    _cloudTops.removeWhere((block, entry) {
      if (entry.isExpired()) {
        entry.discard();
        return true;
      }
      return false;
    });
  }

  void _expire(Map<String, NexradImage> map) {
    map.removeWhere((key, image) {
      final Duration diff = DateTime.now().difference(image.time);
      if (diff.inMinutes > Constants.weatherUpdateTimeMin) {
        image.discard();
        return true;
      }
      return false;
    });
  }

  /// Images for [kind]. For icing/turbulence, pass [altitudeFt] to keep the
  /// discrete forecast level nearest the slider (±1000 ft). For cloud tops,
  /// only bins whose top height is at or above [altitudeFt] are colored.
  List<NexradImage> get(String kind, {int? altitudeFt}) {
    if (kind == "cloudTops") {
      return _getCloudTops(altitudeFt ?? 0);
    }

    final List<NexradImage> ret = [];
    final String prefix = "$kind|";
    for (final MapEntry<String, NexradImage> e in _cache.entries) {
      if (!e.key.startsWith(prefix)) {
        continue;
      }
      if (e.value.isExpired()) {
        e.value.discard();
        continue;
      }
      if (altitudeFt != null) {
        final List<String> parts = e.key.split("|");
        if (parts.length < 3) {
          continue;
        }
        final int alt = int.tryParse(parts[1]) ?? 0;
        if ((alt - altitudeFt).abs() > 1000) {
          continue;
        }
      }
      if (e.value.getImage() != null) {
        ret.add(e.value);
      }
    }
    return ret;
  }

  List<NexradImage> _getCloudTops(int altitudeFt) {
    final List<NexradImage> ret = [];
    final List<int> colors = CloudTopsProduct.colors;
    for (final _CloudTopsEntry entry in _cloudTops.values) {
      if (entry.isExpired()) {
        entry.discard();
        continue;
      }
      final NexradImage? img = entry.imageFor(altitudeFt, colors);
      if (img != null && img.getImage() != null) {
        ret.add(img);
      }
    }
    // Drop expired entries left marked for removal.
    _cloudTops.removeWhere((_, e) => e.isExpired());
    return ret;
  }
}

class _CloudTopsEntry {
  _CloudTopsEntry({
    required this.intensities,
    required this.block,
    required this.conus,
  }) : time = DateTime.now();

  final List<int> intensities;
  final int block;
  final bool conus;
  final DateTime time;
  int? _renderedAlt;
  NexradImage? _image;

  bool isExpired() {
    return DateTime.now().difference(time).inSeconds > 600;
  }

  void discard() {
    _image?.discard();
    _image = null;
    _renderedAlt = null;
  }

  /// Upper bound (ft) of each FIS-B cloud-top encoding (Table G-15).
  static int _topMaxFt(int encoding) {
    const List<int> maxFt = [
      0, // 0 no clouds
      1500, 3000, 4500, 6000, 7500, 9000, 10500, 12000, 13500, 15000,
      18000, 21000, 24000, 60000, // 14 = above 24000
    ];
    if (encoding < 0 || encoding >= maxFt.length) {
      return -1;
    }
    return maxFt[encoding];
  }

  NexradImage? imageFor(int altitudeFt, List<int> colors) {
    if (_image != null && _renderedAlt == altitudeFt) {
      return _image;
    }
    _image?.discard();
    final List<int> argb = List<int>.filled(intensities.length, 0);
    int have = 0;
    for (int i = 0; i < intensities.length; i++) {
      final int idx = intensities[i];
      // Hide bins with no/unknown tops, or tops below the selected altitude.
      if (idx < 1 || idx > 14 || _topMaxFt(idx) < altitudeFt) {
        continue;
      }
      argb[i] = (idx < colors.length) ? colors[idx] : 0;
      if (argb[i] != 0) {
        have++;
      }
    }
    if (have == 0) {
      _image = null;
      _renderedAlt = altitudeFt;
      return null;
    }
    _image = NexradImage(argb, block, conus);
    _renderedAlt = altitudeFt;
    return _image;
  }
}
