import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:avaremp/data/business_database_helper.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:avaremp/io/gps.dart';
import 'package:avaremp/place/elevation_cache.dart';
import 'package:avaremp/utils/path_utils.dart';
import 'package:avaremp/plan/waypoint.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/toast.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import 'constants.dart';
import 'data/main_database_helper.dart';
import 'instruments/instrument_list.dart';

// implements a drawing screen with a center reset button.

class PlateScreen extends StatefulWidget {
  const PlateScreen({super.key});
  @override
  State<StatefulWidget> createState() => PlateScreenState();
}

// give plate name like "RNAV RWY 27" find if the procedure name like "R27.AYBEE" applies to this plate and return false if not
bool doesProcedureBelongsToThisPlate(String plateName, String procedureName) {

  if(plateName.isEmpty || procedureName.isEmpty) {
    return false;
  }

  // of the form "IAP-MA-ILS RWY 27"
  RegExp exp = RegExp(r"([A-Z0-9]+)-[A-Z][A-Z]-(.*)");
  Match? match = exp.firstMatch(plateName);
  if(match == null) {
    return false;
  }
  String plate = match.group(2) ?? "";
  String plateType = match.group(1) ?? "";

  List<String> procedureParts = procedureName.split(".");
  if(procedureParts.length < 2) {
    return false;
  }

  // there could be a better way to do it but there is no mapping from d-tpp to cifp. For now less than perfect is fine
  if(plateType == "IAP") {
    if((procedureParts[1] == plate)) {
      return true; // simple straight match
    }
    if(
        (plate.startsWith("LOC") && procedureParts[1].startsWith("L")) ||
        (plate.startsWith("COPTER") && procedureParts[1].startsWith("H")) ||
        (plate.startsWith("VOR AND DME") && procedureParts[1].startsWith("D")) ||
        (plate.startsWith("LOC AND DME BC") && procedureParts[1].startsWith("LBC")) ||
        (plate.startsWith("LOC BC") && procedureParts[1].startsWith("B")) ||
        (plate.startsWith("ILS") && procedureParts[1].startsWith("I")) ||
        (plate.startsWith("RNAV") && procedureParts[1].startsWith("R")) ||
        (plate.startsWith("NDB") && procedureParts[1].startsWith("N")) ||
        (plate.startsWith("VOR") && procedureParts[1].startsWith("S")) ||
        (plate.startsWith("VOR") && procedureParts[1].startsWith("V")) ||
        (plate.startsWith("LDA") && procedureParts[1].startsWith("X")) ||
        false
    ) {
      String runway = procedureParts[1].substring(1);
      // just keep the number of the runway, for example "27" from "27-Y"
      runway = runway.replaceAll(RegExp(r'[^0-9LRC]'), '');
      if(plate.contains(runway)) {
        return true;
      }
    }
    return false;
  }
  else if(plateType == "DP") {
    if(procedureParts[1].length > 4) {
      String proc = procedureParts[1].substring(0, 5);
      if(plate.startsWith(proc)) {
        return true;
      }
    }
    return false;
  }

  return true;

}

// get plates and airports
class PlatesFuture {
  List<String> _plates = [];
  List<String> _airports = [];
  List<String> _procedures = [];
  List<Destination> _businesses = [];
  AirportDestination? _airportDestination;
  String _currentPlateAirport = Storage().settings.getCurrentPlateAirport();

  Future<void> _getAll() async {

    // get location ID only
    _airports = (await UserDatabaseHelper.db.getRecentAirports()).map((e) => e.locationID).toList();

    if(_currentPlateAirport.isEmpty) {
        if(_airports.isNotEmpty) {
          // start condition when no airport is known.
          _currentPlateAirport = _airports[0];
        }
    }
    else {
      // make current airport front
      _airports.insert(0, _currentPlateAirport);
    }
    _airports = _airports.toSet().toList();

    _plates = [];
    if(_currentPlateAirport.isNotEmpty) {
      _plates = await PathUtils.getPlatesAndCSupSorted(Storage().dataDir, _currentPlateAirport);
      _procedures = await MainDatabaseHelper.db.findProcedures(_currentPlateAirport);
      AirportDestination? d = await MainDatabaseHelper.db.findAirport(_currentPlateAirport);
      if(d != null) {
        _businesses = await BusinessDatabaseHelper.db.findBusinesses(d);
      }
    }
    // next one
    _airportDestination = await MainDatabaseHelper.db
        .findAirport(Storage().settings.getCurrentPlateAirport());
  }

  Future<PlatesFuture> getAll() async {
    await _getAll();
    return this;
  }

  AirportDestination? get airportDestination => _airportDestination;
  List<String> get airports => _airports;
  List<String> get plates => _plates;
  List<Destination> get business => _businesses;
  List<String> get procedures => _procedures;
  String get currentPlateAirport => _currentPlateAirport;
}

class PlateScreenState extends State<PlateScreen> {

  final ValueNotifier _notifier = ValueNotifier(0);
  final List<_PlateTerrainCell> _terrainCells = [];
  String _terrainCacheKey = "";
  int _terrainLoadId = 0;
  final ValueNotifier<_ApproachVerticalProfile?> _approachProfile = ValueNotifier<_ApproachVerticalProfile?>(null);
  String _approachProfileKey = "";
  int _approachProfileLoadId = 0;

  @override
  void dispose() {
    _approachProfile.dispose();
    super.dispose();
    Storage().plateChange.removeListener(_notifyPaint);
    Storage().gpsChange.removeListener(_notifyPaint);
  }

  @override
  Widget build(BuildContext context) {
    // this is to listen for landing event, show airport diagram on landing when this screen shows
    return ValueListenableBuilder(valueListenable: Storage().flightStatus.flightStateChange, builder: (BuildContext context, int value, Widget? child) {
      return FutureBuilder(
        future: PlatesFuture().getAll(),
        builder: (context, snapshot) {
          if(snapshot.hasData) {
            return _makeContent(snapshot.data);
          }
          else {
            return _makeContent(null);
          }
        }
      );
    });
  }

