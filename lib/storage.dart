import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

// put all singletons here.

import 'package:avaremp/constants.dart';
import 'package:avaremp/download_screen.dart';
import 'package:avaremp/gdl90/gdl90_buffer.dart';
import 'package:avaremp/gdl90/message_factory.dart';
import 'package:avaremp/gdl90/ownship_message.dart';
import 'package:avaremp/gdl90/traffic_report_message.dart';
import 'package:avaremp/path_utils.dart';
import 'package:avaremp/plan_route.dart';
import 'package:avaremp/weather/airep_cache.dart';
import 'package:avaremp/weather/airsigmet_cache.dart';
import 'package:avaremp/weather/notam_cache.dart';
import 'package:avaremp/weather/taf_cache.dart';
import 'package:avaremp/weather/tfr_cache.dart';
import 'package:avaremp/udp_receiver.dart';
import 'package:avaremp/waypoint.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_settings.dart';
import 'data/db_general.dart';
import 'destination.dart';
import 'gdl90/message.dart';
import 'gps.dart';
import 'data/main_database_helper.dart';
import 'weather/metar_cache.dart';

class Storage {
  static final Storage _instance = Storage._internal();

  factory Storage() {
    return _instance;
  }

  Storage._internal();

  // on gps update
  final gpsChange = ValueNotifier<Position>(Gps.centerUSAPosition());
  // when plate changes
  final plateChange = ValueNotifier<int>(0);
  // when destination changes
  final timeChange = ValueNotifier<int>(0);
  final warningChange = ValueNotifier<bool>(false);
  late WindsCache winds;
  late MetarCache metar;
  late TafCache taf;
  late TfrCache tfr;
  late AirepCache airep;
  late AirSigmetCache airSigmet;
  late NotamCache notam;

  final PlanRoute _route = PlanRoute("New Plan");
  PlanRoute get route => _route;
  bool gpsLocked = true;
  int _lastMsGpsSignal = DateTime.now().millisecondsSinceEpoch;

  // gps
  final _gps = Gps();
  final _udp = UdpReceiver();
  // where all data is place. This is set on init in main
  late String dataDir;
  Position position = Gps.centerUSAPosition();
  final AppSettings settings = AppSettings();


  int _key = 1111;

  String getKey() {
    return (_key++).toString();
  }

  // make it double buffer to get rid of plate load flicker
  ui.Image? imagePlate;
  Uint8List? imageBytesPlate;
  LatLng? topLeftPlate;
  LatLng? bottomRightPlate;


  // to move the plate
  String lastPlateAirport = "";
  String currentPlate = "";
  List<double>? matrixPlate;
  bool dataExpired = false;
  bool chartsMissing = false;
  bool gpsNotPermitted = false;
  bool gpsDisabled = false;
  bool _gotGpsPosition = false;

  // for navigation on tabs
  final GlobalKey globalKeyBottomNavigationBar = GlobalKey();

  setDestination(Destination? destination) {
    if(destination != null) {
      route.addDirectTo(Waypoint(destination));
    }
  }

  StreamSubscription<Position>? _gpsStream;
  StreamSubscription<Uint8List>? _udpStream;

  void startGps() {
    // GPS data receive
    _gpsStream = _gps.getStream();
    _gpsStream?.onDone(() {
    });
    _gpsStream?.onError((obj){
    });
    _gpsStream?.onData((data) {
      position = data;
      gpsChange.value = position; // tell everyone
      _lastMsGpsSignal = DateTime.now().millisecondsSinceEpoch; // update time when GPS signal was last received
      _gotGpsPosition = true;
      route.update(); // change to route
    });
  }

  stopGps() {
    try {
      _gpsStream?.cancel();
    }
    catch(e) {}
  }


  final Gdl90Buffer _gdl90Buffer = Gdl90Buffer();

  void startUdp() {
    // GPS data receive
    _udpStream = _udp.getStream();
    _udpStream?.onDone(() {
    });
    _udpStream?.onError((obj){
    });
    _udpStream?.onData((data) {
      _gdl90Buffer.put(data);
      while(true) {
        Uint8List? message = _gdl90Buffer.get();
        if (null != message) {
          Message? m = MessageFactory.buildMessage(message);
          if(m != null && m.type == MessageType.ownShip) {
            OwnShipMessage m0 = m as OwnShipMessage;
            Position p = Position(longitude: m0.coordinates.longitude, latitude: m0.coordinates.latitude, timestamp: DateTime.timestamp(), accuracy: 0, altitude: m0.altitude, altitudeAccuracy: 0, heading: m0.heading, headingAccuracy: 0, speed: m0.velocity, speedAccuracy: 0);
            position = p;
            gpsChange.value = p;
          }
          if(m != null && m.type == MessageType.trafficReport) {
            TrafficReportMessage m0 = m as TrafficReportMessage;
          }
        }
        else {
          break;
        }
      }
    });
  }

