import 'dart:typed_data';
import 'package:avaremp/gdl90/product.dart';
import 'package:flutter/foundation.dart';

import 'Id63NexradProduct.dart';
import 'Id64NexradConusProduct.dart';

class ProductFactory {

  static Product? buildProduct(Uint8List fis) {
    BitInputStream s = BitInputStream(fis);

    bool flagAppMethod = s.getBits(1) != 0;
    bool flagGeoLocator = s.getBits(1) != 0;
    s.getBits(1); /* Provider spec flag, discard */

    int productID = s.getBits(11);

    if (flagAppMethod) {
      s.getBits(8);
    }

    if (flagGeoLocator) {
      s.getBits(20);
    }

    bool segFlag = s.getBits(1) != 0;

    int timeOpts = s.getBits(2);

    // 00 - No day, No sec
    // 01 - sec
    // 10 - day
    // 11 - day, sec
    int month = -1, day = -1, hours = -1, mins = -1, secs = -1;
    if ((timeOpts & 0x02) != 0) {
      month = s.getBits(4);
      day = s.getBits(5);
    }
    hours = s.getBits(5);
    mins = s.getBits(6);
    if ((timeOpts & 0x01) != 0) {
      secs = s.getBits(6);
    }

    if (segFlag) {
      // uncommon
      return null;
    }

    int totalRead = s.totalRead();
    int total = fis.lengthInBytes;

    int length = total - totalRead;
    int offset = totalRead;
    Uint8List data = fis.sublist(offset, offset + length);

    Product? p;
    DateTime time = DateTime(DateTime.now().year, month, day, hours, mins, secs);

    switch (productID) {
      case 8:
        break;
      case 9:
        break;
      case 10:
        break;
      case 11:
        break;
      case 12:
        break;
      case 13:
        break;
      case 63:
        p = Id63NexradProduct(time, data);
        break;
      case 64:
        p = Id64NexradConusProduct(time, data);
        break;
      case 413:
        break;
      default:
        break;
    }

    if (null != p) {
      p.parse();
    }

    return (p);
  }
}

class BitInputStream {

  Uint8List buffer;
  int location = 0;
  int bitsLeft = 8;
  int iBuffer = 0;

  BitInputStream(this.buffer) {
    iBuffer = (buffer[0].toInt()) & 0xFF;
  }

  int getBits(int aNumberOfBits) {
    int value = 0;
    int num = aNumberOfBits;
    while (num-- > 0) {
      value <<= 1;
      value |= readBit();
    }
    return value;
  }

  int readBit() {
    if (bitsLeft == 0) {
      iBuffer = (buffer[++location].toInt()) & 0xFF;
      bitsLeft = 8;
    }

    bitsLeft--;
    int bit = (iBuffer >> bitsLeft) & 0x1;

    bit = (bit == 0) ? 0 : 1;

    return bit;
  }

  int totalRead() {
    return location + 1;
  }
}