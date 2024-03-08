import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import 'fis_graphics.dart';

class Product {

  final DateTime time;
  final Uint8List data;
  final LatLng? coordinate;
  FisGraphics fisGraphics = FisGraphics();

  Product(this.time, this.data, this.coordinate);

  void parse() {
    fisGraphics.decode(data);
  }
}