import 'package:auto_size_text/auto_size_text.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../gps.dart';
import '../storage.dart';

class Nav {
  static final GeoCalculations _geo = GeoCalculations();
  static final Map<String, String> _morseMap = {
    "A": ".-",
    "B": "-...",
    "C": "-.-.",
    "D": "-..",
    "E": ".",
    "F": "..-.",
    "G": "--.",
    "H": "....",
    "I": "..",
    "J": ".---",
    "K": "-.-",
    "L": ".-..",
    "M": "--",
    "N": "-.",
    "O": "---",
    "P": ".--.",
    "Q": "--.-",
    "R": ".-.",
    "S": "...",
    "T": "-",
    "U": "..-",
    "V": "...-",
    "W": ".--",
    "X": "-..-",
    "Y": "-.--",
    "Z": "--..",
    "0": "-----",
    "1": ".----",
    "2": "..---",
    "3": "...--",
    "4": "....-",
    "5": ".....",
    "6": "-....",
    "7": "--...",
    "8": "---..",
    "9": "----."
  };

  static String? _getMorseCode(String character) {
    return _morseMap[character.toUpperCase()];
  }

  static String? _getMorseCodeFromString(String text) {
    String result = "";
    for (int i = 0; i < text.length; i++) {
      result += _getMorseCode(text[i]) ?? "";
    }
    return result.replaceAll(".", "\u00B0");
  }

  // From VOR map from database, get the VOR parameters and combine to make a string
  static String getVorLine(NavDestination vor) {
    LatLng current = Gps.toLatLng(Storage().position);
    String location = "${_geo.calculateDistance(current, vor.coordinate).round().toString().padLeft(3, "0")}"
        "/${GeoCalculations.getMagneticHeading(_geo.calculateBearing(current, vor.coordinate), Storage().area.variation).round().toString().padLeft(3, "0")}";
    return "${vor.locationID} $location ${vor.class_} ${vor.facilityName} ${_getMorseCodeFromString(vor.locationID)}";
  }

  static String parse(NavDestination nav) {
    return "Type ${nav.type}\nClass ${nav.class_}\nElevation ${nav.elevation.round()}\n${_getMorseCodeFromString(nav.locationID)}\n";
  }

  static Widget mainWidget(String data) {
    return AutoSizeText(data, minFontSize: 4, maxFontSize: 15, overflow: TextOverflow.visible);
  }

}
