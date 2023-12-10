import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:avaremp/path_utils.dart';
import 'package:exif/exif.dart';
import 'package:flutter/cupertino.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_settings.dart';
import 'db_general.dart';
import 'gps.dart';

class Storage {
  static final Storage _instance = Storage._internal();

  factory Storage() {
    return _instance;
  }

  Storage._internal();

  Future<void> init() async {
    DbGeneral.set(); // set database platform
    WidgetsFlutterBinding.ensureInitialized();
    await WakelockPlus.enable(); // keep screen on
    await Gps.checkPermissions();
    Gps.getUpdates();
    await _settings.initSettings();
  }

  final AppSettings _settings = AppSettings();

  AppSettings get settings => _settings;

  ui.Image? _imagePlate;
  final TransformationController _plateTransformationController = TransformationController();
  Map<String, IfdTag>? _exifPlate;
  String _currentPlate = "";
  String _currentPlateAirport = "BVY";
  String _lastPlateAirport = "";

  set lastPlateAirport(String value) {
    _lastPlateAirport = value;
  }
  String get lastPlateAirport => _lastPlateAirport;

  ui.Image? _imageCSup;
  final TransformationController _csupTransformationController = TransformationController();
  String _currentCSup = "";
  String _currentCSupAirport = "BVY";
  String _lastCSupAirport = "";

  String get lastCSupAirport => _lastCSupAirport;

  set lastCSupAirport(String value) {
    _lastCSupAirport = value;
  }

  Future<void> loadPlate() async {
    String path = await PathUtils.getPlateFilePath(_currentPlateAirport, _currentPlate);
    File file = File(path);
    Completer<ui.Image> completerPlate = Completer();
    Uint8List bytes = await file.readAsBytes();
    _exifPlate = await readExifFromBytes(bytes);
    ui.decodeImageFromList(bytes, (ui.Image img) {
      return completerPlate.complete(img);
    });
    if(_imagePlate != null) {
      _imagePlate!.dispose();
      _imagePlate = null;
    }
    _imagePlate = await completerPlate.future;
  }

  Future<void> loadCSup() async {
    String path = await PathUtils.getCSupFilePath(_currentCSup);
    File file = File(path);
    Completer<ui.Image> completerCSup = Completer();
    Uint8List bytes = await file.readAsBytes();
    ui.decodeImageFromList(bytes, (ui.Image img) {
      return completerCSup.complete(img);
    });
    if(_imageCSup != null) {
      _imageCSup!.dispose();
      _imageCSup = null;
    }
    _imageCSup = await completerCSup.future;
  }

  ui.Image? get imagePlate => _imagePlate;
  TransformationController get plateTransformationController => _plateTransformationController;
  Map<String, IfdTag>? get exifPlate => _exifPlate;
  String get currentPlate => _currentPlate;
  String get currentPlateAirport => _currentPlateAirport;

  set currentPlate(String value) {
    _currentPlate = value;
  }

  set currentPlateAirport(String value) {
    _lastPlateAirport = _currentPlateAirport;
    _currentPlateAirport = value;
  }


  ui.Image? get imageCSup => _imageCSup;
  TransformationController get csupTransformationController => _csupTransformationController;
  String get currentCSup => _currentCSup;
  String get currentCSupAirport => _currentCSupAirport;

  set currentCSup(String value) {
    _currentCSup = value;
  }

  set currentCSupAirport(String value) {
    _currentCSupAirport = value;
  }

}
