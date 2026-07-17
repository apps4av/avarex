import 'dart:typed_data';
import 'package:avaremp/gdl90/ownship_message.dart';
import 'package:avaremp/storage.dart';
import 'package:latlong2/latlong.dart';

import 'message.dart';

/// Why a traffic report was dropped by TrafficCache (not shown on the map).
/// Used by the ADS-B status log to color-code filtered aircraft.
enum TrafficFilter {
  none,     // displayed
  ownship,  // matched our ownship ICAO/callsign ("that's us")
  range,    // outside the current puck distance/altitude window
}

class TrafficReportMessage extends Message {
  double altitude = -305;
  LatLng coordinates = const LatLng(0, 0);
  int icao = 0;
  double velocity = 0;
  double verticalSpeed = 0;
  double heading = 0;
  String callSign = "";
  bool airborne = false;
  bool extrapolated = false;
  int emitter = 0;
  int alertStatus = 0;
  int addressType = 0;
  int nic = 0;
  int nacp = 0;
  int emergencyCode = 0;
  TrafficFilter filter = TrafficFilter.none; // set by TrafficCache.putTraffic

  TrafficReportMessage(super.type);

  @override
  void parse(Uint8List message) {
    if (message.length < 26) {
      return;
    }

    // upper nibble of byte 0 = traffic alert status, lower nibble = address type
    alertStatus = (message[0].toInt() & 0xF0) >> 4;
    addressType = message[0].toInt() & 0x0F;

    icao = (((message[1]).toInt() & 0xFF) << 16) + ((((message[2].toInt()) & 0xFF) << 8)) + (((message[3].toInt()) & 0xFF));
    double lat = OwnShipMessage.calculateDegrees((message[4].toInt() & 0xFF), (message[5].toInt() & 0xFF), (message[6].toInt() & 0xFF));
    double lon = OwnShipMessage.calculateDegrees((message[7].toInt() & 0xFF), (message[8].toInt() & 0xFF), (message[9].toInt() & 0xFF));
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
    }
    altitude = alt.toDouble();


    /*
     * next nibble is miscellaneous indicators:
     * bit 3   bit 2    bit 1    bit 0
     *   x       x        0        0    = heading not valid
     *   x       x        0        1    = heading is true track angle
     *   x       x        1        0    = heading is magnetic heading
     *   x       x        1        1    = heading is true heading
     *   x       0        x        x    = report is updated
     *   x       1        x        x    = report is extrapolated
     *   0       x        x        x    = on ground
     *   1       x        x        x    = airborne
     */
    airborne = (message[11].toInt() & 0x08) != 0;
    extrapolated = (message[11].toInt() & 0x04) != 0;

    // navigation integrity / accuracy categories
    nic = (message[12].toInt() & 0xF0) >> 4;
    nacp = message[12].toInt() & 0x0F;

    upper = ((message[13].toInt() & 0xFF)) << 4;
    lower = ((message[14].toInt() & 0xF0)) >> 4;

    if (upper == 0xFF0 && lower == 0xF) {
    }
    else {
      // knots
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

    emitter = message[17].toInt() & 0xFF;

    // call sign from 18 to 25
    Uint8List call = message.sublist(18, 26);
    callSign = String.fromCharCodes(call).replaceAll(RegExp("[^a-zA-Z0-9]"), "");

    // emergency/priority code occupies the upper nibble of byte 26 when present
    if (message.length >= 27) {
      emergencyCode = (message[26].toInt() & 0xF0) >> 4;
    }

    Storage().trafficCache.putTraffic(this);
  }

  static const Map<int, String> _emitters = {
    0: "No info", 1: "Light", 2: "Small", 3: "Large", 4: "High-vortex large",
    5: "Heavy", 6: "Highly maneuverable", 7: "Rotorcraft", 9: "Glider",
    10: "Lighter-than-air", 11: "Parachutist", 12: "Ultralight", 14: "UAV",
    15: "Spacecraft", 17: "Surface emergency", 18: "Surface service",
    19: "Point obstacle", 20: "Cluster obstacle", 21: "Line obstacle",
  };

  static const Map<int, String> _addressTypes = {
    0: "ADS-B (ICAO)", 1: "ADS-B (self-assigned)", 2: "TIS-B (ICAO)",
    3: "TIS-B (track file)", 4: "Surface vehicle", 5: "Ground station beacon",
  };

  static const Map<int, String> _emergencyCodes = {
    0: "None", 1: "General", 2: "Medical", 3: "Minimum fuel",
    4: "No communication", 5: "Unlawful interference", 6: "Downed aircraft",
  };

  /// Fields common to traffic, basic and long reports.
  String commonDecode() {
    double kts = velocity / 0.514444;
    return "Callsign: ${callSign.isEmpty ? "-" : callSign}\n"
        "ICAO: ${icao.toRadixString(16).toUpperCase().padLeft(6, '0')} ($icao)\n"
        "Latitude: ${coordinates.latitude.toStringAsFixed(5)}\u00b0\n"
        "Longitude: ${coordinates.longitude.toStringAsFixed(5)}\u00b0\n"
        "Altitude: ${altitude.toStringAsFixed(0)} ft\n"
        "Ground speed: ${kts.toStringAsFixed(0)} kt\n"
        "Track/heading: ${heading.toStringAsFixed(0)}\u00b0\n"
        "Vertical speed: ${verticalSpeed.toStringAsFixed(0)} fpm\n"
        "Emitter: ${_emitters[emitter] ?? "Unknown"} ($emitter)\n"
        "Report: ${extrapolated ? "extrapolated" : "updated"}\n"
        "Airborne: ${airborne ? "yes" : "no"}";
  }

  @override
  String decode() =>
      "Alert: ${alertStatus == 0 ? "none" : "traffic"}\n"
      "Address type: ${_addressTypes[addressType] ?? "Reserved ($addressType)"}\n"
      "NIC: $nic\n"
      "NACp: $nacp\n"
      "Emergency: ${_emergencyCodes[emergencyCode] ?? "Reserved ($emergencyCode)"}\n"
      "${commonDecode()}";

}