  // on change of airport, reload first item of the new airport
  Future _loadPlate() async {
    // load plate in background
    await Storage().loadPlate();
    Storage().lastPlateAirport = Storage().settings.getCurrentPlateAirport();
    _refreshTerrainOverlay();
  }


  void _notifyPaint() {
    _notifier.value++;
  }

  String _buildTerrainCacheKey(ui.Image image, List<double> matrix) {
    return "${Storage().settings.getCurrentPlateAirport()}|"
        "${Storage().currentPlate}|"
        "${image.width}x${image.height}|"
        "${matrix.join(",")}";
  }

  double _terrainCellSize(ui.Image image) {
    const int targetCells = 64;
    final int maxDim = max(image.width, image.height);
    double size = maxDim / targetCells;
    if (size < 16) {
      size = 16;
    }
    return size;
  }

  LatLng? _pixelToLatLng(double pixelX, double pixelY, List<double> matrix) {
    if (matrix.length == 4) {
      double dx = matrix[0];
      double dy = matrix[1];
      double lonTopLeft = matrix[2];
      double latTopLeft = matrix[3];
      if (dx == 0 || dy == 0) {
        return null;
      }
      double lon = pixelX / dx + lonTopLeft;
      double lat = pixelY / dy + latTopLeft;
      if (lon.isNaN || lat.isNaN) {
        return null;
      }
      return LatLng(lat, lon);
    }
    else if (matrix.length == 6) {
      double wftA = matrix[0];
      double wftB = matrix[1];
      double wftC = matrix[2];
      double wftD = matrix[3];
      double wftE = matrix[4];
      double wftF = matrix[5];
      double det = (wftA * wftD) - (wftB * wftC);
      if (det == 0) {
        return null;
      }
      double x = 2 * pixelX - wftE;
      double y = 2 * pixelY - wftF;
      double lon = (x * wftD - y * wftC) / det;
      double lat = (y * wftA - x * wftB) / det;
      if (lon.isNaN || lat.isNaN) {
        return null;
      }
      return LatLng(lat, lon);
    }
    return null;
  }

  Future<List<_PlateTerrainCell>> _buildTerrainCells(ui.Image image, List<double> matrix, int loadId) async {
    final List<_PlateTerrainCell> cells = [];
    final double cellSize = _terrainCellSize(image);
    final double width = image.width.toDouble();
    final double height = image.height.toDouble();
    for (double y = 0; y < height; y += cellSize) {
      final double cellHeight = min(cellSize, height - y);
      final double centerY = y + cellHeight / 2;
      for (double x = 0; x < width; x += cellSize) {
        if (!mounted || loadId != _terrainLoadId) {
          return cells;
        }
        final double cellWidth = min(cellSize, width - x);
        final double centerX = x + cellWidth / 2;
        final LatLng? center = _pixelToLatLng(centerX, centerY, matrix);
        if (center == null) {
          continue;
        }
        final double? elevation = await ElevationCache.getElevation(center);
        if (!mounted || loadId != _terrainLoadId) {
          return cells;
        }
        if (elevation == null) {
          continue;
        }
        cells.add(_PlateTerrainCell(
          rect: Rect.fromLTWH(x, y, cellWidth, cellHeight),
          elevationFt: elevation,
        ));
      }
    }
    return cells;
  }

  Future<void> _refreshTerrainOverlay() async {
    try {
      final ui.Image? image = Storage().imagePlate;
      final List<double>? matrix = Storage().matrixPlate;
      if (image == null || matrix == null || matrix.isEmpty) {
        if (_terrainCells.isNotEmpty) {
          _terrainCells.clear();
          _terrainCacheKey = "";
          _notifyPaint();
        }
        return;
      }
      final String cacheKey = _buildTerrainCacheKey(image, matrix);
      if (_terrainCacheKey == cacheKey && _terrainCells.isNotEmpty) {
        return;
      }
      _terrainCacheKey = cacheKey;
      final int loadId = ++_terrainLoadId;
      final List<_PlateTerrainCell> cells = await _buildTerrainCells(image, matrix, loadId);
      if (!mounted || loadId != _terrainLoadId) {
        return;
      }
      _terrainCells
        ..clear()
        ..addAll(cells);
      _notifyPaint();
    }
    catch (_) {
      // ignore terrain overlay errors to avoid blocking plate rendering
    }
  }

  Future<void> _refreshApproachProfile(List<String> procedures, AirportDestination? airport) async {
    if(!Storage().currentPlate.startsWith("IAP")) {
      if(_approachProfile.value != null) {
        _approachProfile.value = null;
        _notifyPaint();
      }
      _approachProfileKey = "";
      return;
    }

    final String? procedureName = _selectApproachProcedure(procedures);
    final String key = "${Storage().settings.getCurrentPlateAirport()}|${Storage().currentPlate}|${procedureName ?? ""}";
    if(_approachProfileKey == key) {
      return;
    }
    _approachProfileKey = key;
    final int loadId = ++_approachProfileLoadId;
    _approachProfile.value = null;
    _notifyPaint();

    if(procedureName == null || airport == null) {
      return;
    }

    final _ApproachVerticalProfile? profile = await _buildApproachProfile(procedureName, airport);
    if(!mounted || loadId != _approachProfileLoadId) {
      return;
    }
    _approachProfile.value = profile;
    _notifyPaint();
  }

  String? _selectApproachProcedure(List<String> procedures) {
    if(procedures.isEmpty) {
      return null;
    }
    final String plate = Storage().currentPlate;
    for(final Destination destination in Storage().route.getAllDestinations().reversed) {
      if(!Destination.isProcedure(destination.type)) {
        continue;
      }
      final String proc = destination.locationID;
      if(doesProcedureBelongsToThisPlate(plate, proc)) {
        return proc;
      }
    }
    return procedures.first;
  }

