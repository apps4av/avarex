import 'dart:math' as math;
import 'dart:typed_data';

/// Small GRIB2 reader for the NOAA icing and turbulence guidance files (DAFS).
///
/// It reads the pieces those files use and nothing else: a Lambert conformal
/// grid (template 3.30) and simple, complex, or complex with spatial
/// differencing packing (templates 5.0, 5.2, 5.3), with or without a bitmap.
/// Anything else throws a [FormatException] so a changed feed fails loudly.

/// Lambert conformal grid on a sphere (GRIB2 grid template 3.30).
class Grib2LambertGrid {
  final int ni;
  final int nj;
  final double dxMeters;
  final double dyMeters;
  final double firstLat;
  final double firstLon;
  final double originLon;
  final double originLat;
  final double latin1;
  final double latin2;
  final int scanningMode;
  final double earthRadius;

  late final double _n;
  late final double _f;
  late final double _rho0;
  late final double _x1;
  late final double _y1;

  Grib2LambertGrid({
    required this.ni,
    required this.nj,
    required this.dxMeters,
    required this.dyMeters,
    required this.firstLat,
    required this.firstLon,
    required this.originLon,
    required this.originLat,
    required this.latin1,
    required this.latin2,
    required this.scanningMode,
    this.earthRadius = 6371229,
  }) {
    final p1 = latin1 * math.pi / 180;
    final p2 = latin2 * math.pi / 180;
    if ((p1 - p2).abs() < 1e-9) {
      _n = math.sin(p1);
    } else {
      _n = math.log(math.cos(p1) / math.cos(p2)) /
          math.log(math.tan(math.pi / 4 + p2 / 2) /
              math.tan(math.pi / 4 + p1 / 2));
    }
    _f = math.cos(p1) * math.pow(math.tan(math.pi / 4 + p1 / 2), _n) / _n;
    _rho0 = _rho(originLat * math.pi / 180);
    final first = _project(firstLat, firstLon);
    _x1 = first.$1;
    _y1 = first.$2;
  }

  double _rho(double lat) =>
      earthRadius * _f / math.pow(math.tan(math.pi / 4 + lat / 2), _n);

  (double, double) _project(double latDeg, double lonDeg) {
    var dLon = lonDeg - originLon;
    while (dLon > 180) {
      dLon -= 360;
    }
    while (dLon < -180) {
      dLon += 360;
    }
    final rho = _rho(latDeg * math.pi / 180);
    final theta = _n * dLon * math.pi / 180;
    return (rho * math.sin(theta), _rho0 - rho * math.cos(theta));
  }

  /// Fractional column and row of a place, in the order the values are stored.
  (double, double) index(double latDeg, double lonDeg) {
    final xy = _project(latDeg, lonDeg);
    final stepX = (scanningMode & 0x80) != 0 ? -dxMeters : dxMeters;
    final stepY = (scanningMode & 0x40) != 0 ? dyMeters : -dyMeters;
    return ((xy.$1 - _x1) / stepX, (xy.$2 - _y1) / stepY);
  }
}

/// One decoded field: one parameter on one level at one forecast time.
class Grib2Message {
  final int discipline;
  final int category;
  final int number;

  /// GRIB2 code table 4.5, such as 102 for mean sea level and 103 for height above ground.
  final int levelType;

  /// Level in the surface's own unit, meters for types 102 and 103.
  final double level;
  final DateTime referenceTime;
  final int forecastHours;
  final Grib2LambertGrid grid;

  /// Row-major in scan order. NaN where the bitmap says there is no value.
  final Float32List values;

  const Grib2Message({
    required this.discipline,
    required this.category,
    required this.number,
    required this.levelType,
    required this.level,
    required this.referenceTime,
    required this.forecastHours,
    required this.grid,
    required this.values,
  });

  DateTime get validTime => referenceTime.add(Duration(hours: forecastHours));

