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

  // Human-readable summary for the ADS-B message log. Overridden per product.
  String decode() => "Product (file $productFileId, ${data.length} bytes)";

  // Short label used in the collapsed uplink summary (e.g. "METAR", "NEXRAD").
  String shortName() => "Product";

  /// Shared summary for graphical FIS-B products parsed through [fisGraphics]
  /// (SIGMET, AIRMET, SUA, textual NOTAM). [name] is the product label.
  String graphicsSummary(String name) {
    if (!fisGraphics.valid) {
      return "$name (no graphics)";
    }
    final List<String> lines = [name];
    if (fisGraphics.location.isNotEmpty) {
      lines.add("Location: ${fisGraphics.location}");
    }
    if (fisGraphics.coordinates.isNotEmpty) {
      lines.add("Vertices: ${fisGraphics.coordinates.length}");
    }
    if (fisGraphics.startTime.isNotEmpty) {
      lines.add("Start: ${fisGraphics.startTime}");
    }
    if (fisGraphics.endTime.isNotEmpty) {
      lines.add("End: ${fisGraphics.endTime}");
    }
    final String txt = fisGraphics.text.replaceAll("\n", " ").trim();
    if (txt.isNotEmpty) {
      lines.add(txt);
    }
    return lines.join("\n");
  }
}