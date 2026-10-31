import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// One reflectivity sweep (a single antenna tilt) from a Level II volume.
class NexradSweep {
  final double elevationDeg;
  final int volumeOrder;
  final Float32List azimuthsDeg;
  final Uint8List raw;
  final int gates;
  final double firstGateM;
  final double gateSpacingM;
  final double scale;
  final double offset;
  final Int16List _azLookup;

  NexradSweep._(this.elevationDeg, this.volumeOrder, this.azimuthsDeg, this.raw,
      this.gates, this.firstGateM, this.gateSpacingM, this.scale, this.offset,
      this._azLookup);

  int get radials => azimuthsDeg.length;

  /// Marks "no echo" in [sample].
  static const double noEcho = -100;

  /// dBZ at [azimuthDeg]/[rangeM], [noEcho] when the beam saw nothing there,
  /// or NaN when the sweep does not reach that far.
  double sample(double azimuthDeg, double rangeM) {
    if (radials == 0 || rangeM < firstGateM) {
      return double.nan;
    }
    final gate = ((rangeM - firstGateM) / gateSpacingM).floor();
    if (gate < 0 || gate >= gates) {
      return double.nan;
    }
    var az = azimuthDeg % 360.0;
    if (az < 0) {
      az += 360.0;
    }
    final radial = _azLookup[(az * 10).floor() % 3600];
    if (radial < 0) {
      return double.nan;
    }
    final value = raw[radial * gates + gate];
    if (value == 0) {
      return noEcho;
    }
    if (value == 1) {
      return double.nan;
    }
    return (value - offset) / scale;
  }
}

/// A decoded Level II volume: reflectivity sweeps sorted from low to high tilt.
class NexradVolume {
  final String siteId;
  final double latitude;
  final double longitude;
  final double antennaMslM;
  final DateTime time;
  final List<NexradSweep> sweeps;

  const NexradVolume({
    required this.siteId,
    required this.latitude,
    required this.longitude,
    required this.antennaMslM,
    required this.time,
    required this.sweeps,
  });
}

class _RadialBuilder {
  double elevationSum = 0;
  final int order;
  final List<double> azimuths = [];
  final List<Uint8List> rows = [];
  int gates = 0;
  double firstGateM = 0;
  double gateSpacingM = 250;
  double scale = 2;
  double offset = 66;

  _RadialBuilder(this.order);

  double get elevation => elevationSum / math.max(1, azimuths.length);
}