  /// Whether the place is inside the grid.
  bool covers(double lat, double lon) {
    final at = grid.index(lat, lon);
    return at.$1 >= 0 &&
        at.$2 >= 0 &&
        at.$1 <= grid.ni - 1 &&
        at.$2 <= grid.nj - 1;
  }

  /// The value at a place, or NaN outside the grid or where there is no value.
  /// [nearest] keeps categories whole, otherwise the four neighbors are blended.
  double sample(double lat, double lon, {bool nearest = false}) {
    final at = grid.index(lat, lon);
    final fi = at.$1;
    final fj = at.$2;
    if (fi < 0 || fj < 0 || fi > grid.ni - 1 || fj > grid.nj - 1) {
      return double.nan;
    }
    if (nearest) {
      return values[fj.round() * grid.ni + fi.round()];
    }
    final i0 = fi.floor().clamp(0, grid.ni - 2);
    final j0 = fj.floor().clamp(0, grid.nj - 2);
    final ti = fi - i0;
    final tj = fj - j0;
    final a = values[j0 * grid.ni + i0];
    final b = values[j0 * grid.ni + i0 + 1];
    final c = values[(j0 + 1) * grid.ni + i0];
    final d = values[(j0 + 1) * grid.ni + i0 + 1];
    if (a.isNaN || b.isNaN || c.isNaN || d.isNaN) {
      return values[fj.round() * grid.ni + fi.round()];
    }
    return (a * (1 - ti) + b * ti) * (1 - tj) + (c * (1 - ti) + d * ti) * tj;
  }
}

/// Reads every message in [bytes]. Fields it cannot read throw a [FormatException].
List<Grib2Message> readGrib2(Uint8List bytes) {
  final out = <Grib2Message>[];
  final data = ByteData.sublistView(bytes);
  var pos = 0;
  while (pos + 16 <= bytes.length) {
    if (bytes[pos] != 0x47 ||
        bytes[pos + 1] != 0x52 ||
        bytes[pos + 2] != 0x49 ||
        bytes[pos + 3] != 0x42) {
      pos++;
      continue;
    }
    final edition = bytes[pos + 7];
    if (edition != 2) {
      throw const FormatException('Not a GRIB2 message');
    }
    final length = data.getUint64(pos + 8);
    final end = pos + length;
    if (end > bytes.length) {
      throw const FormatException('GRIB2 message is cut short');
    }
    out.add(_readMessage(bytes, data, pos, end));
    pos = end;
  }
  return out;
}

int _signMagnitude(int value, int byteCount) {
  final signBit = 1 << (byteCount * 8 - 1);
  return (value & signBit) != 0 ? -(value & (signBit - 1)) : value;
}

int _signedBytes(ByteData data, int at, int byteCount) {
  var value = 0;
  for (var i = 0; i < byteCount; i++) {
    value = (value << 8) | data.getUint8(at + i);
  }
  return _signMagnitude(value, byteCount);
}

