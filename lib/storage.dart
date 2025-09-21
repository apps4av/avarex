import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

// put all singletons here.

import 'package:avaremp/aircraft.dart';
import 'package:avaremp/app_log.dart';
import 'package:avaremp/area.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/download_screen.dart';
import 'package:avaremp/flight_status.dart';
import 'package:avaremp/gdl90/gdl90_buffer.dart';
import 'package:avaremp/gps_recorder.dart';
import 'package:avaremp/gdl90/message_factory.dart';
import 'package:avaremp/gdl90/nexrad_cache.dart';
import 'package:avaremp/gdl90/ownship_message.dart';
import 'package:avaremp/gdl90/traffic_cache.dart';
import 'package:avaremp/nmea/nmea_ownship_message.dart';
import 'package:avaremp/path_utils.dart';
import 'package:avaremp/pfd_painter.dart';
import 'package:avaremp/plan/plan_route.dart';
import 'package:avaremp/stack_with_one.dart';
import 'package:avaremp/unit_conversion.dart';
import 'package:avaremp/weather/airep_cache.dart';
import 'package:avaremp/weather/airsigmet_cache.dart';
import 'package:avaremp/weather/notam_cache.dart';
import 'package:avaremp/weather/taf_cache.dart';
import 'package:avaremp/weather/tfr_cache.dart';
import 'package:avaremp/udp_receiver.dart';
import 'package:avaremp/plan/waypoint.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'app_settings.dart';
import 'data/db_general.dart';
import 'package:avaremp/destination/destination.dart';
import 'download_manager.dart';
import 'flight_timer.dart';
import 'gdl90/message.dart';
import 'geojson_parser.dart';
import 'gps.dart';
import 'image_utils.dart';
import 'nmea/nmea_buffer.dart';
import 'nmea/nmea_message.dart';
import 'nmea/nmea_message_factory.dart';
import 'weather/metar_cache.dart';

class Storage {
  static final Storage _instance = Storage._internal();

  factory Storage() {
    return _instance;
  }

  Storage._internal();

  final pfdChange = ValueNotifier<int>(0);
  // on gps update
  final gpsChange = ValueNotifier<Position>(Gps.fromLatLng(LatLng(0, 0)));
  // when plate changes
  final plateChange = ValueNotifier<int>(0);
  // when destination changes
  final timeChange = ValueNotifier<int>(0);
  final timeRadarChange = ValueNotifier<int>(0);
  final rubberBandChange = ValueNotifier<int>(0); // when route is changed via rubber band, for testing with GPS
  final warningChange = ValueNotifier<bool>(false);
  final flightStatus = FlightStatus();
  late WindsCache winds;
  late MetarCache metar;
  late TafCache taf;
  late TfrCache tfr;
  late AirepCache airep;
  late ValueNotifier<ThemeData> themeNotifier;
  late AirSigmetCache airSigmet;
  late NotamCache notam;
  final NexradCache nexradCache = NexradCache();
  final Area area = Area();
  final TrafficCache trafficCache = TrafficCache();
  final StackWithOne<Position> _gpsStack = StackWithOne(Gps.fromLatLng(LatLng(0, 0)));
  ImageCache imageCache = ImageCache();
  int myAircraftIcao = 0;
  String myAircraftCallsign = "";
  int ownshipMessageIcao = 0;
  final PfdData pfdData = PfdData(); // a place to drive PFD
  GpsRecorder tracks = GpsRecorder();
  late final FlightTimer flightTimer;
  late final FlightTimer flightDownTimer;
  Destination? plateAirportDestination;
  late UnitConversion units;
  final DownloadManager downloadManager = DownloadManager();
  final GeoJsonParser geoParser = GeoJsonParser();

  List<bool> activeChecklistSteps = [];
  String activeChecklistName = "";
  static const gpsSwitchoverTimeMs = 30000; // switch GPS in 30 seconds

  final PlanRoute _route = PlanRoute("New Plan");
  PlanRoute get route => _route;
  bool gpsNoLock = false;
  int _lastMsGpsSignal = DateTime.now().millisecondsSinceEpoch;
  int get lastMsGpsSignal { return _lastMsExternalSignal; } // read-only timestamp exposed for audible alerts, among any other interested parties
  int _lastMsExternalSignal = DateTime.now().millisecondsSinceEpoch - gpsSwitchoverTimeMs;
  bool gpsInternal = true;

