import 'package:avaremp/gdl90/product.dart';
import 'package:avaremp/storage.dart';

class NexradProduct extends Product {
  NexradProduct(super.time, super.data, super.coordinate, super.productFileId, super.productFileLength, super.apduNumber, super.segFlag);

  static const int numRows = 4;
  static const int numCols = 32;

  static final List<int> _intensity = [
    0x00000000,
    0x00000000,
    0x7F007F00, // dark green
    0x7F00AF00, // light green
    0x7F00FF00, // lighter green
    0x7FFFFF00, // yellow
    0x7FFF7F00, // orange
    0x7FFF0000  // red
  ];

  int block = -1;
  List<int> full = [];
  List<int> empty = [];

  @override
  void parse() {

    // Get blocks, skip first 3.
    bool elementIdentifier = ((data[0]).toInt() & 0x80) != 0; // RLE or Empty?

    int len = data.lengthInBytes;
    block = (data[0].toInt() & 0x0F) << 16;
    block += (data[1].toInt() & 0xFF) << 8;
    block += data[2].toInt() & 0xFF;

    int index = 3;

    //Decode blocks RLE encoded
    if (elementIdentifier) {
      // Each row element is 1 minute (4 minutes total)
      // Each col element is 1.5 minute (48 minutes total)
      full = List<int>.filled(numCols * numRows, _intensity[0]);
      empty = [];

      int j = 0;
      int i;
      while (index < len) {
        int numberOfBins = ((data[index].toInt() & 0xF8) >> 3) + 1;
        for (i = 0; i < numberOfBins; i++) {
          if (j >= full.length) {
            full = [];
            return;
          }
          full[j] = _intensity[(data[index].toInt() & 0x07)];
          j++;
        }
        index++;
      }
    }
    else {
      // Empty Element bitmap — see SBS Description Doc Appendix G.1.1.2.3
      // and Table G-3. Byte 4 holds the 4-bit bitmap length L in its low
      // nibble (bits 5-8 per the spec, where bit 1 = MSB) and four bitmap
      // bits in its high nibble for BN+1..BN+4. L additional bytes follow.
      full = [];
      empty = [];
      empty.add(block);

      final int header = data[index].toInt();
      final int bitmapLen = header & 0x0F;

      if ((header & 0x10) != 0) empty.add(block + 1); // byte 4, bit 4
      if ((header & 0x20) != 0) empty.add(block + 2); // byte 4, bit 3
      if ((header & 0x40) != 0) empty.add(block + 3); // byte 4, bit 2
      if ((header & 0x80) != 0) empty.add(block + 4); // byte 4, bit 1

      for (int i = 1; i <= bitmapLen; i++) {
        if (index + i >= len) {
          break;
        }
        final int b = data[index + i].toInt();
        // Within each subsequent byte, bit 8 (LSB) maps to the lowest
        // additional offset and bit 1 (MSB) to the highest, matching
        // Table G-3.
        if ((b & 0x01) != 0) empty.add(block + i * 8 - 3);
        if ((b & 0x02) != 0) empty.add(block + i * 8 - 2);
        if ((b & 0x04) != 0) empty.add(block + i * 8 - 1);
        if ((b & 0x08) != 0) empty.add(block + i * 8);
        if ((b & 0x10) != 0) empty.add(block + i * 8 + 1);
        if ((b & 0x20) != 0) empty.add(block + i * 8 + 2);
        if ((b & 0x40) != 0) empty.add(block + i * 8 + 3);
        if ((b & 0x80) != 0) empty.add(block + i * 8 + 4);
      }
    }
    Storage().nexradCache.putImg(this);
  }

}