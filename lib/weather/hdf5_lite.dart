import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Reads one-dimensional numeric variables out of a NetCDF4 (HDF5) file.
///
/// This is not a general HDF5 library. It reads what the GOES lightning files
/// use: a version 2 or 3 superblock, version 2 object headers, and variables stored
/// contiguous or in chunks (version 3 layout, B-tree v1 index) with the shuffle
/// and deflate filters. Anything else throws a [FormatException].
class Hdf5Lite {
  final Uint8List _bytes;
  late final ByteData _data;

  Hdf5Lite(this._bytes) {
    _data = ByteData.sublistView(_bytes);
    const signature = [0x89, 0x48, 0x44, 0x46, 0x0d, 0x0a, 0x1a, 0x0a];
    if (_bytes.length < 48) {
      throw const FormatException('Not an HDF5 file');
    }
    for (var i = 0; i < signature.length; i++) {
      if (_bytes[i] != signature[i]) {
        throw const FormatException('Not an HDF5 file');
      }
    }
    final version = _bytes[8];
    if (version != 2 && version != 3) {
      throw FormatException('HDF5 superblock version $version is not supported');
    }
    if (_bytes[9] != 8 || _bytes[10] != 8) {
      throw const FormatException('Only 8 byte HDF5 offsets are supported');
    }
  }

  /// The values of variable [name], or null when the file has no such variable.
  Float64List? vector(String name) {
    final header = _find(name);
    if (header == null) {
      return null;
    }
    return _read(header);
  }

  /// A group's links are plain text in the file: a name length, the name, and the
  /// address of the object. Finding that pattern works whether the group keeps its
  /// links in its header or in a heap, and an address that is not an object header
  /// is never accepted.
  int? _find(String name) {
    final needle = name.codeUnits;
    final last = _bytes.length - needle.length - 8;
    for (var i = 1; i <= last; i++) {
      if (_bytes[i] != needle[0] || _bytes[i - 1] != needle.length) {
        continue;
      }
      var same = true;
      for (var k = 1; k < needle.length; k++) {
        if (_bytes[i + k] != needle[k]) {
          same = false;
          break;
        }
      }
      if (!same) {
        continue;
      }
      final address = _data.getUint64(i + needle.length, Endian.little);
      if (_isHeader(address)) {
        return address;
      }
    }
    return null;
  }

  bool _isHeader(int address) {
    return address > 0 &&
        address + 6 < _bytes.length &&
        _bytes[address] == 0x4f &&
        _bytes[address + 1] == 0x48 &&
        _bytes[address + 2] == 0x44 &&
        _bytes[address + 3] == 0x52 &&
        _bytes[address + 4] == 2;
  }

  /// Object header messages by type, following continuation blocks.
  Map<int, Uint8List> _messages(int header) {
    final flags = _bytes[header + 5];
    var p = header + 6;
    if ((flags & 0x20) != 0) {
      p += 16;
    }
    if ((flags & 0x10) != 0) {
      p += 4;
    }
    final sizeBytes = 1 << (flags & 3);
    var chunk = 0;
    for (var i = 0; i < sizeBytes; i++) {
      chunk |= _bytes[p + i] << (8 * i);
    }
    p += sizeBytes;
    final blocks = <(int, int)>[(p, p + chunk - 4)];
    final out = <int, Uint8List>{};
    while (blocks.isNotEmpty) {
      final block = blocks.removeAt(0);
      var at = block.$1;
      while (at + 4 <= block.$2) {
        final type = _bytes[at];
        final size = _data.getUint16(at + 1, Endian.little);
        var body = at + 4;
        if ((flags & 0x04) != 0) {
          body += 2;
        }
        if (body + size > _bytes.length) {
          throw const FormatException('HDF5 header is cut short');
        }
        if (type == 0x10) {
          final offset = _data.getUint64(body, Endian.little);
          final length = _data.getUint64(body + 8, Endian.little);
          if (offset + length > _bytes.length) {
            throw const FormatException('HDF5 header is cut short');
          }
          blocks.add((offset + 4, offset + length - 4));
        } else if (type != 0) {
          out.putIfAbsent(
              type, () => Uint8List.sublistView(_bytes, body, body + size));
        }
        at = body + size;
      }
    }
    return out;
  }

  Float64List _read(int header) {
    final messages = _messages(header);
    final space = messages[0x01];
    final type = messages[0x03];
    final layout = messages[0x08];
    if (space == null || type == null) {
      throw const FormatException('HDF5 variable is incomplete');
    }
    final count = _count(space);
    if (count == 0) {
      return Float64List(0);
    }
    if (layout == null) {
      throw const FormatException('HDF5 variable has no storage');
    }
    final element = _Element.parse(type);
    final raw = Uint8List(count * element.size);
    final filters = _filters(messages[0x0b]);
    final ld = ByteData.sublistView(layout);
    if (layout[0] != 3) {
      throw FormatException('HDF5 layout version ${layout[0]} is not supported');
    }
    switch (layout[1]) {
      case 1:
        final address = ld.getUint64(2, Endian.little);
        final size = ld.getUint64(10, Endian.little);
        if (address + size > _bytes.length || size < raw.length) {
          throw const FormatException('HDF5 data is cut short');
        }
        raw.setRange(0, raw.length,
            Uint8List.sublistView(_bytes, address, address + raw.length));
        break;
      case 2:
        final rank = layout[2];
        if (rank != 2) {
          throw const FormatException('Only one-dimensional variables are supported');
        }
        final tree = ld.getUint64(3, Endian.little);
        final chunkElements = ld.getUint32(11, Endian.little);
        _readChunks(tree, rank, chunkElements, element.size, filters, raw);
        break;
      default:
        throw FormatException('HDF5 layout class ${layout[1]} is not supported');
    }
    return element.decode(raw, count);
  }