  // gps
  final _gps = Gps();
  final _udpReceiver = UdpReceiver();
  // where all data is place. This is set on init in main
  late String dataDir;
  late String cacheDir;
  late Position position;
  double vSpeed = 0;
  bool airborne = true;  
  final AppSettings settings = AppSettings();

  final Gdl90Buffer _gdl90Buffer = Gdl90Buffer();
  final NmeaBuffer _nmeaBuffer = NmeaBuffer();

  int _key = 1111;

  String getKey() {
    return (_key++).toString();
  }

  // make it double buffer to get rid of plate load flicker
  ui.Image? imagePlate;
  ui.Image? imagePlane;
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
  final List<String> _exceptions = [];

  // for navigation on tabs
  final GlobalKey globalKeyBottomNavigationBar = GlobalKey();

  void setDestination(Destination? destination) {
    if(destination != null) {
      route.addDirectTo(Waypoint(destination));
    }
  }

  /*
   * Ability to show warning messages to user when exceptions occur
   */
  List<String> getExceptions() {
    return _exceptions;
  }

  void setException(String value) {
    if(_exceptions.contains(value)) {
      return;
    }
    _exceptions.add(value.split('\n').first); // only first line
  }

  StreamSubscription<Position>? _gpsStream;
  StreamSubscription<Uint8List>? _udpStream;

  void startIO() {

    // GPS data receive
    // start both external and internal
    if(!gpsDisabled) {
      _gpsStream = _gps.getStream();
      _gpsStream?.onDone(() {});
      _gpsStream?.onError((obj) {});
      _gpsStream?.onData((data) {
        if (gpsInternal) {
          if(Gps.isPositionCloseToZero(data)) {
            return; // skip 0, 0 when GPS is not locked
          }
          _lastMsGpsSignal = DateTime.now().millisecondsSinceEpoch; // update time when GPS signal was last received
          _gpsStack.push(data);
          tracks.add(data);
        } // provide internal GPS when external is not available
      });
    }

    // GPS data receive
    _udpStream = _udpReceiver.getStream([4000, 43211, 49002, 5557], [false, false, false, false]); // 5557 is app to app comm
    _udpStream?.onDone(() {
    });
    _udpStream?.onError((obj){
    });
    _udpStream?.onData((data) {
      _gdl90Buffer.put(data);
      _nmeaBuffer.put(data);
      // gdl90
      while(true) {
        Uint8List? message = _gdl90Buffer.get();
        if (null != message) {
          Message? m = MessageFactory.buildMessage(message);
          if(m != null && m is OwnShipMessage) {
            Position p = Position(longitude: m.coordinates.longitude, latitude: m.coordinates.latitude, timestamp: DateTime.timestamp(), accuracy: 0, altitude: m.altitude, altitudeAccuracy: 0, heading: m.heading, headingAccuracy: 0, speed: m.velocity, speedAccuracy: 0);
            if(Gps.isPositionCloseToZero(p)) {
              continue; // skip 0, 0 when GPS is not locked
            }
            ownshipMessageIcao = m.icao;
            _lastMsGpsSignal = DateTime.now().millisecondsSinceEpoch; // update time when GPS signal was last received
            _lastMsExternalSignal = _lastMsGpsSignal; // start ignoring internal GPS
            _gpsStack.push(p);
            // Record additional ownship settings for audible alerts (among other interested parties)--or perhaps these can just reside here in Storage?
            vSpeed = m.verticalSpeed;
            airborne = m.airborne;
            // record waypoints for tracks.
            tracks.add(p);
          }
        }
        else {
          break;
        }
      }
      // nmea
      while(true) {
        Uint8List? message = _nmeaBuffer.get();
        if (null != message) {
          NmeaMessage? m = NmeaMessageFactory.buildMessage(message);
          if(m != null && m is NmeaOwnShipMessage) {
            NmeaOwnShipMessage m0 = m;
            Position p = Position(longitude: m0.coordinates.longitude, latitude: m0.coordinates.latitude, timestamp: DateTime.timestamp(), accuracy: 0, altitude: m0.altitude, altitudeAccuracy: 0, heading: m0.heading, headingAccuracy: 0, speed: m0.velocity, speedAccuracy: 0);
            if(Gps.isPositionCloseToZero(p)) {
              continue; // skip 0, 0 when GPS is not locked
            }
            ownshipMessageIcao = m0.icao;
            _lastMsGpsSignal = DateTime.now().millisecondsSinceEpoch; // update time when GPS signal was last received
            _lastMsExternalSignal = _lastMsGpsSignal; // start ignoring internal GPS
            vSpeed = m0.verticalSpeed;
            airborne = m0.altitude > 100;
            _gpsStack.push(p);
            tracks.add(p);
          }
        }
        else {
          break;
        }
      }
    });
    try {
      // Have traffic cache listen for GPS changes for distance calc and (resulting) audible alert changes
      gpsChange.addListener(Storage().trafficCache.updateTrafficDistancesAndAlerts);
    } catch (e) {
      AppLog.logMessage("Error adding GPS traffic cache listener: $e");
    }
  }

