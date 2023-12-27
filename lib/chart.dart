
// Each chart in a list, color gray mean not downloaded, green means downloaded and current, red means downloaded and expired

import 'package:flutter/cupertino.dart';

import 'download.dart';

class Chart {
  String name;
  String filename;
  IconData icon;
  int state;
  double progress; // 0 to 1 = 100%
  String subtitle;
  Color color;
  bool enabled;
  Download download;

  Chart(this.name, this.color, this.icon, this.filename, this.state, this.subtitle, this.progress, this.enabled, this.download);

}

// Chart category like sectional, IFR, ...
class ChartCategory {

  static const String sectional = "Sectional";
  static const String tac = "TAC";
  static const String ifrl = "IFR Low";
  static const String plates = "Plates";
  static const String databases = "Databases";
  static const String csup = "CSUP";

  String title;
  Color color;
  List<Chart> charts;
  ChartCategory(this.title, this.color, this.charts);


  static String chartTypeToIndex(String type) {
    switch(type) {
      case sectional:
        return "0";
      case tac:
        return "1";
      case ifrl:
        return "3";
    }
    return "";
  }

  static double chartTypeToZoom(String type) {
    switch(type) {
      case sectional:
        return 10;
      case tac:
        return 11;
      case ifrl:
        return 10;
    }
    return 5;
  }

}


