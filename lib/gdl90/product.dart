import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import 'fis_graphics.dart';

class Product {

  final DateTime time;
  Uint8List data;
  final LatLng? coordinate;
  FisGraphics fisGraphics = FisGraphics();
  final int productFileId;
  final int productFileLength;
  final int apduNumber;
  final bool segFlag;

  Product(this.time, this.data, this.coordinate, this.productFileId, this.productFileLength, this.apduNumber, this.segFlag);

  void parse() {
    fisGraphics.decode(data);
  }
}