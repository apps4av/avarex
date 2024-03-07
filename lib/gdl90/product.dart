import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

class Product {

  final DateTime time;
  final Uint8List line;
  final LatLng? coordinate;

  Product(this.time, this.line, this.coordinate);

  void parse() {

  }
}