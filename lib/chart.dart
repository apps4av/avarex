
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
  static const String ifrh = "IFR High";
  static const String ifra = "IFR Area";
  static const String flyway = "Flyway";
  static const String heli = "Helicopter";
  static const String plates = "Plates";
  static const String databases = "Databases";
  static const String csup = "CSUP";

  String title;
  Color color;
  List<Chart> charts;
  bool isChart;

  ChartCategory(this.title, this.color, this.charts, this.isChart);

  static String chartTypeToIndex(String type) {
    switch(type) {
      case sectional:
        return "0";
      case tac:
        return "1";
      case ifrl:
        return "3";
      case ifrh:
        return "4";
      case ifra:
        return "5";
      case heli:
        return "9";
      case flyway:
        return "13";
    }
    return "";
  }

  static int chartTypeToZoom(String type) {
    switch(type) {
      case sectional:
        return 11;
      case tac:
        return 12;
      case ifrl:
        return 11;
      case ifrh:
        return 10;
      case ifra:
        return 12;
      case heli:
        return 13;
      case flyway:
        return 12;
    }
    return 5;
  }

}


