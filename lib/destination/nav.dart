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
    "A": "o-",
    "B": "-ooo",
    "C": "-o-o",
    "D": "-oo",
    "E": "o",
    "F": "oo-o",
    "G": "--o",
    "H": "oooo",
    "I": "oo",
    "J": "o---",
    "K": "-o-",
    "L": "o-oo",
    "M": "--",
    "N": "-o",
    "O": "---",
    "P": "o--o",
    "Q": "--o-",
    "R": "o-o",
    "S": "ooo",
    "T": "-",
    "U": "oo-",
    "V": "ooo-",
    "W": "o--",
    "X": "-oo-",
    "Y": "-o--",
    "Z": "--oo",
    "0": "-----",
    "1": "o----",
    "2": "oo---",
    "3": "ooo--",
    "4": "oooo-",
    "5": "ooooo",
    "6": "-oooo",
    "7": "--ooo",
    "8": "---oo",
    "9": "----o"
  };

  static String? _getMorseCode(String character) {
    return _morseMap[character.toUpperCase()];
  }

  static String? _getMorseCodeFromString(String text) {
    String result = "";
    for (int i = 0; i < text.length; i++) {
      result += _getMorseCode(text[i]) ?? "";
    }
    return result;
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