/// Reads an Archive II file (the `*_V06` objects in the unidata-nexrad-level2 bucket).
/// Only reflectivity is kept. Returns null when the bytes are not a Level II volume.
NexradVolume? decodeNexradLevel2(Uint8List bytes,
    {double? fallbackLat, double? fallbackLon, double? fallbackElevM}) {
  if (bytes.length < 28 ||
      bytes[0] != 0x41 ||
      bytes[1] != 0x52 ||
      bytes[2] != 0x32 ||
      bytes[3] != 0x56) {
    return null;
  }
  final head = ByteData.sublistView(bytes);
  final days = head.getUint32(12);
  final ms = head.getUint32(16);
  var siteId = String.fromCharCodes(bytes.sublist(20, 24)).trim();
  var lat = fallbackLat ?? 0.0;
  var lon = fallbackLon ?? 0.0;
  var antenna = fallbackElevM ?? 0.0;
  final volumeTime = DateTime.fromMillisecondsSinceEpoch(
      (days - 1) * 86400000 + ms,
      isUtc: true);

  final cuts = <_RadialBuilder>[];
  _RadialBuilder? current;
  var order = 0;
  var pos = 24;
  while (pos + 4 <= bytes.length) {
    final size = head.getInt32(pos).abs();
    pos += 4;
    if (size == 0 || pos + size > bytes.length) {
      break;
    }
    Uint8List chunk;
    try {
      chunk = BZip2Decoder()
          .decodeBytes(Uint8List.sublistView(bytes, pos, pos + size));
    } catch (_) {
      pos += size;
      continue;
    }
    pos += size;
    final data = ByteData.sublistView(chunk);
    var at = 0;
    while (at + 28 <= chunk.length) {
      final halfwords = data.getUint16(at + 12);
      final type = chunk[at + 15];
      if (type != 31) {
        at += 2432;
        continue;
      }
      final length = halfwords * 2;
      if (length < 16 + 32 || at + 12 + length > chunk.length) {
        break;
      }
      final base = at + 12 + 16;
      at += 12 + length;
      final end = at;
      if (data.getUint16(base + 30) < 2) {
        continue;
      }
      final status = chunk[base + 21];
      final elevationAngle = data.getFloat32(base + 24);
      final azimuth = data.getFloat32(base + 12);
      if (!azimuth.isFinite || !elevationAngle.isFinite) {
        continue;
      }
      final blocks = math.min(data.getUint16(base + 30), 10);
      int? refAt;
      int? volAt;
      for (var b = 0; b < blocks; b++) {
        final pointer = data.getUint32(base + 32 + b * 4);
        if (pointer == 0 || base + pointer + 8 > end) {
          continue;
        }
        final name = String.fromCharCodes(
            chunk.sublist(base + pointer + 1, base + pointer + 4));
        if (name == 'REF') {
          refAt = base + pointer;
        } else if (name == 'VOL') {
          volAt = base + pointer;
        }
      }
      if (volAt != null && volAt + 20 <= end) {
        final vLat = data.getFloat32(volAt + 8);
        final vLon = data.getFloat32(volAt + 12);
        if (vLat.isFinite && vLon.isFinite && (vLat != 0 || vLon != 0)) {
          lat = vLat;
          lon = vLon;
          antenna = (data.getInt16(volAt + 16) + data.getUint16(volAt + 18))
              .toDouble();
        }
      }
      if (status == 0 || status == 3 || status == 5 || current == null) {
        current = null;
      }
      if (refAt == null || refAt + 28 > end) {
        continue;
      }
      final gates = data.getUint16(refAt + 8);
      final wordSize = chunk[refAt + 19];
      if (gates == 0 || wordSize != 8 || refAt + 28 + gates > end) {
        continue;
      }
      if (current == null) {
        current = _RadialBuilder(order++);
        cuts.add(current);
      }
      current.gates = math.max(current.gates, gates);
      current.firstGateM = data.getUint16(refAt + 10).toDouble();
      current.gateSpacingM = math.max(1, data.getUint16(refAt + 12)).toDouble();
      final scale = data.getFloat32(refAt + 20);
      final offset = data.getFloat32(refAt + 24);
      if (scale.isFinite && scale != 0 && offset.isFinite) {
        current.scale = scale;
        current.offset = offset;
      }
      current.elevationSum += elevationAngle;
      current.azimuths.add(azimuth);
      current.rows.add(Uint8List.fromList(
          Uint8List.sublistView(chunk, refAt + 28, refAt + 28 + gates)));
    }
  }

  if (siteId.isEmpty) {
    siteId = 'KXXX';
  }
  if (lat == 0 && lon == 0) {
    return null;
  }
  final sweeps = <NexradSweep>[];
  for (final cut in cuts) {
    final sweep = _finishSweep(cut);
    if (sweep != null) {
      sweeps.add(sweep);
    }
  }
  if (sweeps.isEmpty) {
    return null;
  }
  // Repeat cuts at the same angle (SAILS): the later one is the fresher picture.
  sweeps.sort((a, b) => a.elevationDeg != b.elevationDeg
      ? a.elevationDeg.compareTo(b.elevationDeg)
      : a.volumeOrder.compareTo(b.volumeOrder));
  final unique = <NexradSweep>[];
  var groupStart = double.negativeInfinity;
  for (final sweep in sweeps) {
    if (unique.isNotEmpty && sweep.elevationDeg - groupStart < 0.2) {
      unique[unique.length - 1] = sweep;
    } else {
      groupStart = sweep.elevationDeg;
      unique.add(sweep);
    }
  }
  return NexradVolume(
    siteId: siteId,
    latitude: lat,
    longitude: lon,
    antennaMslM: antenna,
    time: volumeTime,
    sweeps: unique,
  );
}

