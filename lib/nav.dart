import 'package:avaremp/destination.dart';
import 'package:flutter/material.dart';

class Nav {
  static String parse(NavDestination nav) {
    return "Type ${nav.type}\nClass ${nav.class_}\nElevation ${nav.elevation.round()}\nVariation ${nav.variation}";
  }

  static Widget mainWidget(String data) {
    return Text(data);
  }
}