  void stopIO() {
    try {
      _udpStream?.cancel();
      _udpReceiver.finish();
    }
    catch(e) {
      AppLog.logMessage("Error stopping UDP: $e");
    }
    try {
      _gpsStream?.cancel();
    }
    catch(e) {
      AppLog.logMessage("Error stopping GPS: $e");
    }
    try {
      // Have audible alerts stop listening for GPS changes
      Storage().gpsChange.removeListener(TrafficCache().handleAudibleAlerts);    
    } catch (e) {
      AppLog.logMessage("Error removing GPS traffic cache listener: $e");
    }
  }

  Future<void> init() async {
    WidgetsFlutterBinding.ensureInitialized();
    Directory dir = await getApplicationDocumentsDirectory();
    dataDir = PathUtils.getFilePath(dir.path, "avarex"); // put files in a folder
    dir = await getApplicationSupportDirectory();
    cacheDir = dir.path; // for tiles cache
    dir = Directory(dataDir);
    if(!dir.existsSync()) {
      dir.createSync();
    }
    DbGeneral.set(); // set database platform

    await settings.initSettings();
    themeNotifier = ValueNotifier<ThemeData>(Storage().settings.isLightMode() ? ThemeData.light() : ThemeData.dark());
    units = UnitConversion(settings.getUnits());
    flightTimer = FlightTimer(true, 0, timeChange);
    flightDownTimer = FlightTimer(false, 30 * 60, timeChange); // 30 minute down timer
    WakelockPlus.enable().onError(
      (error, stackTrace) => {
        // wakelock is optional
      }
    ); // keep screen on
    // ask for GPS permission

    gpsNotPermitted = await Gps().isPermissionDenied().onError((error, stackTrace) => true);
    if(gpsNotPermitted) {
      Gps().requestPermissions().onError((error, stackTrace) => {});
    }
    gpsDisabled = await Gps().isDisabled().onError((error, stackTrace) => true);

    LatLng last = LatLng(settings.getCenterLatitude(), settings.getCenterLongitude());
    position = Gps.fromLatLng(last);
    _gpsStack.push(position);

    // don't await on this, but set when available, as DB access could take a few ms
    loadAircraftIds();

    // this is a long login process, do not await here

    await checkChartsExist();
    await checkDataExpiry();

    winds = WeatherCache.make(WindsCache) as WindsCache;
    metar = WeatherCache.make(MetarCache) as MetarCache;
    taf = WeatherCache.make(TafCache) as TafCache;
    tfr = WeatherCache.make(TfrCache) as TfrCache;
    airep = WeatherCache.make(AirepCache) as AirepCache;
    airSigmet = WeatherCache.make(AirSigmetCache) as AirSigmetCache;
    notam = WeatherCache.make(NotamCache) as NotamCache;

    // plane image
    imagePlane = await ImageUtils.loadImageFromAssets('plane.png');

    // set area
    await area.update(position);

    Timer.periodic(const Duration(milliseconds: 250), (tim) async {
      // this provides time to apps
      timeRadarChange.value++;
    });

    Timer.periodic(const Duration(seconds: 1), (tim) async {
      // this provides time to apps
      timeChange.value++;

      Position positionIn = _gpsStack.pop(); // used for testing and injecting GPS location
      position = Gps.clone(positionIn, area.geoAltitude);
      gpsChange.value = position; // tell everyone

      // update flight status
      flightStatus.update(position.speed);

      route.update(); // change to route
      int now = DateTime.now().millisecondsSinceEpoch;
      gpsInternal = ((_lastMsExternalSignal + gpsSwitchoverTimeMs) < now);

      int diff = now - _lastMsGpsSignal;
      if (diff > 2 * gpsSwitchoverTimeMs) { // no GPS signal from both sources, send warning
        gpsNoLock = true;
      }
      else {
        gpsNoLock = false;
      }

      if((timeChange.value % 15) == 0) {
        // update area every 15 seconds
        area.update(position);
      }

      if((timeChange.value % 5) == 0) {
        if(gpsInternal) {
          // check system for any issues
          bool permissionDenied = await Gps().isPermissionDenied().onError((error, stackTrace) => true);
          if(permissionDenied == false && gpsNotPermitted == true) {
            // restart GPS since permission was denied, and now its allowed
            stopIO();
            startIO();
          }
          gpsNotPermitted = permissionDenied;
          gpsDisabled = await Gps().isDisabled().onError((error, stackTrace) => true);
          warningChange.value =
              gpsNotPermitted || gpsDisabled || gpsNoLock || dataExpired || chartsMissing || _exceptions.isNotEmpty;
        }
        else {
          // remove GPS warnings as its external now
          warningChange.value = gpsNoLock || dataExpired || chartsMissing || _exceptions.isNotEmpty;
        }
      }

      if((timeChange.value % (10 * 60)) == 0) {
        // clear system image cache
        imageCache.clear();
        downloadWeather();
      }

    });

    downloadWeather();
  }