NexradSweep? _finishSweep(_RadialBuilder cut) {
  final count = cut.rows.length;
  if (count < 90 || cut.gates == 0) {
    return null;
  }
  final order = List<int>.generate(count, (i) => i)
    ..sort((a, b) => cut.azimuths[a].compareTo(cut.azimuths[b]));
  final azimuths = Float32List(count);
  final raw = Uint8List(count * cut.gates);
  for (var i = 0; i < count; i++) {
    final row = cut.rows[order[i]];
    azimuths[i] = cut.azimuths[order[i]];
    raw.setRange(i * cut.gates, i * cut.gates + row.length, row);
  }
  // Nearest radial for every tenth of a degree. Gaps wider than 3 degrees stay empty.
  final lookup = Int16List(3600);
  for (var bin = 0; bin < 3600; bin++) {
    final target = bin / 10.0 + 0.05;
    var best = -1;
    var bestDiff = 3.0;
    var low = 0;
    var high = count - 1;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (azimuths[mid] < target) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    for (final candidate in [low - 1, low, low + 1]) {
      final i = (candidate + count) % count;
      var diff = (azimuths[i] - target).abs();
      if (diff > 180) {
        diff = 360 - diff;
      }
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i;
      }
    }
    lookup[bin] = best;
  }
  return NexradSweep._(cut.elevation, cut.order, azimuths, raw, cut.gates,
      cut.firstGateM, cut.gateSpacingM, cut.scale, cut.offset, lookup);
}

/// Reflectivity on a regular east/north/altitude grid around [centerLat]/[centerLon].
class NexradGrid {
  final String label;
  final DateTime time;
  final double centerLat;
  final double centerLon;
  final double radiusNm;
  final double cellNm;
  final double levelFt;
  final int cols;
  final int levels;

  /// 0 is empty, otherwise whole dBZ. Index is `(level * cols + row) * cols + col`,
  /// row 0 south, col 0 west, level 0 the lowest slab.
  final Uint8List dbz;

  /// Top of the highest slab with a return of at least [echoTopDbz].
  final double echoTopFt;

  const NexradGrid({
    required this.label,
    required this.time,
    required this.centerLat,
    required this.centerLon,
    required this.radiusNm,
    required this.cellNm,
    required this.levelFt,
    required this.cols,
    required this.levels,
    required this.dbz,
    required this.echoTopFt,
  });

  static const int minDbz = 5;
  static const int echoTopDbz = 18;

  int index(int level, int row, int col) => (level * cols + row) * cols + col;

  double get ageMinutes =>
      DateTime.now().toUtc().difference(time).inSeconds / 60.0;
}

const double _earthM = 6371000.0;
const double _beamEarthM = _earthM * 4.0 / 3.0;
const double _feetPerMeter = 3.28084;

/// Resamples one or more radars (nearest first) into one grid. A radar that does
/// not reach a cell, because it is in the cone above the antenna or past the
/// range, hands that cell to the next one.
NexradGrid? voxelizeNexrad(
  List<NexradVolume> volumes, {
  required double centerLat,
  required double centerLon,
  double radiusNm = 60,
  double cellNm = 1,
  double levelFt = 1000,
  int maxLevels = 45,
}) {
  if (volumes.isEmpty) {
    return null;
  }
  final cols = (radiusNm * 2 / cellNm).round();
  final levels = maxLevels;
  final out = Uint8List(levels * cols * cols);
  final cosLat = math.cos(centerLat * math.pi / 180);

  // One entry per (row, col, radar): bearing and ground distance from that radar.
  final az = List.generate(volumes.length, (_) => Float64List(cols * cols));
  final ground = List.generate(volumes.length, (_) => Float64List(cols * cols));
  for (var row = 0; row < cols; row++) {
    final north = -radiusNm + (row + 0.5) * cellNm;
    final lat = centerLat + north / 60.0;
    for (var col = 0; col < cols; col++) {
      final east = -radiusNm + (col + 0.5) * cellNm;
      final lon = centerLon + east / (60.0 * cosLat);
      for (var v = 0; v < volumes.length; v++) {
        final p = _bearingDistance(
            volumes[v].latitude, volumes[v].longitude, lat, lon);
        az[v][row * cols + col] = p.$1;
        ground[v][row * cols + col] = p.$2;
      }
    }
  }

  var topLevel = -1;
  for (var level = 0; level < levels; level++) {
    var strong = 0;
    final altM = (level + 0.5) * levelFt / _feetPerMeter;
    for (var cell = 0; cell < cols * cols; cell++) {
      for (var v = 0; v < volumes.length; v++) {
        final volume = volumes[v];
        final value = _sampleVolume(
            volume, az[v][cell], ground[v][cell], altM - volume.antennaMslM);
        if (value.isNaN) {
          continue;
        }
        if (value >= NexradGrid.minDbz) {
          final dbz = value.round().clamp(NexradGrid.minDbz, 95);
          out[level * cols * cols + cell] = dbz;
          if (dbz >= NexradGrid.echoTopDbz) {
            strong++;
          }
        }
        break;
      }
    }
    // A few stray cells (birds, clutter) must not stretch the whole box upward.
    if (strong >= 4) {
      topLevel = level;
    }
  }

  var newest = volumes.first.time;
  for (final volume in volumes) {
    if (volume.time.isAfter(newest)) {
      newest = volume.time;
    }
  }
  return NexradGrid(
    label: volumes.map((v) => v.siteId).join(' + '),
    time: newest,
    centerLat: centerLat,
    centerLon: centerLon,
    radiusNm: radiusNm,
    cellNm: cellNm,
    levelFt: levelFt,
    cols: cols,
    levels: levels,
    dbz: out,
    echoTopFt: topLevel < 0 ? 0 : (topLevel + 1) * levelFt,
  );
}

