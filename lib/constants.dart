import 'package:flutter/material.dart';

class Constants {
  static const bool useK = true;
  static const weatherUpdateTimeMin = 10;

  static const int _hashIntCoprimeSeed = 23;
  static const int _hashIntCoprimeMultiplier = 31;

  static const double _kMetersToFeet = 3.28084;
  static const double _kMpsToKnotsConv = 1.0 / 0.514444;  

  static const int kMaxIntValue = 0x7FFFFFFFFFFFFFFF;

  @pragma("vm:prefer-inline")
  static double mToFt(double meters) { return _kMetersToFeet * meters; }
  @pragma("vm:prefer-inline")
  static double mpsToKt(double metersPerSecond) { return _kMpsToKnotsConv * metersPerSecond; }  
  static double mToNm(double meters) {return 0.000539957 * meters;}
  static double nmToM(distance) {return distance / 0.000539957;}
  static String secondsToHHmm(int seconds) {
    final Duration duration = Duration(seconds: seconds);
    final List<String> tokens = duration.toString().split(":");
    return("${tokens[0].padLeft(2, "0")}:${tokens[1].padLeft(2, "0")}");
  }

  /// Hash function to get a unique hash value for a given set of integer parameters, based on the
  /// algorithm in "Effective Java [2nd ed.]" by Josh Bloch; see https://stackoverflow.com/questions/892618/create-a-hashcode-of-two-numbers
  @pragma("vm:prefer-inline")
  static int hashInts(final List<int> ints) {
    int hash = _hashIntCoprimeSeed;
    for (int i = 0; i < ints.length; i++) {
      hash = hash * _hashIntCoprimeMultiplier + ints[i];
    }
    return hash;
  }

  static const Color appBarButtonColor = Colors.white;

  static const Color dropDownButtonIconColor = Colors.transparent;
  static Color dropDownButtonBackgroundColor = Colors.black.withAlpha(156);
  static Color centerButtonBackgroundColor = Colors.black.withAlpha(156);
  static Color runwayColor = Colors.white.withAlpha(100);
  static Color runwayMapColor = Colors.pinkAccent;

  static const Color chartAbsentColor = Colors.grey;
  static const Color chartCurrentColor = Colors.green;
  static const Color chartExpiredColor = Colors.red;

  static const Color mapBackgroundColor = Colors.black;

  static const Color instrumentsNormalValueColor = Colors.white;
  static const Color instrumentsNormalLabelColor = Colors.white;

  static Color appBarBackgroundColor = Colors.transparent;
  static Color instrumentBackgroundColor = Colors.black26.withAlpha(156);
  static Color bottomNavBarBackgroundColor = Colors.black.withAlpha(156);

  static double dropDownButtonFontSize = 14;

  static double carouselAspectRatio(BuildContext context) {
    return isPortrait(context) ? 0.625 : 2.5;
  }

  static double bottomPaddingSize(BuildContext context) {
    return MediaQuery.of(context).padding.bottom;
  }
  static double screenHeight(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }
  static double screenWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }

  static bool isPortrait(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.portrait;
  }

  static const Color distanceCircleColor = Color.fromARGB(200, 58, 58, 58);
  static const Color speedCircleColor = Color.fromARGB(200, 0, 255, 0);
  static const Color planCurrentColor = Colors.purpleAccent;
  static const Color planNextColor = Colors.grey;
  static const Color planPassedColor = Colors.cyanAccent;
  static const Color trackColor = Colors.blue;
  static const Color tracksColor = Colors.green;
  static const Color planBorderColor = Colors.black;
  static const Color planeColor = Color.fromARGB(150, 255, 0, 0);
  static const Color plateMarkColor = Color.fromARGB(150, 0, 255, 0);
  static const Color tfrColor = Color.fromARGB(150, 255, 0, 0);
  static const Color tfrColorFuture = Color.fromARGB(150, 255, 103, 2);

}