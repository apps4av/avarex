import 'dart:typed_data';
import 'package:avaremp/gdl90/product.dart';
import 'package:avaremp/gdl90/sigmet_product.dart';
import 'package:avaremp/gdl90/sua_product.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'airmet_product.dart';
import 'textual_weather_product.dart';
import 'nexrad_high_product.dart';
import 'nexrad_medium_product.dart';
import 'notam_product.dart';

class ProductFactory {

  static Map<int, List<Product>> segmentedProducts = {};

  static Product? buildProduct(Uint8List fis, LatLng? coordinate) {
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

    int productFileId = 0;
    int productFileLength = 0;
    int apduNumber = 0;
    if (segFlag) {
      productFileId = s.getBits(10);
      productFileLength = s.getBits(9);
      apduNumber = s.getBits(9);
    }

    int totalRead = s.totalRead();
    int total = fis.lengthInBytes;

    int length = total - totalRead;
    int offset = totalRead;
    Uint8List data = fis.sublist(offset, offset + length);

    Product? p;
    DateTime time = DateTime(DateTime.now().year, month, day, hours, mins, secs); // ignore this
    time = DateTime.now().toUtc();

    switch (productID) {
      case 8:
        p = NotamProduct(time, data, coordinate, productFileId, productFileLength, apduNumber, segFlag);  // NOTAM graphics
        break;
      case 9:
        break;
      case 10:
        break;
      case 11:
        p = AirmetProduct(time, data, coordinate, productFileId, productFileLength, apduNumber, segFlag);  // AIRMET graphics
        break;
      case 12:
        p = SigmetProduct(time, data, coordinate, productFileId, productFileLength, apduNumber, segFlag);  // SIGMET graphics
        break;
      case 13:
        p = SuaProduct(time, data, coordinate, productFileId, productFileLength, apduNumber, segFlag); // SUA graphics
        break;
      case 63:
        p = NexradHighProduct(time, data, coordinate, productFileId, productFileLength, apduNumber, segFlag);
        break;
      case 64:
        p = NexradMediumProduct(time, data, coordinate, productFileId, productFileLength, apduNumber, segFlag);
        break;
      case 413:
        p = TextualWeatherProduct(time, data, coordinate, productFileId, productFileLength, apduNumber, segFlag); // MEATR, TAF, SPECI, WINDS, PIREP
        break;
      default:
        break;
    }

    if (null != p) {
      if(p.segFlag && p.apduNumber != 0 && p.apduNumber <= p.productFileLength && p.productFileLength != 0) {
        // based on productFieldId, collect all segments in segmented products, where location in the list of a particular productFieldId is apduNumber-1
        int index = p.apduNumber - 1;
        List<Product>? list = segmentedProducts[productFileId];
        if(list != null) {
          // already have it
          list[index] = p;
        }
        else {
          // do not have it
          list = List<Product>.filled(p.productFileLength, p, growable: false);
          segmentedProducts[productFileId] = list;
        }
        // if we have all segments, combine them, return the combined product and remove from segmented products
        bool complete = true;
        for(int count = 0; count <= p.productFileLength - 1; count++) {
          if(list[count].apduNumber != count + 1) {
            // not all segments in yet
            complete = false;
            break;
          }
        }
        if(complete) {
          // segment complete, combine it
          segmentedProducts.remove(productFileId);
          // combine all data segments of each product segment
          p = list[0];
          for(int count = 1; count < p.productFileLength; count++) {
            Uint8List data = list[count].data.sublist(6);
            p.data = Uint8List.fromList(p.data + data);
          }
        }
        else {
          p = null;
        }
      }
    }

    if(p != null) {
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