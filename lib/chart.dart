
// Each chart in a list, color gray mean not downloaded, green means downloaded and current, red means downloaded and expired
import 'dart:ui';

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

  static String sectional = "Sectional";
  static String tac = "TAC";
  static String ifrl = "IFR Low";
  static String plates = "Plates";
  static String databases = "Databases";

  String title;
  Color color;
  List<Chart> charts;
  ChartCategory(this.title, this.color, this.charts);
}


