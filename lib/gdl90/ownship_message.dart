import 'dart:typed_data';
import 'package:avaremp/storage.dart';
import 'package:latlong2/latlong.dart';

import 'message.dart';

class OwnShipMessage extends Message {

  double altitude = -305;
  LatLng coordinates = const LatLng(0, 0);
  int icao = 0;
  double velocity = 0;
  double verticalSpeed = 0;
  double heading = 0;
  bool airborne = false;
  bool extrapolated = false;
  int trackType = 0;
  int nic = 0;
  int nacp = 0;

  OwnShipMessage(super.type);

  // Track/heading type from the low 2 bits of the misc indicator nibble.
  static const Map<int, String> trackTypes = {
    0: "Not valid", 1: "True track angle", 2: "Magnetic heading",
    3: "True heading",
  };

  @override
  void parse(Uint8List message) {
    if (message.length < 17) {
      return;
    }

    icao = (((message[1]).toInt() & 0xFF) << 16) + ((((message[2].toInt()) & 0xFF) << 8)) + (((message[3].toInt()) & 0xFF));
    double lat = calculateDegrees((message[4].toInt() & 0xFF), (message[5].toInt() & 0xFF), (message[6].toInt() & 0xFF));
    double lon = calculateDegrees((message[7].toInt() & 0xFF), (message[8].toInt() & 0xFF), (message[9].toInt() & 0xFF));
    coordinates = LatLng(lat, lon);

    int upper = ((message[10].toInt() & 0xFF)) << 4;
    int lower = ((message[11].toInt() & 0xF0)) >> 4;
    int alt = upper + lower;
    if (alt != 0xFFF) {
      alt *= 25;
      alt -= 1000;
      if (alt < -1000) {
        alt = -1000;
      }
      // meter
      altitude = alt.toDouble() * Storage().units.fToM;
    }

    airborne = (message[11] & 0x08) != 0;
    extrapolated = (message[11] & 0x04) != 0;
    trackType = message[11].toInt() & 0x03;

    // navigation integrity / accuracy categories
    nic = (message[12].toInt() & 0xF0) >> 4;
    nacp = message[12].toInt() & 0x0F;

    upper = ((message[13].toInt() & 0xFF)) << 4;
    lower = ((message[14].toInt() & 0xF0)) >> 4;

    if (upper == 0xFF0 && lower == 0xF) {
    }
    else {
      // m/s
      velocity = ((upper.toDouble() + lower.toDouble()) * 0.514444);
    }

    // vs
    if ((message[14].toInt() & 0x08) == 0) {
      verticalSpeed = ((message[14].toInt() & 0x0F) << 14) + ((message[15].toInt() & 0xFF) << 6).toDouble();
    }
    else if (message[15].toInt() == 0) {
      verticalSpeed = 2000000000;
    }
    else {
      verticalSpeed = (((message[14].toInt() & 0x0F) << 14) + ((message[15].toInt() & 0xFF) << 6) - 0x40000).toDouble();
    }

    // heading / track
    heading = ((message[16].toInt() & 0xFF).toDouble() * 1.40625); // heading resolution 1.40625
  }

  @override
  String decode() {
    double altFt = altitude * Storage().units.mToF;
    double kts = velocity / 0.514444;
    return "ICAO: ${icao.toRadixString(16).toUpperCase().padLeft(6, '0')} ($icao)\n"
        "Latitude: ${coordinates.latitude.toStringAsFixed(5)}\u00b0\n"
        "Longitude: ${coordinates.longitude.toStringAsFixed(5)}\u00b0\n"
        "Altitude: ${altFt.toStringAsFixed(0)} ft (${altitude.toStringAsFixed(0)} m)\n"
        "Ground speed: ${kts.toStringAsFixed(0)} kt (${velocity.toStringAsFixed(1)} m/s)\n"
        "Track/heading: ${heading.toStringAsFixed(0)}\u00b0 (${trackTypes[trackType] ?? "?"})\n"
        "Vertical speed: ${verticalSpeed.toStringAsFixed(0)} fpm\n"
        "NIC: $nic\n"
        "NACp: $nacp\n"
        "Report: ${extrapolated ? "extrapolated" : "updated"}\n"
        "Airborne: ${airborne ? "yes" : "no"}";
  }

  static double calculateDegrees(int highByte, int midByte, int lowByte) {
    int position = 0;
    double xx;

    position = highByte;
    position <<= 8;
    position |= midByte;
    position <<= 8;
    position |= lowByte;
    position &= 0xFFFFFFFF;

    if ((position & 0x800000) != 0) {
      int yy;

      position |= 0xFFFFFFFFFF000000; //ints are 64 bit in dart

      yy = position;
      xx = yy.toDouble();
    }
    else {
      xx = (position & 0x7FFFFF).toDouble();
    }

    xx *= 2.1457672E-5; // low lat resolution

    return xx;
  }
}