  stopUdp() {
    try {
      _udpStream?.cancel();
      _udp.finish();
    }
    catch(e) {}
  }

  Future<void> init() async {
    DbGeneral.set(); // set database platform
    WidgetsFlutterBinding.ensureInitialized();
    await WakelockPlus.enable(); // keep screen on
    // ask for GPS permission
    await _gps.checkPermissions();
    position = await Gps().getLastPosition();
    Directory dir = await getApplicationDocumentsDirectory();
    dataDir = dir.path;
    await settings.initSettings();
    await checkChartsExist();
    await checkDataExpiry();

    String path = join(dataDir, "256.png");
    ByteData data = await rootBundle.load("assets/images/256.png");
    List<int> bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await File(path).writeAsBytes(bytes);
    await FlutterMapTileCaching.initialise();
    await FMTC.instance('mapStore').manage.createAsync(); // cache tiles

    winds = WeatherCache.make(WindsCache) as WindsCache;
    metar = WeatherCache.make(MetarCache) as MetarCache;
    taf = WeatherCache.make(TafCache) as TafCache;
    tfr = WeatherCache.make(TfrCache) as TfrCache;
    airep = WeatherCache.make(AirepCache) as AirepCache;
    airSigmet = WeatherCache.make(AirSigmetCache) as AirSigmetCache;
    notam = WeatherCache.make(NotamCache) as NotamCache;
    winds.download();
    metar.download();
    taf.download();
    tfr.download();
    airep.download();
    airSigmet.download();

    gpsNotPermitted = await Gps().checkPermissions();
    if(!gpsNotPermitted) {
      Gps().requestPermissions();
    }
    gpsDisabled = !(await Gps().checkEnabled());

    Timer.periodic(const Duration(seconds: 1), (tim) async {
      // this provides time to apps
      timeChange.value++;

      if(timeChange.value % 5 == 0) {
        if(settings.isInternalGps()) { // only for internal GPS
          if (!_gotGpsPosition) {
            gpsChange.value =
                position; // if GPS not sending, then keep sending last location
          }
          // check system for any issues
          gpsNotPermitted = await Gps().checkPermissions();
          gpsDisabled = !(await Gps().checkEnabled());
          warningChange.value =
              gpsNotPermitted || gpsDisabled || dataExpired || chartsMissing;
          int diff = DateTime
              .now()
              .millisecondsSinceEpoch - _lastMsGpsSignal;
          if (diff > 60000) { // 60 seconds, no GPS signal, send warning
            gpsLocked = false;
          }
          else {
            gpsLocked = true;
          }
        }
        else {
          // remove GPS warnings as its external now
          warningChange.value = dataExpired || chartsMissing;
        }
      }
      if((timeChange.value % (Constants.weatherUpdateTimeMin * 60)) == 0) {
        winds.download();
        metar.download();
        taf.download();
        tfr.download();
      }
      // check GPS enabled
    });
  }

  Future<void> checkDataExpiry() async {
    dataExpired = await DownloadScreenState.isAnyChartExpired();
  }

  Future<void> checkChartsExist() async {
    chartsMissing = !(await DownloadScreenState.doesAnyChartExists());
  }

  Future<void> loadPlate() async {
    String plateAirport = settings.getCurrentPlateAirport();
    String path = PathUtils.getPlatePath(dataDir, plateAirport, currentPlate);
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
    imageBytesPlate = bytes;

    // this should come from exif but it is legacy and needs to be fixed
    if(currentPlate == "AIRPORT-DIAGRAM") {
      matrixPlate = await MainDatabaseHelper.db.findAirportDiagramMatrix(plateAirport);
    }

    topLeftPlate = null;
    bottomRightPlate = null;

    ui.decodeImageFromList(bytes, (ui.Image img) {
      return completerPlate.complete(img);
    });
    ui.Image? image = await completerPlate.future; // double buffering
    if(imagePlate != null) {
      imagePlate!.dispose();
      imagePlate = null;
    }
    imagePlate = image;

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

        double dx = matrixPlate![0];
        double dy = matrixPlate![1];
        double lonTopLeft = matrixPlate![2];
        double latTopLeft = matrixPlate![3];
        double latBottomRight = latTopLeft + image.height / dy;
        double lonBottomRight = lonTopLeft + image.width / dx;
        topLeftPlate = LatLng(latTopLeft, lonTopLeft);
        bottomRightPlate = LatLng(latBottomRight, lonBottomRight);
      }
  }

    plateChange.value++; // change in storage
  }
}


class FileCacheManager {

  static final FileCacheManager _instance = FileCacheManager._internal();

  factory FileCacheManager() {
    return _instance;
  }

  FileCacheManager._internal();

  // this must be in a singleton class.
  final CacheManager networkCacheManager = CacheManager(Config("customCache", stalePeriod: const Duration(minutes: 1)));

}
