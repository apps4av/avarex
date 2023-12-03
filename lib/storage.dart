import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:avaremp/path_utils.dart';
import 'package:avaremp/scale.dart';

class Storage {
  static final Storage _singleton = Storage._internal();
  Storage._internal();

  factory Storage() {
    return _singleton;
  }

  ui.Image? _imagePlate;

  final Scale _scalePlate = Scale.n();

  String _currentPlate = "AIRPORT-DIAGRAM";
  String _currentPlateAirport = "BVY";

  Future<void> loadPlate() async {
    String path = await PathUtils.getPlateFilePath(_currentPlateAirport, _currentPlate);
    File file = File(path);
    Completer<ui.Image> completerPlate = Completer();
    Uint8List bytes = await file.readAsBytes();
    ui.decodeImageFromList(bytes, (ui.Image img) {
      return completerPlate.complete(img);
    });
    if(_imagePlate != null) {
      _imagePlate!.dispose();
      _imagePlate = null;
    }
    _imagePlate = await completerPlate.future;
  }

  ui.Image? get imagePlate => _imagePlate;

  Scale get scalePlate => _scalePlate;

  String get currentPlate => _currentPlate;

  set currentPlate(String value) {
    _currentPlate = value;
  }

  String get currentPlateAirport => _currentPlateAirport;

  set currentPlateAirport(String value) {
    _currentPlateAirport = value;
  }
}