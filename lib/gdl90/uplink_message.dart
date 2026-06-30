import 'dart:typed_data';

import 'package:avaremp/storage.dart';
import 'package:latlong2/latlong.dart';

import 'fis_buffer.dart';
import 'message.dart';

class UplinkMessage extends Message {

  FisBuffer? fis;
  LatLng? groundStation;
  bool positionValid = false;
  int slotId = 0;
  int tisbSiteId = 0;

  UplinkMessage(super.type);

  @override
  void parse(Uint8List message) {
    /*
     * First 3 bytes are Zulu time,
     * Next 8 is UAT header
     * Rest of 424 is payload
     *
     */
    if (message.length < 11) {
      return;
    }
    int skip = 3;
    int lat = 0;
    lat += (message[skip + 0].toInt()) & 0xFF;
    lat <<= 8;
    lat += (message[skip + 1].toInt()) & 0xFF;
    lat <<= 8;
    lat += (message[skip + 2].toInt()) & 0xFE;
    lat >>= 1;

    bool isSouth = (lat & 0x800000) != 0;
    double degLat = lat.toDouble() * 2.1457672E-5;
    if (isSouth) {
      degLat *= -1;
    }

    int lon = 0;
    lon += (message[skip + 3].toInt()) & 0xFF;
    lon <<= 8;
    lon += (message[skip + 4].toInt()) & 0xFF;
    lon <<= 8;
    lon += (message[skip + 5].toInt()) & 0xFE;
    lon >>= 1;
    if ((message[skip + 2].toInt() & 0x01) != 0) {
      lon += 0x800000;
    }

    bool isWest = (lon & 0x800000) != 0;
    double degLon = (lon & 0x7fffff) * 2.1457672E-5;
    if (isWest) {
      degLon = -1 * (180 - degLon);
    }

    positionValid = (message[skip + 5].toInt() & 0x01) != 0;

    bool applicationDataValid = (message[skip + 6].toInt() & 0x20) != 0;
    if (false == applicationDataValid) {
      return;
    }

    // byte 6 bits 0-4: slot ID; byte 7 upper nibble: TIS-B site ID (0 = no TIS-B)
    slotId = message[skip + 6].toInt() & 0x1F;
    tisbSiteId = (message[skip + 7].toInt() & 0xF0) >> 4;

    // The uplink frame carries the position of the transmitting ground
    // station ("tower"). Record it for the ADS-B reception indicator, skipping
    // an unlocked 0,0 position.
    if (!(degLat == 0 && degLon == 0)) {
      groundStation = LatLng(degLat, degLon);
      Storage().adsbStatus.reportGroundStation(groundStation!);
    }

    // byte 9-432: application data (multiple iFrames).
    skip = 3 + 8;

    Uint8List data = message.sublist(skip);
    FisBuffer fisBuffer = FisBuffer(data, LatLng(degLat, degLon)); // this product does not happen at a location?

    //Now decode all.
    fisBuffer.makeProducts();
    fis = fisBuffer;
  }

  @override
  String decode() {
    String station = groundStation == null
        ? "-"
        : "${groundStation!.latitude.toStringAsFixed(4)}\u00b0, ${groundStation!.longitude.toStringAsFixed(4)}\u00b0";
    int count = fis?.products.length ?? 0;

    StringBuffer products = StringBuffer("Products: $count");
    if (fis != null) {
      for (final p in fis!.products) {
        // Indent continuation lines so each product reads as one block.
        products.write("\n\u2022 ${p.decode().replaceAll("\n", "\n  ")}");
      }
    }

    return "Ground station: $station\n"
        "Position valid: ${positionValid ? "yes" : "no"}\n"
        "Slot ID: $slotId\n"
        "TIS-B site ID: ${tisbSiteId == 0 ? "none" : tisbSiteId}\n"
        "$products";
  }

  @override
  String summary() {
    if (fis == null || fis!.products.isEmpty) {
      return "";
    }
    // Distinct product types, preserving first-seen order.
    final List<String> names = [];
    for (final p in fis!.products) {
      final String n = p.shortName();
      if (!names.contains(n)) {
        names.add(n);
      }
    }
    return names.join(", ");
  }
}