  Future<_ApproachVerticalProfile?> _buildApproachProfile(String procedureName, AirportDestination airport) async {
    final List<Map<String, dynamic>> records = await MainDatabaseHelper.db.findProcedureLines(procedureName);
    if(records.isEmpty) {
      return null;
    }

    int fafIndex = -1;
    for(int i = 0; i < records.length; i++) {
      if(_isFaf(records[i])) {
        fafIndex = i;
        break;
      }
    }
    if(fafIndex < 0) {
      fafIndex = records.length - 1;
    }

    int iafIndex = -1;
    final int iafStart = fafIndex < records.length ? fafIndex : records.length - 1;
    for(int i = iafStart; i >= 0; i--) {
      if(_isIaf(records[i])) {
        iafIndex = i;
        break;
      }
    }

    int thresholdIndex = -1;
    final int thresholdStart = fafIndex < 0 ? 0 : fafIndex;
    for(int i = thresholdStart; i < records.length; i++) {
      if(_isRunwayFix(records[i])) {
        thresholdIndex = i;
        break;
      }
    }
    if(thresholdIndex < 0) {
      thresholdIndex = records.length - 1;
    }

    final int startIndex = iafIndex >= 0 ? iafIndex : 0;
    final int endIndex = thresholdIndex >= 0 ? thresholdIndex : records.length - 1;

    final Map<String, dynamic> thresholdRecord = records[endIndex];
    final String thresholdFixId = _mapValue(thresholdRecord, const ["fix_identifier", "fixIdentifier"]);
    final _RunwayThreshold? threshold = _resolveThreshold(airport, thresholdFixId, procedureName);
    final LatLng thresholdCoord = threshold?.coordinate ?? airport.coordinate;
    final double thresholdAltitude = threshold?.elevationFt ?? airport.elevation ?? 0.0;

    final List<_ApproachProfileCandidate> candidates = [];
    String lastFixId = "";
    for(int i = startIndex; i <= endIndex; i++) {
      final Map<String, dynamic> record = records[i];
      final String fixId = _mapValue(record, const ["fix_identifier", "fixIdentifier"]);
      if(fixId.isEmpty) {
        continue;
      }

      final bool isIaf = _isIaf(record);
      final bool isFaf = _isFaf(record);
      final bool isRunway = i == endIndex || _isRunwayFix(record);

      LatLng? coord = await _resolveFixCoordinate(fixId, airport);
      if(coord == null) {
        if(!isRunway) {
          continue;
        }
        coord = thresholdCoord;
      }

      if(fixId == lastFixId && !isRunway) {
        continue;
      }

      final double? slope = _parseVerticalAngle(_mapValue(record, const ["vertical_angle", "verticalAngle"]));
      double? altitude = _parseAltitudeFromRecord(record);
      if(isRunway) {
        altitude = thresholdAltitude;
      }

      final String labelRole = isRunway ? "RW" : (isFaf ? "FAF" : (isIaf ? "IAF" : ""));
      final String label = labelRole.isEmpty ? fixId.trim() : _buildWaypointLabel(labelRole, fixId);
      candidates.add(_ApproachProfileCandidate(
        coordinate: coord,
        label: label,
        slopeDeg: slope,
        altitudeFt: altitude,
        isRunway: isRunway,
      ));
      lastFixId = fixId;
    }

    if(candidates.isEmpty) {
      return null;
    }

    if(!candidates.last.isRunway) {
      candidates.add(_ApproachProfileCandidate(
        coordinate: thresholdCoord,
        label: _buildWaypointLabel("RW", thresholdFixId),
        slopeDeg: _parseVerticalAngle(_mapValue(thresholdRecord, const ["vertical_angle", "verticalAngle"])),
        altitudeFt: thresholdAltitude,
        isRunway: true,
      ));
    }

    final List<double> distances = [0];
    double totalDistance = 0;
    for(int i = 1; i < candidates.length; i++) {
      totalDistance += _distanceNmBetween(candidates[i - 1].coordinate, candidates[i].coordinate);
      distances.add(totalDistance);
    }

    if(totalDistance <= 0) {
      return null;
    }

    double? defaultSlope;
    for(final _ApproachProfileCandidate candidate in candidates) {
      if(candidate.slopeDeg != null) {
        defaultSlope = candidate.slopeDeg;
        break;
      }
    }
    defaultSlope ??= 3.0;

    final List<_ApproachProfilePoint> points = [];
    for(int i = 0; i < candidates.length; i++) {
      final _ApproachProfileCandidate candidate = candidates[i];
      double? altitude = candidate.altitudeFt;
      if(altitude == null) {
        final double slope = candidate.slopeDeg ?? defaultSlope;
        final double distanceToThreshold = totalDistance - distances[i];
        altitude = thresholdAltitude + tan(_toRadians(slope)) * distanceToThreshold * _feetPerNm;
      }
      if(altitude < thresholdAltitude) {
        altitude = thresholdAltitude;
      }
      points.add(_ApproachProfilePoint(
        waypointLabel: candidate.label,
        distanceNm: distances[i],
        altitudeFt: altitude,
        slopeDeg: candidate.slopeDeg,
      ));
    }

    if(points.length < 2) {
      return null;
    }

    return _ApproachVerticalProfile(points: points, thresholdCoordinate: thresholdCoord);
  }

  static double _toRadians(double degrees) {
    return degrees * pi / 180.0;
  }

  static const double _feetPerNm = 6076.12;
  static const double _metersPerNm = 1851.9993;

  double _distanceNmBetween(LatLng start, LatLng end) {
    final double distanceInUnits = GeoCalculations().calculateDistance(start, end);
    final double meters = distanceInUnits * Storage().units.toM;
    return meters / _metersPerNm;
  }

