import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class Constants {

  static const int tileWidth = 512;
  static const int tileHeight = 512;

  static const Color appBarButtonColor = Colors.cyanAccent;
  static const Color bottomNavBarButtonColor = Colors.cyanAccent;
  static const Color bottomSheetTitleColor = Colors.cyanAccent;

  static const Color dropDownButtonColor = Colors.cyanAccent;
  static const Color dropDownButtonIconColor = Colors.transparent;
  static Color dropDownButtonBackgroundColor = Colors.black.withAlpha(156);
  static Color centerButtonBackgroundColor = Colors.black.withAlpha(156);

  static const Color chartAbsentColor = Colors.grey;
  static const Color chartCurrentColor = Colors.green;
  static const Color chartExpiredColor = Colors.red;

  static const Color mapBackgroundColor = Colors.black;

  static const Color instrumentsNormalValueColor = Colors.white;
  static const Color instrumentsNormalLabelColor = Colors.white;

  static Color appBarBackgroundColor = Colors.black.withAlpha(100);
  static Color bottomNavBarBackgroundColor = Colors.black.withAlpha(100);




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

}