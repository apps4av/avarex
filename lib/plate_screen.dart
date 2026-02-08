import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:avaremp/data/business_database_helper.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/destination/airport.dart';
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

const double _metersToNm = 0.000539957;

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
  final Distance _profileDistance = const Distance(calculator: Haversine());
  final List<_VerticalProfilePoint> _verticalProfilePoints = [];
  String? _selectedProcedure;
  String _verticalProfileKey = "";
  int _verticalProfileLoadId = 0;

  @override
  void dispose() {
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

  void _updateSelectedProcedure(List<String> procedureNames) {
    if (procedureNames.isEmpty) {
      _selectedProcedure = null;
      _verticalProfilePoints.clear();
      _verticalProfileKey = "";
      return;
    }
    if (_selectedProcedure == null || !procedureNames.contains(_selectedProcedure)) {
      _selectedProcedure = procedureNames[0];
    }
    final String cacheKey = "${Storage().settings.getCurrentPlateAirport()}|"
        "${Storage().currentPlate}|$_selectedProcedure";
    if (cacheKey != _verticalProfileKey) {
      _verticalProfileKey = cacheKey;
      _verticalProfilePoints.clear();
      if (_selectedProcedure != null) {
        _loadVerticalProfile(_selectedProcedure!);
      }
    }
  }

  Future<void> _loadVerticalProfile(String procedureName) async {
    final int loadId = ++_verticalProfileLoadId;
    final List<ProcedureProfilePoint> points =
        await MainDatabaseHelper.db.findProcedureProfile(procedureName);
    if (!mounted || loadId != _verticalProfileLoadId) {
      return;
    }
    final List<_VerticalProfilePoint> profilePoints = points
        .map((point) => _VerticalProfilePoint(
              name: point.fixIdentifier,
              coordinate: point.coordinate,
              altitudeFt: point.altitudeFt,
            ))
        .toList();
    final LatLng? runway = await _findRunwayCoordinate(procedureName, profilePoints);
    _updateProfileDistances(profilePoints, runway);
    setState(() {
      _verticalProfilePoints
        ..clear()
        ..addAll(profilePoints);
    });
    _notifyPaint();
  }

  Future<LatLng?> _findRunwayCoordinate(
      String procedureName,
      List<_VerticalProfilePoint> points,
    ) async {
    final RegExp runwayExp = RegExp(r'^RW\d+[LRC]?$');
    for (final point in points) {
      if (runwayExp.hasMatch(point.name)) {
        return point.coordinate;
      }
    }
    final List<String> segments = procedureName.split(".");
    if (segments.isEmpty) {
      return null;
    }
    final String airportId = segments[0].trim().toUpperCase();
    String runway = "";
    if (segments.length > 1) {
      runway = segments[1].toUpperCase().replaceAll(RegExp(r'[^0-9LRC]'), '');
      if (runway.isNotEmpty) {
        runway = _normalizeRunwayIdent(runway);
      }
    }
    if (runway.isEmpty) {
      return null;
    }
    final AirportDestination? airport = await MainDatabaseHelper.db.findAirport(airportId);
    if (airport == null) {
      return null;
    }
    return Airport.findCoordinatesFromRunway(airport, "RW$runway");
  }

  String _normalizeRunwayIdent(String runway) {
    final RegExp exp = RegExp(r'^(?<num>\d+)(?<side>[LRC]?)$');
    final Match? match = exp.firstMatch(runway);
    if (match == null) {
      return runway;
    }
    String number = match.group(1) ?? runway;
    final String side = match.group(2) ?? "";
    if (number.length == 1) {
      number = "0$number";
    }
    return "$number$side";
  }

  void _updateProfileDistances(List<_VerticalProfilePoint> points, LatLng? runway) {
    if (points.isEmpty) {
      return;
    }
    double cumulative = 0;
    final List<double> distancesFromStart = List.filled(points.length, 0);
    distancesFromStart[0] = 0;
    points[0].distanceNm = 0;
    for (int index = 1; index < points.length; index++) {
      final double segmentNm =
          _profileDistance(points[index - 1].coordinate, points[index].coordinate) *
              _metersToNm;
      cumulative += segmentNm;
      distancesFromStart[index] = cumulative;
      points[index].distanceNm = cumulative;
    }
    if (runway == null) {
      return;
    }
    final double? runwayDistance = _distanceAlongPath(points, distancesFromStart, runway);
    if (runwayDistance == null) {
      return;
    }
    for (int index = 0; index < points.length; index++) {
      points[index].distanceNm = (distancesFromStart[index] - runwayDistance).abs();
    }
  }

  double? _distanceAlongPath(
      List<_VerticalProfilePoint> points,
      List<double> distancesFromStart,
      LatLng target,
    ) {
    if (points.length < 2) {
      return null;
    }
    double bestSq = double.infinity;
    double? bestDistance;
    for (int index = 0; index < points.length - 1; index++) {
      final LatLng a = points[index].coordinate;
      final LatLng b = points[index + 1].coordinate;
      final double refLat = GeoCalculations.toRadians((a.latitude + b.latitude) / 2);
      final Offset aNm = _toLocalNm(a, refLat);
      final Offset bNm = _toLocalNm(b, refLat);
      final Offset pNm = _toLocalNm(target, refLat);
      final Offset ab = bNm - aNm;
      final Offset ap = pNm - aNm;
      final double abLenSq = ab.dx * ab.dx + ab.dy * ab.dy;
      if (abLenSq == 0) {
        continue;
      }
      double t = (ap.dx * ab.dx + ap.dy * ab.dy) / abLenSq;
      t = t.clamp(0, 1).toDouble();
      final Offset proj = Offset(aNm.dx + ab.dx * t, aNm.dy + ab.dy * t);
      final Offset diff = pNm - proj;
      final double distSq = diff.dx * diff.dx + diff.dy * diff.dy;
      if (distSq < bestSq) {
        bestSq = distSq;
        final double segmentDistance = distancesFromStart[index + 1] - distancesFromStart[index];
        bestDistance = distancesFromStart[index] + segmentDistance * t;
      }
    }
    return bestDistance;
  }

  Offset _toLocalNm(LatLng point, double refLat) {
    const double earthRadiusNm = 3440.069;
    final double lat = GeoCalculations.toRadians(point.latitude);
    final double lon = GeoCalculations.toRadians(point.longitude);
    return Offset(
      lon * cos(refLat) * earthRadiusNm,
      lat * earthRadiusNm,
    );
  }

  Widget _makeContent(PlatesFuture? future) {

    double height = 0;

    if(future == null || future.airports.isEmpty) {
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
    _updateSelectedProcedure(procedureNames);

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
            child: CustomPaint(painter: _PlatePainter(notifier, _terrainCells, opacity)),
          )
      ),

      _buildVerticalProfileOverlay(context, notifier),

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
                          value: procedures.contains(_selectedProcedure) ? _selectedProcedure : procedures[0],
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
                            setState(() {
                              _selectedProcedure = value;
                              _verticalProfileKey = "${Storage().settings.getCurrentPlateAirport()}|"
                                  "${Storage().currentPlate}|$value";
                              _verticalProfilePoints.clear();
                            });
                            _loadVerticalProfile(value);
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

  Widget _buildVerticalProfileOverlay(BuildContext context, ValueNotifier notifier) {
    if (_selectedProcedure == null || _verticalProfilePoints.isEmpty) {
      return Container();
    }
    final double screenHeight = Constants.screenHeight(context);
    final double screenWidth = Constants.screenWidth(context);
    final double height = max(120, screenHeight * (Constants.isPortrait(context) ? 0.22 : 0.3));
    final double width = screenWidth * 0.9;
    final Color background = Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.8);
    final Color textColor = Theme.of(context).colorScheme.onSurface;
    final Color axisColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4);
    final Color lineColor = Theme.of(context).colorScheme.secondary;
    final Color planeColor = Constants.planeColor.withValues(alpha: 0.9);

    return Positioned(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: IgnorePointer(
          child: Padding(
            padding: EdgeInsets.only(bottom: Constants.bottomPaddingSize(context) + 60),
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: axisColor),
              ),
              child: CustomPaint(
                painter: _VerticalProfilePainter(
                  notifier,
                  _verticalProfilePoints,
                  label: _selectedProcedure ?? "",
                  textColor: textColor,
                  axisColor: axisColor,
                  lineColor: lineColor,
                  planeColor: planeColor,
                ),
              ),
            ),
          ),
        ),
      ),
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

  _PlatePainter(ValueNotifier repaint, this._terrainCells, this.opacity): super(repaint: repaint);

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
      }
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

  @override
  bool shouldRepaint(_PlatePainter oldDelegate) => true;
}