/// Bearing in degrees and surface distance in meters from the radar to the point.
(double, double) _bearingDistance(
    double lat1, double lon1, double lat2, double lon2) {
  final p1 = lat1 * math.pi / 180;
  final p2 = lat2 * math.pi / 180;
  final dl = (lon2 - lon1) * math.pi / 180;
  final y = math.sin(dl) * math.cos(p2);
  final x = math.cos(p1) * math.sin(p2) -
      math.sin(p1) * math.cos(p2) * math.cos(dl);
  final bearing = math.atan2(y, x) * 180 / math.pi;
  final a = math.pow(math.sin((p2 - p1) / 2), 2) +
      math.cos(p1) * math.cos(p2) * math.pow(math.sin(dl / 2), 2);
  final c = 2 * math.asin(math.min(1.0, math.sqrt(a.toDouble())));
  return ((bearing + 360) % 360, c * _earthM);
}

/// dBZ for a point [heightM] above the antenna and [groundM] away along the surface.
/// NaN means this radar has no view of it.
double _sampleVolume(
    NexradVolume volume, double bearingDeg, double groundM, double heightM) {
  final sweeps = volume.sweeps;
  if (sweeps.isEmpty) {
    return double.nan;
  }
  final phi = groundM / _beamEarthM;
  final radius = _beamEarthM + heightM;
  final x = radius * math.sin(phi);
  final y = radius * math.cos(phi) - _beamEarthM;
  final slant = math.sqrt(x * x + y * y);
  if (slant < 1000) {
    return double.nan;
  }
  final elevation = math.atan2(y, x) * 180 / math.pi;

  if (elevation <= sweeps.first.elevationDeg) {
    if (sweeps.first.elevationDeg - elevation > 0.75) {
      return double.nan;
    }
    return sweeps.first.sample(bearingDeg, slant);
  }
  if (elevation >= sweeps.last.elevationDeg) {
    if (elevation - sweeps.last.elevationDeg > 1.0) {
      return double.nan;
    }
    return sweeps.last.sample(bearingDeg, slant);
  }
  var high = 1;
  while (high < sweeps.length - 1 && sweeps[high].elevationDeg < elevation) {
    high++;
  }
  final lo = sweeps[high - 1];
  final hi = sweeps[high];
  final vLo = lo.sample(bearingDeg, slant);
  final vHi = hi.sample(bearingDeg, slant);
  final t = (elevation - lo.elevationDeg) / (hi.elevationDeg - lo.elevationDeg);
  if (vLo.isNaN && vHi.isNaN) {
    return double.nan;
  }
  if (vLo.isNaN) {
    return t > 0.5 ? vHi : double.nan;
  }
  if (vHi.isNaN) {
    return t < 0.5 ? vLo : double.nan;
  }
  // No echo counts as a faint return, so an edge fades instead of staying hard.
  final a = math.max(vLo, 0.0);
  final b = math.max(vHi, 0.0);
  final value = a * (1 - t) + b * t;
  return value < NexradGrid.minDbz && vLo == NexradSweep.noEcho &&
          vHi == NexradSweep.noEcho
      ? NexradSweep.noEcho
      : value;
}