  String _mapValue(Map<String, dynamic> map, List<String> keys) {
    for(final String key in keys) {
      final dynamic value = map[key];
      if(value == null) {
        continue;
      }
      final String text = value.toString().trim();
      if(text.isNotEmpty) {
        return text;
      }
    }
    return "";
  }

  String _buildWaypointLabel(String role, String fixId) {
    final String trimmed = fixId.trim();
    if(trimmed.isEmpty) {
      return role;
    }
    return "$role $trimmed";
  }

  bool _isIaf(Map<String, dynamic> map) {
    final String wdc = _mapValue(map, const ["waypoint_description_code", "waypointDescriptionCode"]).toUpperCase();
    final String path = _mapValue(map, const ["path_and_termination", "pathAndTermination"]).toUpperCase();
    return wdc.contains("IAF") || wdc.startsWith("IA") || wdc == "I" || path == "IF";
  }

  bool _isFaf(Map<String, dynamic> map) {
    final String wdc = _mapValue(map, const ["waypoint_description_code", "waypointDescriptionCode"]).toUpperCase();
    final String path = _mapValue(map, const ["path_and_termination", "pathAndTermination"]).toUpperCase();
    return wdc.contains("FAF") || wdc.startsWith("FA") || wdc == "F" || path == "FA";
  }

  bool _isRunwayFix(Map<String, dynamic> map) {
    final String fixId = _mapValue(map, const ["fix_identifier", "fixIdentifier"]).toUpperCase();
    final String wdc = _mapValue(map, const ["waypoint_description_code", "waypointDescriptionCode"]).toUpperCase();
    final String path = _mapValue(map, const ["path_and_termination", "pathAndTermination"]).toUpperCase();
    return fixId.startsWith("RW") || wdc.contains("RWY") || path == "RW";
  }

  double? _parseVerticalAngle(String raw) {
    final String cleaned = raw.trim();
    if(cleaned.isEmpty) {
      return null;
    }
    final String numeric = cleaned.replaceAll(RegExp(r"[^0-9\.\-]"), "");
    if(numeric.isEmpty) {
      return null;
    }
    double? value = double.tryParse(numeric);
    if(value == null || value == 0) {
      return null;
    }
    value = value.abs();
    if(!numeric.contains(".")) {
      while(value > 10) {
        value = value / 10.0;
      }
    }
    if(value <= 0 || value > 10) {
      return null;
    }
    return value;
  }

  double? _parseAltitudeFromRecord(Map<String, dynamic> record) {
    final String altitude1 = _mapValue(record, const ["altitude1", "altitude_1"]);
    final String altitude2 = _mapValue(record, const ["altitude2", "altitude_2"]);
    final double? alt1 = _parseAltitudeFt(altitude1);
    final double? alt2 = _parseAltitudeFt(altitude2);
    if(alt1 != null && alt2 != null) {
      return max(alt1, alt2);
    }
    return alt1 ?? alt2;
  }

  double? _parseAltitudeFt(String raw) {
    final String cleaned = raw.trim();
    if(cleaned.isEmpty) {
      return null;
    }
    final String numeric = cleaned.replaceAll(RegExp(r"[^0-9]"), "");
    if(numeric.isEmpty) {
      return null;
    }
    int? value = int.tryParse(numeric);
    if(value == null || value == 0) {
      return null;
    }
    if(numeric.length <= 3) {
      value = value * 100;
    }
    else if(numeric.length == 4 && value < 2000) {
      value = value * 10;
    }
    return value.toDouble();
  }

  Future<LatLng?> _resolveFixCoordinate(String fixId, AirportDestination airport) async {
    final String trimmed = fixId.trim();
    if(trimmed.isEmpty) {
      return null;
    }

    final String upper = trimmed.toUpperCase();
    if(upper.startsWith("RW")) {
      final _RunwayThreshold? runway = _resolveThreshold(airport, trimmed, "");
      if(runway != null) {
        return runway.coordinate;
      }
    }

    FixDestination? fix = await MainDatabaseHelper.db.findFix(trimmed);
    if(fix != null) {
      return fix.coordinate;
    }
    NavDestination? nav = await MainDatabaseHelper.db.findNav(trimmed);
    if(nav != null) {
      return nav.coordinate;
    }
    return null;
  }

  _RunwayThreshold? _resolveThreshold(AirportDestination airport, String fixId, String procedureName) {
    String? runwayIdent = _runwayIdentFromText(fixId);
    runwayIdent ??= _runwayIdentFromText(procedureName);
    runwayIdent ??= _runwayIdentFromText(Storage().currentPlate);
    if(runwayIdent == null) {
      return null;
    }
    return _findRunwayThreshold(airport, runwayIdent);
  }

  String? _runwayIdentFromText(String text) {
    final RegExp exp = RegExp(r"RWY?\s*([0-9]{1,2}[LRC]?)", caseSensitive: false);
    final RegExpMatch? match = exp.firstMatch(text);
    if(match == null) {
      final RegExp fallback = RegExp(r"([0-9]{1,2}[LRC]?)[A-Z]?$", caseSensitive: false);
      final RegExpMatch? altMatch = fallback.firstMatch(text);
      return altMatch?.group(1);
    }
    return match.group(1);
  }

  _RunwayThreshold? _findRunwayThreshold(AirportDestination airport, String runwayIdent) {
    for(final Map<String, dynamic> runway in airport.runways) {
      final String leIdent = runway['LEIdent']?.toString().trim() ?? "";
      final String heIdent = runway['HEIdent']?.toString().trim() ?? "";
      if(leIdent == runwayIdent) {
        final LatLng? ll = _runwayCoordinate(runway, "LE");
        if(ll == null) {
          continue;
        }
        return _RunwayThreshold(
          coordinate: ll,
          elevationFt: _runwayElevation(runway, "LE"),
        );
      }
      if(heIdent == runwayIdent) {
        final LatLng? ll = _runwayCoordinate(runway, "HE");
        if(ll == null) {
          continue;
        }
        return _RunwayThreshold(
          coordinate: ll,
          elevationFt: _runwayElevation(runway, "HE"),
        );
      }
    }
    return null;
  }

