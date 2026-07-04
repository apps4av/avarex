import 'dart:typed_data';

/// Port of the Avidyne AviSDK `Crc32Bit` class.
///
/// Uses the ARINC-665 / MPEG-2 style CRC-32 with polynomial 0x04C11DB7,
/// an initial value of 0, MSB-first processing and no final XOR / reflection.
/// This must match the IFD byte-for-byte or uploaded routes are rejected with
/// a file CRC error.
class AvidyneCrc32 {
  static final Uint32List _table = _generateTable();

  int _value = 0;

  static Uint32List _generateTable() {
    const int polynomial = 0x04C11DB7;
    final Uint32List table = Uint32List(256);
    for (int i = 0; i < 256; i++) {
      int crc = (i << 24) & 0xFFFFFFFF;
      for (int j = 0; j < 8; j++) {
        if ((crc & 0x80000000) != 0) {
          crc = ((crc << 1) ^ polynomial) & 0xFFFFFFFF;
        } else {
          crc = (crc << 1) & 0xFFFFFFFF;
        }
      }
      table[i] = crc;
    }
    return table;
  }

  void reset() {
    _value = 0;
  }

  void add(List<int> data, [int? length]) {
    final int len = length ?? data.length;
    for (int i = 0; i < len; i++) {
      final int tempChar = data[i] & 0xFF;
      _value = (((_value << 8) & 0xFFFFFFFF) ^
              tempChar ^
              _table[(_value >> 24) & 0xFF]) &
          0xFFFFFFFF;
    }
  }

  int get value => _value & 0xFFFFFFFF;

  /// Convenience one-shot computation.
  static int compute(List<int> data) {
    final AvidyneCrc32 crc = AvidyneCrc32();
    crc.add(data);
    return crc.value;
  }
}
