
// Each chart in a list, color gray mean not downloaded, green means downloaded and current, red means downloaded and expired

import 'package:flutter/cupertino.dart';

import 'download.dart';

class Chart {
  String _name;
  String _filename;
  IconData _icon;
  int _state;
  double _progress; // 0 to 1 = 100%
  String _subtitle;
  Color _color;
  bool _enabled;
  Download _download;

  Chart(this._name, this._color, this._icon, this._filename, this._state, this._subtitle, this._progress, this._enabled, this._download);

  String get name => _name;

  set name(String value) {
    _name = value;
  }

  String get filename => _filename;

  set filename(String value) {
    _filename = value;
  }

  IconData get icon => _icon;

  set icon(IconData value) {
    _icon = value;
  }

  int get state => _state;

  set state(int value) {
    _state = value;
  }

  double get progress => _progress;

  set progress(double value) {
    _progress = value;
  }

  String get subtitle => _subtitle;

  set subtitle(String value) {
    _subtitle = value;
  }

  Color get color => _color;

  set color(Color value) {
    _color = value;
  }

  bool get enabled => _enabled;

  set enabled(bool value) {
    _enabled = value;
  }

  Download get download => _download;

  set download(Download value) {
    _download = value;
  }
}

// Chart category like sectional, IFR, ...
class ChartCategory {

  static const String sectional = "Sectional";
  static const String tac = "TAC";
  static const String ifrl = "IFR Low";
  static const String plates = "Plates";
  static const String databases = "Databases";
  static const String csup = "CSUP";

  String _title;
  Color _color;
  List<Chart> _charts;
  ChartCategory(this._title, this._color, this._charts);

  String get title => _title;

  set title(String value) {
    _title = value;
  }

  Color get color => _color;

  set color(Color value) {
    _color = value;
  }

  List<Chart> get charts => _charts;

  set charts(List<Chart> value) {
    _charts = value;
  }

  static String chartTypeToIndex(String type) {
    switch(type) {
      case sectional:
        return "0";
      case tac:
        return "1";
      case ifrl:
        return "2";
    }
    return "";
  }

  static double chartTypeToZoom(String type) {
    switch(type) {
      case sectional:
        return 10;
      case tac:
        return 12;
      case ifrl:
        return 10;
    }
    return 5;
  }

}