Grib2Message _readMessage(Uint8List bytes, ByteData data, int start, int end) {
  final discipline = bytes[start + 6];
  var pos = start + 16;
  DateTime? reference;
  Grib2LambertGrid? grid;
  var category = 0;
  var number = 0;
  var levelType = 0;
  var level = 0.0;
  var forecastHours = 0;
  var dataPoints = 0;
  int? packing;
  int? sectionFive;
  Uint8List? bitmap;
  var hasBitmap = false;
  Float32List? values;

  while (pos + 5 <= end) {
    if (bytes[pos] == 0x37 &&
        bytes[pos + 1] == 0x37 &&
        bytes[pos + 2] == 0x37 &&
        bytes[pos + 3] == 0x37) {
      break;
    }
    final length = data.getUint32(pos);
    final section = bytes[pos + 4];
    switch (section) {
      case 1:
        reference = DateTime.utc(
          data.getUint16(pos + 12),
          bytes[pos + 14],
          bytes[pos + 15],
          bytes[pos + 16],
          bytes[pos + 17],
          bytes[pos + 18],
        );
        break;
      case 3:
        final template = data.getUint16(pos + 12);
        if (template != 30) {
          throw FormatException('GRIB2 grid template $template is not supported');
        }
        final shape = bytes[pos + 14];
        grid = Grib2LambertGrid(
          ni: data.getUint32(pos + 30),
          nj: data.getUint32(pos + 34),
          firstLat: _signedBytes(data, pos + 38, 4) / 1e6,
          firstLon: data.getUint32(pos + 42) / 1e6,
          originLat: _signedBytes(data, pos + 47, 4) / 1e6,
          originLon: data.getUint32(pos + 51) / 1e6,
          dxMeters: data.getUint32(pos + 55) / 1000,
          dyMeters: data.getUint32(pos + 59) / 1000,
          scanningMode: bytes[pos + 64],
          latin1: _signedBytes(data, pos + 65, 4) / 1e6,
          latin2: _signedBytes(data, pos + 69, 4) / 1e6,
          earthRadius: shape == 0 ? 6367470 : 6371229,
        );
        break;
      case 4:
        final template = data.getUint16(pos + 7);
        if (template != 0) {
          throw FormatException(
              'GRIB2 product template $template is not supported');
        }
        category = bytes[pos + 9];
        number = bytes[pos + 10];
        final unit = bytes[pos + 17];
        final time = data.getUint32(pos + 18);
        forecastHours = switch (unit) {
          0 => time ~/ 60,
          1 => time,
          2 => time * 24,
          _ => time,
        };
        levelType = bytes[pos + 22];
        final scale = _signMagnitude(bytes[pos + 23], 1);
        final scaled = _signedBytes(data, pos + 24, 4);
        level = scaled * math.pow(10, -scale).toDouble();
        break;
      case 5:
        dataPoints = data.getUint32(pos + 5);
        packing = data.getUint16(pos + 9);
        sectionFive = pos;
        break;
      case 6:
        final indicator = bytes[pos + 5];
        if (indicator == 0) {
          hasBitmap = true;
          bitmap = Uint8List.sublistView(bytes, pos + 6, pos + length);
        } else if (indicator != 255) {
          throw FormatException('GRIB2 bitmap type $indicator is not supported');
        }
        break;
      case 7:
        final five = sectionFive;
        if (five == null || packing == null || grid == null) {
          throw const FormatException('GRIB2 data before its description');
        }
        final packed = _unpack(bytes, data, five, packing, pos + 5, pos + length,
            dataPoints);
        final total = grid.ni * grid.nj;
        if (hasBitmap) {
          final field = Float32List(total);
          var k = 0;
          for (var i = 0; i < total; i++) {
            final present = (bitmap![i >> 3] & (0x80 >> (i & 7))) != 0;
            field[i] = present && k < packed.length ? packed[k++] : double.nan;
          }
          values = field;
        } else {
          if (packed.length < total) {
            throw const FormatException('GRIB2 field has too few values');
          }
          values = packed;
        }
        break;
    }
    pos += length;
  }
  if (reference == null || grid == null || values == null) {
    throw const FormatException('GRIB2 message is incomplete');
  }
  return Grib2Message(
    discipline: discipline,
    category: category,
    number: number,
    levelType: levelType,
    level: level,
    referenceTime: reference,
    forecastHours: forecastHours,
    grid: grid,
    values: values,
  );
}

class _Bits {
  final Uint8List bytes;
  int bit;

  _Bits(this.bytes, int startByte) : bit = startByte * 8;

  int read(int count) {
    var value = 0;
    var left = count;
    while (left > 0) {
      final byteIndex = bit >> 3;
      final used = bit & 7;
      final take = math.min(8 - used, left);
      final chunk = (bytes[byteIndex] >> (8 - used - take)) & ((1 << take) - 1);
      value = (value << take) | chunk;
      bit += take;
      left -= take;
    }
    return value;
  }

