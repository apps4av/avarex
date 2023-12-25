import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:avaremp/path_utils.dart';
import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_settings.dart';
import 'db_general.dart';
import 'gps.dart';

class Storage extends ChangeNotifier {
  static final Storage _instance = Storage._internal();

  factory Storage() {
    return _instance;
  }

  Storage._internal();

  // one second timer for simulation
  Timer scheduleTimeout([int milliseconds = 1000]) =>
      Timer(Duration(milliseconds: milliseconds), handleTimeout);

  void handleTimeout() async {  // callback function
    position = await _gps.getCurrentPosition();
    gpsChange.notifyListeners(); // tell everyone
    scheduleTimeout();
  }

  final gpsChange = ValueNotifier<int>(0);
  final plateChange = ValueNotifier<int>(1);

  Future<void> init() async {
    DbGeneral.set(); // set database platform
    WidgetsFlutterBinding.ensureInitialized();
    await WakelockPlus.enable(); // keep screen on
    LocationPermission permission = await _gps.checkPermissions();
    if(LocationPermission.denied == permission ||
        LocationPermission.deniedForever == permission ||
        LocationPermission.unableToDetermine == permission) {
    }
    bool enabled = await _gps.checkEnabled();
    position = await Gps().getLastPosition();
    dataDir = await PathUtils.getDownloadDirPath();
    await settings.initSettings();
    scheduleTimeout();
  }


  // for navigation on tabs
  final GlobalKey globalKeyBottomNavigationBar = GlobalKey();

  final _gps = Gps();
  String dataDir = "";

  late Position position;

  final AppSettings settings = AppSettings();

  ui.Image? imagePlate;
  final TransformationController plateTransformationController = TransformationController();
  String lastPlateAirport = "";
  String currentPlate = "";
  List<double>? matrixPlate;

  Future<void> loadPlate() async {
    String path = await PathUtils.getPlateFilePath(settings.getCurrentPlateAirport(), currentPlate);
    if(currentPlate.startsWith("CSUP:")) {
      // all CSUP plates are appended by CSUP so remove it
      path = await PathUtils.getCSupFilePath(currentPlate.replaceFirst("CSUP:", ""));
    }
    File file = File(path);
    Completer<ui.Image> completerPlate = Completer();
    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    }
    catch(e) {
      ByteData bd = await rootBundle.load('assets/images/black.png');
      // file bad or not found
      bytes = bd.buffer.asUint8List();
    }
    Map<String, IfdTag> exif = await readExifFromBytes(bytes);
    matrixPlate = null;
    IfdTag? tag = exif["EXIF UserComment"];
    if(null != tag) {
      List<String> tokens = tag.toString().split("|");
      if(tokens.length == 4) {
        matrixPlate = [];
        matrixPlate!.add(double.parse(tokens[0]));
        matrixPlate!.add(double.parse(tokens[1]));
        matrixPlate!.add(double.parse(tokens[2]));
        matrixPlate!.add(double.parse(tokens[3]));
      }
    }

    ui.decodeImageFromList(bytes, (ui.Image img) {
      return completerPlate.complete(img);
    });
    if(imagePlate != null) {
      imagePlate!.dispose();
      imagePlate = null;
    }
    imagePlate = await completerPlate.future;
    plateChange.notifyListeners(); // change in storage
  }

  resetPlate() {
    plateTransformationController.value.setEntry(0, 0, 1);
    plateTransformationController.value.setEntry(1, 1, 1);
    plateTransformationController.value.setEntry(2, 2, 1);
    plateTransformationController.value.setEntry(0, 3, 0);
    plateTransformationController.value.setEntry(1, 3, 0);
  }

}