  LatLng? _runwayCoordinate(Map<String, dynamic> runway, String side) {
    try {
      final double lat = double.parse(runway['${side}Latitude'].toString());
      final double lon = double.parse(runway['${side}Longitude'].toString());
      return LatLng(lat, lon);
    }
    catch (_) {
      return null;
    }
  }

  double? _runwayElevation(Map<String, dynamic> runway, String side) {
    try {
      final String value = runway['${side}Elevation']?.toString() ?? "";
      if(value.isEmpty) {
        return null;
      }
      return double.tryParse(value);
    }
    catch (_) {
      return null;
    }
  }

  Widget _makeContent(PlatesFuture? future) {

    double height = 0;

    if(future == null || future.airports.isEmpty) {
      _refreshApproachProfile([], null);
      return makePlateView([], [], [], [], height, _notifier);
    }

    List<String> plates = future.plates;
    List<Destination> business = future.business;
    List<String> airports = future.airports;
    List<String> procedures = future.procedures;
    Storage().settings.setCurrentPlateAirport(future.currentPlateAirport);

    if(plates.isNotEmpty && (Storage().lastPlateAirport !=  Storage().settings.getCurrentPlateAirport())) {
      Storage().currentPlate = plates[0]; // new airport, change to plate 0
    }

    _loadPlate();

    // plate load notification, repaint
    Storage().plateChange.addListener(_notifyPaint);
    Storage().gpsChange.addListener(_notifyPaint);

    List<String> procedureNames = [];
    for(String prec in procedures) {
      if(doesProcedureBelongsToThisPlate(Storage().currentPlate, prec)) {
        procedureNames.add(prec);
      }
    }

    _refreshApproachProfile(procedureNames, future.airportDestination);

    return makePlateView(airports, plates, procedureNames, business, height, _notifier);
  }

  Widget makePlateView(List<String> airports, List<String> plates, List<String> procedures, List<Destination> business, double height, ValueNotifier notifier) {

    bool notAd = !PathUtils.isAirportDiagram(Storage().currentPlate);
    if(notAd) {
      Storage().business = null;
    }

    final List<String> layers = Storage().settings.getLayers();
    final List<double> layersOpacity = Storage().settings.getLayersOpacity();
    final double opacity = layersOpacity[layers.indexOf("Elevation")];

    return Scaffold(body: Stack(children: [
      // always return this so to reduce flicker
      InteractiveViewer(
          minScale: 1,
          maxScale: 8,
          child:
          SizedBox(
            height: Constants.screenHeight(context),
            width: Constants.screenWidth(context),
            child: CustomPaint(painter: _PlatePainter(notifier, _terrainCells, opacity, _approachProfile)),
          )
      ),

      Positioned(
        child: Align(
          alignment: Alignment.topLeft,
          child: (Storage().settings.isInstrumentsVisiblePlate()) ?
            SizedBox(height: Constants.screenHeightForInstruments(context), child: const InstrumentList()) : Container(),
        )
      ),

      // allow user to toggle instruments
      Positioned(
      child: Align(
        alignment: Alignment.topRight,
        child: CircleAvatar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7),
        child: IconButton(onPressed: () {
          setState(() {
            Storage().settings.setInstrumentsVisiblePlate(!Storage().settings.isInstrumentsVisiblePlate());
          });
        }, icon: Icon(Storage().settings.isInstrumentsVisiblePlate() ? MdiIcons.arrowCollapseRight : MdiIcons.arrowCollapseLeft),),),
      )),
      plates.isEmpty ? Container() : // nothing to show here if plates is empty
      Positioned(
          child: Align(
              alignment: Alignment.bottomLeft,
              child: plates[0].isEmpty ? Container() : Container(
                  padding: EdgeInsets.fromLTRB(15, 5, 5, Constants.bottomPaddingSize(context) + 5),
                  child:DropdownButtonHideUnderline(
                      child:DropdownButton2<String>(
                        isDense: true,// plate selection
                        customButton: CircleAvatar(backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7),child: const Icon(Icons.more_horiz),
                        ),
                        buttonStyleData: ButtonStyleData(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.transparent),
                        ),
                        dropdownStyleData: DropdownStyleData(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                          width: Constants.screenWidth(context) * 0.75,
                        ),
                        isExpanded: false,
                        value: plates.contains(Storage().currentPlate) ? Storage().currentPlate : plates[0],
                        items: plates.map((String item) {
                          return DropdownMenuItem<String>(
                            value: item,
                            child: Row(children:[
                              Expanded(child:
                                Container(
                                  decoration: BoxDecoration(color: _getPlateColor(item),
                                    borderRadius: BorderRadius.circular(5),),
                                    child: Padding(padding: const EdgeInsets.all(5), child:
                                      AutoSizeText(item, minFontSize: 2, maxLines: 1,)),
                                )
                              )
                            ])
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            Storage().currentPlate = value ?? plates[0];
                          });
                        },
                      )
                  )
              )
          )
      ),