  int _count(Uint8List space) {
    final version = space[0];
    final rank = space[1];
    var at = version == 1 ? 8 : 4;
    if (version == 2 && space[3] == 0) {
      return 1; // scalar
    }
    if (version == 2 && space[3] == 2) {
      return 0; // null
    }
    final data = ByteData.sublistView(space);
    var total = 1;
    for (var i = 0; i < rank; i++) {
      total *= data.getUint64(at, Endian.little);
      at += 8;
    }
    return total;
  }

  List<int> _filters(Uint8List? message) {
    if (message == null) {
      return const [];
    }
    final version = message[0];
    final count = message[1];
    final data = ByteData.sublistView(message);
    var at = version == 1 ? 8 : 2;
    final ids = <int>[];
    for (var i = 0; i < count; i++) {
      final id = data.getUint16(at, Endian.little);
      at += 2;
      var nameLength = 0;
      if (version == 1 || id >= 256) {
        nameLength = data.getUint16(at, Endian.little);
        at += 2;
      }
      at += 2; // flags
      final values = data.getUint16(at, Endian.little);
      at += 2;
      at += nameLength;
      if (version == 1 && nameLength > 0) {
        at = (at + 7) & ~7;
      }
      at += values * 4;
      if (version == 1 && values.isOdd) {
        at += 4;
      }
      ids.add(id);
    }
    return ids;
  }

  void _readChunks(int tree, int rank, int chunkElements, int elementSize,
      List<int> filters, Uint8List out) {
    if (tree + 24 > _bytes.length ||
        _bytes[tree] != 0x54 ||
        _bytes[tree + 1] != 0x52 ||
        _bytes[tree + 2] != 0x45 ||
        _bytes[tree + 3] != 0x45) {
      throw const FormatException('HDF5 chunk index is not a B-tree');
    }
    final level = _bytes[tree + 5];
    final used = _data.getUint16(tree + 6, Endian.little);
    final keySize = 8 + rank * 8;
    var at = tree + 24;
    for (var i = 0; i < used; i++) {
      final size = _data.getUint32(at, Endian.little);
      final mask = _data.getUint32(at + 4, Endian.little);
      final offset = _data.getUint64(at + 8, Endian.little);
      final child = _data.getUint64(at + keySize, Endian.little);
      at += keySize + 8;
      if (level > 0) {
        _readChunks(child, rank, chunkElements, elementSize, filters, out);
        continue;
      }
      if (child + size > _bytes.length) {
        throw const FormatException('HDF5 chunk is cut short');
      }
      var chunk = Uint8List.sublistView(_bytes, child, child + size);
      // Filters were applied in listed order, so undo them last to first.
      for (var f = filters.length - 1; f >= 0; f--) {
        if ((mask & (1 << f)) != 0) {
          continue;
        }
        switch (filters[f]) {
          case 1:
            chunk = Uint8List.fromList(ZLibDecoder().decodeBytes(chunk));
            break;
          case 2:
            chunk = _unshuffle(chunk, elementSize);
            break;
          default:
            throw FormatException('HDF5 filter ${filters[f]} is not supported');
        }
      }
      final start = offset * elementSize;
      final room = out.length - start;
      if (start < 0 || room <= 0) {
        continue;
      }
      final take = chunk.length < room ? chunk.length : room;
      out.setRange(start, start + take, chunk);
    }
  }

  static Uint8List _unshuffle(Uint8List shuffled, int size) {
    final count = shuffled.length ~/ size;
    final out = Uint8List(shuffled.length);
    for (var k = 0; k < size; k++) {
      for (var i = 0; i < count; i++) {
        out[i * size + k] = shuffled[k * count + i];
      }
    }
    return out;
  }
}

class _Element {
  final int kind; // 0 integer, 1 float
  final int size;
  final bool signed;
  final Endian endian;

  const _Element(this.kind, this.size, this.signed, this.endian);

  factory _Element.parse(Uint8List type) {
    final kind = type[0] & 0x0f;
    final size = ByteData.sublistView(type).getUint32(4, Endian.little);
    final endian = (type[1] & 1) != 0 ? Endian.big : Endian.little;
    if (kind == 0) {
      return _Element(0, size, (type[1] & 8) != 0, endian);
    }
    if (kind == 1 && (size == 4 || size == 8)) {
      return _Element(1, size, true, endian);
    }
    throw FormatException('HDF5 data type $kind of size $size is not supported');
  }

  Float64List decode(Uint8List raw, int count) {
    final data = ByteData.sublistView(raw);
    final out = Float64List(count);
    for (var i = 0; i < count; i++) {
      final at = i * size;
      if (kind == 1) {
        out[i] = size == 4
            ? data.getFloat32(at, endian)
            : data.getFloat64(at, endian);
        continue;
      }
      switch (size) {
        case 1:
          out[i] = (signed ? data.getInt8(at) : data.getUint8(at)).toDouble();
          break;
        case 2:
          out[i] = (signed ? data.getInt16(at, endian) : data.getUint16(at, endian))
              .toDouble();
          break;
        case 4:
          out[i] = (signed ? data.getInt32(at, endian) : data.getUint32(at, endian))
              .toDouble();
          break;
        case 8:
          out[i] = data.getInt64(at, endian).toDouble();
          break;
        default:
          throw FormatException('HDF5 integer size $size is not supported');
      }
    }
    return out;
  }
}
