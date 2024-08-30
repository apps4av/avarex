
// Each chart in a list, color gray mean not downloaded, green means downloaded and current, red means downloaded and expired

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'download.dart';

class Chart {
  String name;
  String filename;
  IconData icon;
  int state;
  String subtitle;
  Color color;
  bool enabled;
  Download download;
  ValueNotifier<int> progress = ValueNotifier<int>(0); // 0 to 100 and <0 for error

  Chart(this.name, this.color, this.icon, this.filename, this.state, this.subtitle, this.progress, this.enabled, this.download);

  static String getChartRegion(int x, int y, int z) {
    List<(LatLngBounds, String)> regionCoordinates = [
      (LatLngBounds(const LatLng(71, -180), const LatLng(51, -126)), "ak"),   // Alaska
      (LatLngBounds(const LatLng(24, -162), const LatLng(18, -152)), "pac"),   // Pacific
      (LatLngBounds(const LatLng(50, -125), const LatLng(40, -103)), "nw"),   // Northwest
      (LatLngBounds(const LatLng(40, -125), const LatLng(15, -103)), "sw"),   // Southwest
      (LatLngBounds(const LatLng(50, -105), const LatLng(37, -90)), "nc"),   // North Central
      (LatLngBounds(const LatLng(50, -95),  const LatLng(37, -80)), "ec"),   // East Central
      (LatLngBounds(const LatLng(37, -110), const LatLng(15, -90)), "sc"),   // South Central
      (LatLngBounds(const LatLng(50, -80),  const LatLng(37, -60)), "ne"),   // Northeast
      (LatLngBounds(const LatLng(37, -90),  const LatLng(15, -60)), "se"),   // Southeast
    ];

    // find lat/lon from tile number, upper left
    num n = pow(2, z);
    double lon = x / n * 360.0 - 180.0;
    double lat = 2 * atan(exp((180 - (y / n) * 360) * pi / 180)) * 180 / pi - 90;

    for (var region in regionCoordinates) {
      if(region.$1.contains(LatLng(lat, lon))) {
        return region.$2;
      }
    }
    return "";
  }

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
        return 10;
      case tac:
        return 11;
      case ifrl:
        return 10;
      case ifrh:
        return 9;
      case ifra:
        return 11;
      case heli:
        return 12;
      case flyway:
        return 11;
    }
    return 5;
  }

}


