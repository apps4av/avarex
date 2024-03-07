import 'dart:typed_data';

import 'package:avaremp/gdl90/product.dart';
import 'package:avaremp/gdl90/product_factory.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

class FisBuffer {

  Uint8List buffer;
  List<Product> products = [];
  FisBuffer(this.buffer, this.coordinate);
  LatLng? coordinate;

  //Parse products out of the Fis
  void makeProducts() {
    int size = buffer.lengthInBytes;
    int count = 0;
    while (count < (size - 1)) {

      int iFrameLength = ((buffer[count].toInt()) & 0xFF) << 1;
      iFrameLength += ((buffer[count + 1].toInt()) & 0x80) >> 7;

      if (0 == iFrameLength) {
        break;
      }

      int frameType = ((buffer[count + 1].toInt()) & 0x0F);

      //Bad frame, or reserved frame ! = 0
      if ((count + 2 + iFrameLength) > size || frameType != 0) {
        break;
      }

      Uint8List fis = buffer.sublist(count + 2, count + 2 + iFrameLength);

      try {
        Product? p = ProductFactory.buildProduct(fis, coordinate);
        if(p != null) {
          products.add(p);
        }
      }
      catch(e) {}

      count += iFrameLength + 2;
    }
  }
}