      (business.isEmpty || notAd) ? Container() : // nothing to show here if plates is empty
      Positioned(
          child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                  padding: EdgeInsets.fromLTRB(15, 5, 5, Constants.bottomPaddingSize(context) + 5),
                  child:DropdownButtonHideUnderline(
                      child:DropdownButton2<String>(
                        isDense: true,// plate selection
                        customButton: CircleAvatar(backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7),child: const Icon(Icons.more_horiz),
                        ),
                        buttonStyleData: ButtonStyleData(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.transparent),
                        ),
                        dropdownStyleData: DropdownStyleData(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                          width: Constants.screenWidth(context) * 0.75,
                        ),
                        isExpanded: false,
                        value: business.contains(Storage().business) ? Storage().business!.facilityName : business[0].facilityName,
                        items: business.map((Destination item) {
                          return DropdownMenuItem<String>(
                              value: item.facilityName,
                              child: Row(children:[
                                Expanded(child:
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(5),),
                                  child: Padding(padding: const EdgeInsets.all(5), child:
                                  AutoSizeText(item.facilityName, minFontSize: 2, maxLines: 1,)),
                                )
                                )
                              ])
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            Storage().business = value == null ? business[0] : business.firstWhere((element) => element.facilityName == value, orElse: () => business[0]);
                          });
                        },
                      )
                  )
              )
          )
      ),

      airports.isEmpty ? Container() : // nothing to show here is airports is empty
      Positioned(
          child: Align(
              alignment: Alignment.bottomRight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  procedures.isEmpty || procedures[0].isEmpty ? Container() : // nothing to show here if plates is empty
                  Container(
                    padding: EdgeInsets.fromLTRB(15, 5, 5, Constants.bottomPaddingSize(context) + 5),
                    child:DropdownButtonHideUnderline(
                        child:DropdownButton2<String>(
                          isDense: true,// plate selection
                            customButton: CircleAvatar(radius: 14, backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7),child: const Icon(Icons.route)),
                            buttonStyleData: ButtonStyleData(
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.transparent),
                          ),
                          dropdownStyleData: DropdownStyleData(
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                            width: Constants.screenWidth(context) * 0.75,
                          ),
                          isExpanded: false,
                          value: procedures[0],
                          items: procedures.map((String item) {
                            return DropdownMenuItem<String>(
                                value: item,
                                child: Row(children:[
                                  Expanded(child:
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(5),),
                                    child: Padding(padding: const EdgeInsets.all(5), child:
                                    AutoSizeText(item, minFontSize: 2, maxLines: 1,)),
                                  ))
                                ])
                            );
                          }).toList(),
                          onChanged: (value) {
                            if(value == null) {
                              return;
                            }
                            MainDatabaseHelper.db.findProcedure(value).then((ProcedureDestination? procedure) {
                              if(procedure != null) {
                                Storage().route.addWaypoint(Waypoint(procedure));
                                setState(() {
                                  Toast.showToast(context, "Added ${procedure.facilityName} to Plan", null, 3);
                                  // show toast message that the procedure is added to the plan
                                });
                              }
                            });
                          },
                        )
                    )
                  ),

                  airports[0].isEmpty ? Container() :
                  Container(
                    padding: EdgeInsets.fromLTRB(5, 5, 15, Constants.bottomPaddingSize(context) + 5),
                    child:DropdownButtonHideUnderline(
                      child:DropdownButton2<String>( // airport selection
                        buttonStyleData: ButtonStyleData(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7)),
                        ),
                        dropdownStyleData: DropdownStyleData(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                        ),
                        isExpanded: false,
                        value: airports.contains(Storage().settings.getCurrentPlateAirport()) ? Storage().settings.getCurrentPlateAirport() : airports[0],
                        items: airports.map((String item) {
                          return DropdownMenuItem<String>(
                              value: item,
                              child:Text(item, style: TextStyle(fontSize: Constants.dropDownButtonFontSize))
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            Storage().settings.setCurrentPlateAirport(value ?? airports[0]);
                          });
                        },
                      )
                  )
              )
            ]
          )
      ),
    )
    ])
    );
  }
  
  Color _getPlateColor(String name) {
    if(name.startsWith("APD")) {
      return Colors.green;
    }
    else if(name.startsWith("CSUP")) {
      return Colors.blue;
    }
    else if(name.startsWith("DP")) {
      return Colors.pinkAccent;
    }
    else if(name.startsWith("IAP")) {
      return Colors.purpleAccent;
    }
    else if(name.startsWith("STAR")) {
      return Colors.cyan;
    }
    else if(name.startsWith("MIN")) {
      return Colors.brown;
    }
    else if(name.startsWith("HOT")) {
      return Colors.red;
    }
    else if(name.startsWith("LAH")) {
      return Colors.red;
    }

    return Colors.grey;
  }
}

class _PlatePainter extends CustomPainter {

  List<double>? _matrix;
  Destination? _business;
  ui.Image? _image;
  ui.Image? _imagePlane;
  double? _variation;
  double opacity;
  final List<_PlateTerrainCell> _terrainCells;
  final ValueNotifier<_ApproachVerticalProfile?> _approachProfile;

  // Define a paint object
  final _paint = Paint()
    ..isAntiAlias = true
    ..filterQuality = FilterQuality.high;
  // Define a paint object for circle
  final _paintCenter = Paint()
    ..style = PaintingStyle.fill
    ..color = Constants.plateMarkColor;

  final _paintLine = Paint()
    ..strokeWidth = 6
    ..color = Constants.planeColor;

  final _paintCompass = Paint()
    ..strokeWidth = 3
    ..color = Colors.red;

  final _paintBusiness = Paint()
    ..strokeWidth = 3
    ..color = Colors.blueAccent.withAlpha(200)
    ..style = PaintingStyle.fill;

  final _paintTerrain = Paint()
    ..style = PaintingStyle.fill;

  final _paintProfileFill = Paint()
    ..style = PaintingStyle.fill;

  final _paintProfileLine = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  final _paintProfileBorder = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;

  final _paintProfileMarker = Paint()
    ..style = PaintingStyle.fill;

  final _paintProfileCurrent = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  final _paintProfileAircraft = Paint()
    ..style = PaintingStyle.fill;

  static const double _metersPerNm = 1851.9993;

  _PlatePainter(ValueNotifier repaint, this._terrainCells, this.opacity, this._approachProfile): super(repaint: repaint);