  Future<void> loadAircraftIds() async {
    final String acName = settings.getAircraft();
    if (acName.isEmpty) {
      // Reset, if there is no longer any aircraft selected (say all were deleted)
      myAircraftCallsign = "";
      myAircraftIcao = 0;
      return;
    }
    try {
      final Aircraft ac = await UserDatabaseHelper.db.getAircraft(acName);
      if (ac.icao.isNotEmpty) {
        try {
          myAircraftIcao = ac.icao.trim().length > 6 ? int.parse(ac.icao) : int.parse(ac.icao, radix: 16);
        } catch (e) {
          AppLog.logMessage("Invalid ICAO in database: ${ac.icao}");
          // ignore
        }
      }
      if (ac.tail.isNotEmpty) {
        myAircraftCallsign = ac.tail.trim().toUpperCase();
      }
    } catch (e) {
      myAircraftCallsign = "";
      myAircraftIcao = 0;
    }
  }

  Future<void> downloadWeather() async {
    winds.download();
    metar.download();
    taf.download();
    tfr.download();
    airep.download();
    airSigmet.download();
  }

  Future<void> checkDataExpiry() async {
    dataExpired = await DownloadScreenState.isAnyChartExpired();
  }

  Future<void> checkChartsExist() async {
    chartsMissing = !(await DownloadScreenState.doesAnyChartExists());
  }

  Future<void> loadPlate() async {
    String plateAirport = settings.getCurrentPlateAirport();
    plateAirportDestination = await MainDatabaseHelper.db.findAirport(plateAirport);
    String path = await PathUtils.getPlatePath(dataDir, plateAirport, currentPlate);
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
      else if(tokens.length == 6) { //could be made same as for other plates
        matrixPlate = [];
        matrixPlate!.add(double.parse(tokens[0]));
        matrixPlate!.add(double.parse(tokens[1]));
        matrixPlate!.add(double.parse(tokens[2]));
        matrixPlate!.add(double.parse(tokens[3]));
        matrixPlate!.add(double.parse(tokens[4]));
        matrixPlate!.add(double.parse(tokens[5]));
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
  final CacheManager documentsCacheManager = CacheManager(Config("customDocumentsCache", stalePeriod: const Duration(minutes: 1)));
  final CacheManager mapCacheManager = CacheManager(Config("customMapCache", stalePeriod: const Duration(days: 60)));
}
