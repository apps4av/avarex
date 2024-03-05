import 'package:avaremp/gdl90/product.dart';

class NexradProduct extends Product {
  NexradProduct(super.time, super.data);

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
      //Make a list of empty blocks
      full = [];
      empty = [];
      empty.add(block);
      int bitmapLen = data[index].toInt() & 0x0F;

      if ((data[index].toInt() & 0x10) != 0) {
        empty.add(block + 1);
      }

      if ((data[index].toInt() & 0x20) != 0) {
        empty.add(block + 2);
      }

      if ((data[index].toInt() & 0x30) != 0) {
        empty.add(block + 3);
      }

      if ((data[index].toInt() & 0x40) != 0) {
        empty.add(block + 4);
      }

      for (int i = 1; i < bitmapLen; i++) {
        if ((data[index + i].toInt() & 0x01) != 0) {
          empty.add(block + i * 8 - 3);
        }

        if ((data[index + i].toInt() & 0x02) != 0) {
          empty.add(block + i * 8 - 2);
        }

        if ((data[index + i].toInt() & 0x04) != 0) {
          empty.add(block + i * 8 - 1);
        }

        if ((data[index + i].toInt() & 0x08) != 0) {
          empty.add(block + i * 8 - 0);
        }

        if ((data[index + i].toInt() & 0x10) != 0) {
          empty.add(block + i * 8 + 1);
        }

        if ((data[index + i].toInt() & 0x20) != 0) {
          empty.add(block + i * 8 + 2);
        }

        if ((data[index + i].toInt() & 0x40) != 0) {
          empty.add(block + i * 8 + 3);
        }

        if ((data[index + i].toInt() & 0x80) != 0) {
          empty.add(block + i * 8 + 4);
        }
      }
    }
  }

}