  (Offset, double) _calculateOffset(LatLng ll) {
    double lon = ll.longitude;
    double lat = ll.latitude;
    Offset offset = const Offset(0, 0);
    double angle = 0;
    if(_matrix!.length == 4) {
      double dx = _matrix![0];
      double dy = _matrix![1];
      double lonTopLeft = _matrix![2];
      double latTopLeft = _matrix![3];
      double pixX = (lon - lonTopLeft) * dx;
      double pixY = (lat - latTopLeft) * dy;
      offset = Offset(pixX, pixY);
      angle = 0;
    }
    else if(_matrix!.length == 6) {
      double wftA = _matrix![0];
      double wftB = _matrix![1];
      double wftC = _matrix![2];
      double wftD = _matrix![3];
      double wftE = _matrix![4];
      double wftF = _matrix![5];

      double pixX = (wftA * lon + wftC * lat + wftE) / 2;
      double pixY = (wftB * lon + wftD * lat + wftF) / 2;
      offset = Offset(pixX, pixY);

      double pixXn = (wftA * lon + wftC * (lat + 0.1) + wftE) / 2;
      double pixYn = (wftB * lon + wftD * (lat + 0.1) + wftF) / 2;
      double diffX = pixXn - pixX;
      double diffY = pixYn - pixY;
      angle = GeoCalculations.toDegrees(atan2(diffX, -diffY));
    }
    return (offset, angle);
  }

  @override
  void paint(Canvas canvas, Size size) {

    _image = Storage().imagePlate;
    _business = Storage().business;
    _variation = Storage().area.variation;
    _imagePlane = Storage().imagePlane;
    _matrix = Storage().matrixPlate;
    Destination? center = Storage().plateAirportDestination;

    if(_image != null && center != null) {

      // make in center
      double h = size.height;
      double ih = _image!.height.toDouble();
      double w = size.width;
      double iw = _image!.width.toDouble();
      double fac = h / ih;
      double fac2 = w / iw;
      if (fac > fac2) {
        fac = fac2;
      }

      canvas.save();
      canvas.translate(0, 0);
      canvas.scale(fac);
      canvas.drawImage(_image!, const Offset(0, 0), _paint);

      if(_terrainCells.isNotEmpty) {
        _drawTerrainOverlay(canvas);
      }

      if(null != _matrix) {

        double heading = Storage().position.heading;
        Offset offsetCircle = const Offset(0, 0);
        Offset offsetPlane = const Offset(0, 0);
        double angle = 0;

        (offsetCircle, _) = _calculateOffset(center.coordinate);
        (offsetPlane, angle) = _calculateOffset(Gps.toLatLng(Storage().position));

        // draw circle at center of airport
        canvas.drawCircle(offsetCircle, 16  , _paintCenter);

        if(_business != null) {
          // draw selected business
          Offset offsetBiz = const Offset(0, 0);
          (offsetBiz, _) = _calculateOffset(_business!.coordinate);
          canvas.drawCircle(offsetBiz, 10, _paintBusiness);
          offsetBiz = Offset(offsetBiz.dx + 12, offsetBiz.dy - 12);
          TextSpan span = TextSpan(text: _business!.facilityName.substring(0, min(_business!.facilityName.length, 24)),
              style: TextStyle(color: Colors.red, backgroundColor: Colors.white, fontWeight: FontWeight.bold, fontSize: 12));
          TextPainter tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
          tp.layout();
          tp.paint(canvas, offsetBiz);
        }

        //draw airplane
        canvas.save();
        canvas.translate(offsetPlane.dx, offsetPlane.dy);
        canvas.rotate((heading + angle) * pi / 180);
        canvas.drawImage(_imagePlane!, Offset(-_imagePlane!.width / 2, -_imagePlane!.height / 2), _paint);
        // draw all based on screen width, height
        _paintLine.shader = ui.Gradient.linear(Offset(0, 2 * (size.height + size.width) / 64), Offset(0, -(size.height + size.width) / 2), [Colors.red, Colors.white]);
        canvas.drawLine(Offset(0, (size.height + size.width) / 64 - _imagePlane!.height), Offset(0, -(size.height + size.width) / 2), _paintLine);
        double a = (_variation! - 90 - heading) * pi / 180;
        double x2 = 64 * cos(a);
        double y2 = 64 * sin(a);
        double x3 = 54 * cos(a - 0.1);
        double y3 = 54 * sin(a - 0.1);
        canvas.drawLine(const Offset(0, 0), Offset(x2, y2), _paintCompass);
        canvas.drawLine(Offset(x2, y2), Offset(x3, y3), _paintCompass);
        _paintLine.shader = null;
        canvas.restore();
      }
      _drawApproachProfile(canvas);
      canvas.restore();
    }
  }

  void _drawTerrainOverlay(Canvas canvas) {
    final double altitudeFt = GeoCalculations.convertAltitude(Storage().position.altitude);
    final double warningFloor = altitudeFt - 1000;
    final double cautionFloor = altitudeFt - 500;
    final Color yellowColor = Colors.yellow.withValues(alpha: opacity);
    final Color redColor = Colors.red.withValues(alpha: opacity);
    for(final _PlateTerrainCell cell in _terrainCells) {
      if(cell.elevationFt < warningFloor) {
        continue;
      }
      _paintTerrain.color = cell.elevationFt < cautionFloor ? yellowColor : redColor;
      canvas.drawRect(cell.rect, _paintTerrain);
    }
  }