class _VerticalProfilePoint {
  final String name;
  final LatLng coordinate;
  final double? altitudeFt;
  double distanceNm;
  _VerticalProfilePoint({
    required this.name,
    required this.coordinate,
    required this.altitudeFt,
    this.distanceNm = 0,
  });
}

class _VerticalProfilePainter extends CustomPainter {
  static const double _earthRadiusNm = 3440.069;
  final List<_VerticalProfilePoint> points;
  final String label;
  final Color textColor;
  final Paint _axisPaint;
  final Paint _gridPaint;
  final Paint _linePaint;
  final Paint _pointPaint;
  final Paint _planePaint;

  _VerticalProfilePainter(
      ValueNotifier repaint,
      this.points, {
      required this.label,
      required this.textColor,
      required Color axisColor,
      required Color lineColor,
      required Color planeColor,
    }) :
      _axisPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = axisColor,
      _gridPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = axisColor.withValues(alpha: 0.3),
      _linePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = lineColor,
      _pointPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = lineColor,
      _planePaint = Paint()
        ..style = PaintingStyle.fill
        ..color = planeColor,
      super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      return;
    }
    final List<_VerticalProfilePoint> altitudePoints =
        points.where((point) => point.altitudeFt != null).toList();
    if (altitudePoints.isEmpty) {
      return;
    }
    const double leftPad = 42;
    const double topPad = 20;
    const double rightPad = 12;
    const double bottomPad = 30;
    final Rect chart = Rect.fromLTRB(
      leftPad,
      topPad,
      size.width - rightPad,
      size.height - bottomPad,
    );
    if (chart.width <= 0 || chart.height <= 0) {
      return;
    }

    canvas.drawRect(chart, _axisPaint);
    _drawText(canvas, label, Offset(chart.left, 2), fontSize: 11, fontWeight: FontWeight.bold);

    double minAlt = altitudePoints
        .map((point) => point.altitudeFt!)
        .reduce(min);
    double maxAlt = altitudePoints
        .map((point) => point.altitudeFt!)
        .reduce(max);
    final double planeAlt = GeoCalculations.convertAltitude(Storage().position.altitude);
    minAlt = min(minAlt, planeAlt);
    maxAlt = max(maxAlt, planeAlt);
    if ((maxAlt - minAlt) < 500) {
      final double mid = (minAlt + maxAlt) / 2;
      minAlt = mid - 250;
      maxAlt = mid + 250;
    }
    final double padding = max(100, (maxAlt - minAlt) * 0.1);
    minAlt = max(0, minAlt - padding);
    maxAlt = maxAlt + padding;
    minAlt = (minAlt / 100).floor() * 100;
    maxAlt = (maxAlt / 100).ceil() * 100;
    if (maxAlt == minAlt) {
      maxAlt = minAlt + 100;
    }

    double totalDistance = points
        .map((point) => point.distanceNm)
        .reduce(max);
    if (totalDistance <= 0) {
      totalDistance = 1;
    }

    for (double tick = minAlt; tick <= maxAlt; tick += 100) {
      final double y = _yForAltitude(chart, tick, minAlt, maxAlt);
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), _gridPaint);
      _drawText(
        canvas,
        "${tick.round()} ft",
        Offset(chart.left - 6, y - 5),
        align: TextAlign.right,
        fontSize: 8,
      );
    }

    _drawText(
      canvas,
      "0 nm",
      Offset(chart.left, chart.bottom + 2),
    );
    _drawText(
      canvas,
      "${totalDistance.toStringAsFixed(1)} nm",
      Offset(chart.right, chart.bottom + 2),
      align: TextAlign.right,
    );

    final ui.Path path = ui.Path();
    bool hasStarted = false;
    for (final point in points) {
      final double? altitude = point.altitudeFt;
      if (altitude == null) {
        hasStarted = false;
        continue;
      }
      final double x = _xForDistance(chart, point.distanceNm, totalDistance);
      final double y = _yForAltitude(chart, altitude, minAlt, maxAlt);
      if (!hasStarted) {
        path.moveTo(x, y);
        hasStarted = true;
      }
      else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, _linePaint);

    for (final point in points) {
      if (point.altitudeFt == null) {
        continue;
      }
      final double x = _xForDistance(chart, point.distanceNm, totalDistance);
      final double y = _yForAltitude(chart, point.altitudeFt!, minAlt, maxAlt);
      canvas.drawCircle(Offset(x, y), 2.5, _pointPaint);
    }

    double lastLabelRight = -double.infinity;
    for (final point in altitudePoints) {
      final double x = _xForDistance(chart, point.distanceNm, totalDistance);
      canvas.drawLine(
        Offset(x, chart.bottom),
        Offset(x, chart.bottom + 4),
        _axisPaint,
      );
      final String label = point.name;
      if (label.isEmpty) {
        continue;
      }
      final TextPainter measure = _measureText(label, fontSize: 9);
      final double clampedX = x
          .clamp(chart.left + measure.width / 2, chart.right - measure.width / 2)
          .toDouble();
      final double left = clampedX - measure.width / 2;
      final double right = clampedX + measure.width / 2;
      if (left <= lastLabelRight + 4) {
        continue;
      }
      _drawText(
        canvas,
        label,
        Offset(clampedX, chart.bottom + 14),
        align: TextAlign.center,
        fontSize: 9,
      );
      lastLabelRight = right;
    }

    final LatLng plane = Gps.toLatLng(Storage().position);
    final double? planeDistance = _closestDistanceAlongPath(points, plane);
    if (planeDistance != null) {
      final double clampedDistance = planeDistance.clamp(0, totalDistance).toDouble();
      final double x = _xForDistance(chart, clampedDistance, totalDistance);
      double y = _yForAltitude(chart, planeAlt, minAlt, maxAlt);
      y = y.clamp(chart.top, chart.bottom).toDouble();
      canvas.drawCircle(Offset(x, y), 3.5, _planePaint);
    }
  }

  double _xForDistance(Rect chart, double distance, double totalDistance) {
    return chart.left + (distance / totalDistance) * chart.width;
  }

  double _yForAltitude(Rect chart, double altitude, double minAlt, double maxAlt) {
    return chart.bottom - ((altitude - minAlt) / (maxAlt - minAlt)) * chart.height;
  }

  TextPainter _measureText(String text, {double fontSize = 10, FontWeight fontWeight = FontWeight.normal}) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: textColor, fontSize: fontSize, fontWeight: fontWeight),
      ),
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    return tp;
  }

  void _drawText(
      Canvas canvas,
      String text,
      Offset position, {
      TextAlign align = TextAlign.left,
      double fontSize = 10,
      FontWeight fontWeight = FontWeight.normal,
    }) {
    final TextPainter tp = _measureText(text, fontSize: fontSize, fontWeight: fontWeight);
    Offset drawOffset = position;
    if (align == TextAlign.center) {
      drawOffset = Offset(position.dx - tp.width / 2, position.dy);
    }
    else if (align == TextAlign.right) {
      drawOffset = Offset(position.dx - tp.width, position.dy);
    }
    tp.paint(canvas, drawOffset);
  }

  double? _closestDistanceAlongPath(List<_VerticalProfilePoint> points, LatLng plane) {
    if (points.length < 2) {
      return null;
    }
    double bestSq = double.infinity;
    double? bestAlong;
    for (int index = 0; index < points.length - 1; index++) {
      final LatLng a = points[index].coordinate;
      final LatLng b = points[index + 1].coordinate;
      final double refLat = GeoCalculations.toRadians((a.latitude + b.latitude) / 2);
      final Offset aNm = _toLocalNm(a, refLat);
      final Offset bNm = _toLocalNm(b, refLat);
      final Offset pNm = _toLocalNm(plane, refLat);
      final Offset ab = bNm - aNm;
      final Offset ap = pNm - aNm;
      final double abLenSq = ab.dx * ab.dx + ab.dy * ab.dy;
      if (abLenSq == 0) {
        continue;
      }
      double t = (ap.dx * ab.dx + ap.dy * ab.dy) / abLenSq;
      t = t.clamp(0, 1).toDouble();
      final Offset proj = Offset(aNm.dx + ab.dx * t, aNm.dy + ab.dy * t);
      final Offset diff = pNm - proj;
      final double distSq = diff.dx * diff.dx + diff.dy * diff.dy;
      if (distSq < bestSq) {
        bestSq = distSq;
        final double segmentDistance = points[index + 1].distanceNm - points[index].distanceNm;
        bestAlong = points[index].distanceNm + segmentDistance * t;
      }
    }
    return bestAlong;
  }

  Offset _toLocalNm(LatLng point, double refLat) {
    final double lat = GeoCalculations.toRadians(point.latitude);
    final double lon = GeoCalculations.toRadians(point.longitude);
    return Offset(
      lon * cos(refLat) * _earthRadiusNm,
      lat * _earthRadiusNm,
    );
  }

  @override
  bool shouldRepaint(_VerticalProfilePainter oldDelegate) => true;
}

class _PlateTerrainCell {
  final Rect rect;
  final double elevationFt;
  const _PlateTerrainCell({required this.rect, required this.elevationFt});
}