  void align() {
    bit = (bit + 7) & ~7;
  }
}

Float32List _unpack(Uint8List bytes, ByteData data, int five, int packing,
    int dataStart, int dataEnd, int count) {
  final reference = data.getFloat32(five + 11);
  final binary = _signMagnitude(data.getUint16(five + 15), 2);
  final decimal = _signMagnitude(data.getUint16(five + 17), 2);
  final bitsPerValue = bytes[five + 19];
  final scale = math.pow(2, binary).toDouble();
  final unscale = math.pow(10, -decimal).toDouble();
  final out = Float32List(count);

  if (packing == 0) {
    if (bitsPerValue == 0) {
      out.fillRange(0, count, reference * unscale);
      return out;
    }
    final bits = _Bits(bytes, dataStart);
    for (var i = 0; i < count; i++) {
      out[i] = (reference + bits.read(bitsPerValue) * scale) * unscale;
    }
    return out;
  }
  if (packing != 2 && packing != 3) {
    throw FormatException('GRIB2 packing template $packing is not supported');
  }

  if (bytes[five + 22] != 0) {
    throw const FormatException('GRIB2 missing value codes are not supported');
  }
  final groups = data.getUint32(five + 31);
  final widthReference = bytes[five + 35];
  final widthBits = bytes[five + 36];
  final lengthReference = data.getUint32(five + 37);
  final lengthIncrement = bytes[five + 41];
  final lastLength = data.getUint32(five + 42);
  final lengthBits = bytes[five + 46];
  var order = 0;
  var extraBytes = 0;
  if (packing == 3) {
    order = bytes[five + 47];
    extraBytes = bytes[five + 48];
  }

  var at = dataStart;
  var first = 0;
  var second = 0;
  var minimum = 0;
  if (order > 0) {
    first = _signedBytes(data, at, extraBytes);
    at += extraBytes;
    if (order == 2) {
      second = _signedBytes(data, at, extraBytes);
      at += extraBytes;
    }
    minimum = _signedBytes(data, at, extraBytes);
    at += extraBytes;
  }

  final bits = _Bits(bytes, at);
  final references = Int32List(groups);
  if (bitsPerValue > 0) {
    for (var g = 0; g < groups; g++) {
      references[g] = bits.read(bitsPerValue);
    }
  }
  bits.align();
  final widths = Uint8List(groups);
  for (var g = 0; g < groups; g++) {
    widths[g] = widthReference + (widthBits > 0 ? bits.read(widthBits) : 0);
  }
  bits.align();
  final lengths = Int32List(groups);
  for (var g = 0; g < groups; g++) {
    lengths[g] =
        lengthReference + (lengthBits > 0 ? bits.read(lengthBits) : 0) * lengthIncrement;
  }
  if (groups > 0) {
    lengths[groups - 1] = lastLength;
  }
  bits.align();

  final ints = Int64List(count);
  var n = 0;
  for (var g = 0; g < groups && n < count; g++) {
    final width = widths[g];
    final reference = references[g];
    final len = math.min(lengths[g], count - n);
    if (width == 0) {
      for (var i = 0; i < len; i++) {
        ints[n++] = reference;
      }
    } else {
      for (var i = 0; i < len; i++) {
        ints[n++] = reference + bits.read(width);
      }
    }
  }
  if (n < count) {
    throw const FormatException('GRIB2 data section is cut short');
  }

  if (order == 1) {
    ints[0] = first;
    for (var i = 1; i < count; i++) {
      ints[i] = ints[i] + minimum + ints[i - 1];
    }
  } else if (order == 2) {
    ints[0] = first;
    ints[1] = second;
    for (var i = 2; i < count; i++) {
      ints[i] = ints[i] + minimum + 2 * ints[i - 1] - ints[i - 2];
    }
  }
  for (var i = 0; i < count; i++) {
    out[i] = (reference + ints[i] * scale) * unscale;
  }
  return out;
}