  void _drawApproachProfile(Canvas canvas) {
    final _ApproachVerticalProfile? profile = _approachProfile.value;
    if(profile == null || profile.points.length < 2 || _image == null) {
      return;
    }

    final double iw = _image!.width.toDouble();
    final double ih = _image!.height.toDouble();
    final double margin = iw * 0.04;
    final double chartWidth = iw * 0.36;
    final double chartHeight = ih * 0.18;
    final Rect rect = Rect.fromLTWH(margin, ih - chartHeight - margin, chartWidth, chartHeight);
    if(rect.width <= 0 || rect.height <= 0) {
      return;
    }

    double minAlt = profile.points.map((p) => p.altitudeFt).reduce(min);
    double maxAlt = profile.points.map((p) => p.altitudeFt).reduce(max);
    final double currentAlt = GeoCalculations.convertAltitude(Storage().position.altitude);
    minAlt = min(minAlt, currentAlt);
    maxAlt = max(maxAlt, currentAlt);
    final double padding = max(200, (maxAlt - minAlt) * 0.15);
    minAlt -= padding;
    maxAlt += padding;
    if(maxAlt <= minAlt) {
      return;
    }

    final double totalDistance = profile.points.last.distanceNm;
    if(totalDistance <= 0) {
      return;
    }

    double yForAlt(double alt) {
      return rect.bottom - (alt - minAlt) / (maxAlt - minAlt) * rect.height;
    }

    double xForDistance(double dist) {
      return rect.left + (dist / totalDistance) * rect.width;
    }

    _paintProfileFill.color = Colors.black.withValues(alpha: 0.55);
    canvas.drawRect(rect, _paintProfileFill);
    _paintProfileBorder.color = Colors.white.withValues(alpha: 0.6);
    canvas.drawRect(rect, _paintProfileBorder);

    _paintProfileLine.color = Colors.cyanAccent.withValues(alpha: 0.9);
    _paintProfileMarker.color = Colors.white;
    _paintProfileCurrent.color = Colors.orangeAccent.withValues(alpha: 0.9);
    _paintProfileAircraft.color = Colors.orange.withValues(alpha: 0.95);

    final List<Offset> points = profile.points.map((p) => Offset(xForDistance(p.distanceNm), yForAlt(p.altitudeFt))).toList();
    for(int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], _paintProfileLine);
    }
    for(final Offset point in points) {
      canvas.drawCircle(point, 3, _paintProfileMarker);
    }

    final double currentY = yForAlt(currentAlt);
    if(currentY >= rect.top && currentY <= rect.bottom) {
      canvas.drawLine(Offset(rect.left, currentY), Offset(rect.right, currentY), _paintProfileCurrent);
    }

    double distanceNmBetween(LatLng start, LatLng end) {
      final double distanceInUnits = GeoCalculations().calculateDistance(start, end);
      final double meters = distanceInUnits * Storage().units.toM;
      return meters / _metersPerNm;
    }

    final LatLng currentPos = Gps.toLatLng(Storage().position);
    final double distanceToThreshold = distanceNmBetween(currentPos, profile.thresholdCoordinate);
    double distanceAlong = totalDistance - distanceToThreshold;
    distanceAlong = distanceAlong.clamp(0.0, totalDistance);
    final double aircraftX = xForDistance(distanceAlong);
    if(currentY >= rect.top && currentY <= rect.bottom) {
      canvas.drawCircle(Offset(aircraftX, currentY), 4, _paintProfileAircraft);
    }

    double labelFontSize = min(12, max(8, rect.height * 0.14));

    void drawText(String text, Offset anchor, {TextAlign align = TextAlign.left}) {
      TextSpan span = TextSpan(
          text: text,
          style: TextStyle(
            fontSize: labelFontSize,
            color: Colors.white,
            backgroundColor: Colors.black.withValues(alpha: 0.6),
          ));
      TextPainter tp = TextPainter(text: span, textAlign: align, textDirection: TextDirection.ltr);
      tp.layout();
      double dx = anchor.dx;
      if(align == TextAlign.center) {
        dx -= tp.width / 2;
      }
      else if(align == TextAlign.right) {
        dx -= tp.width;
      }
      tp.paint(canvas, Offset(dx, anchor.dy));
    }

    drawText(maxAlt.round().toString(), Offset(rect.left + 4, rect.top + 2));
    drawText(minAlt.round().toString(), Offset(rect.left + 4, rect.bottom - labelFontSize - 2));

    for(int i = 0; i < profile.points.length; i++) {
      final _ApproachProfilePoint point = profile.points[i];
      final String slopeText = point.slopeDeg == null ? "" : " ${point.slopeDeg!.toStringAsFixed(1)}deg";
      drawText("${point.waypointLabel}$slopeText", Offset(points[i].dx, rect.bottom - labelFontSize - 2), align: TextAlign.center);
      final double altLabelY = max(rect.top + 2, points[i].dy - labelFontSize - 2);
      drawText("${point.altitudeFt.round()}ft", Offset(points[i].dx, altLabelY), align: TextAlign.center);
    }
  }

  @override
  bool shouldRepaint(_PlatePainter oldDelegate) => true;
}

class _PlateTerrainCell {
  final Rect rect;
  final double elevationFt;
  const _PlateTerrainCell({required this.rect, required this.elevationFt});
}

class _ApproachProfileCandidate {
  final LatLng coordinate;
  final String label;
  final double? slopeDeg;
  final double? altitudeFt;
  final bool isRunway;

  const _ApproachProfileCandidate({
    required this.coordinate,
    required this.label,
    required this.slopeDeg,
    required this.altitudeFt,
    required this.isRunway,
  });
}

class _ApproachProfilePoint {
  final String waypointLabel;
  final double distanceNm;
  final double altitudeFt;
  final double? slopeDeg;

  const _ApproachProfilePoint({
    required this.waypointLabel,
    required this.distanceNm,
    required this.altitudeFt,
    required this.slopeDeg,
  });
}

class _ApproachVerticalProfile {
  final List<_ApproachProfilePoint> points;
  final LatLng thresholdCoordinate;

  const _ApproachVerticalProfile({required this.points, required this.thresholdCoordinate});
}

class _RunwayThreshold {
  final LatLng coordinate;
  final double? elevationFt;

  const _RunwayThreshold({
    required this.coordinate,
    required this.elevationFt,
  });
}

