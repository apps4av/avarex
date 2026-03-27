import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:avaremp/data/business_database_helper.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/instruments/plate_profile_widget.dart';
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
  final TransformationController _transformationController = TransformationController();

  @override
  void initState() {
    super.initState();
    _transformationController.value = Storage().plateTransform;
    _transformationController.addListener(_onTransformChanged);
  }

  void _onTransformChanged() {
    Storage().plateTransform = _transformationController.value.clone();
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformChanged);
    _transformationController.dispose();
    super.dispose();
    Storage().plateChange.removeListener(_notifyPaint);
    Storage().gpsChange.removeListener(_notifyPaint);
    Storage().planeIconChange.removeListener(_notifyPaint);
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
      _transformationController.value = Matrix4.identity();
    }

    _loadPlate();

    // plate load notification, repaint
    Storage().plateChange.addListener(_notifyPaint);
    Storage().gpsChange.addListener(_notifyPaint);
    Storage().planeIconChange.addListener(_notifyPaint);

    List<String> procedureNames = [];
    for(String prec in procedures) {
      if(doesProcedureBelongsToThisPlate(Storage().currentPlate, prec)) {
        procedureNames.add(prec);
      }
    }

    return makePlateView(airports, plates, procedureNames, business, height, _notifier);
  }

  Widget makePlateView(List<String> airports, List<String> plates, List<String> procedures, List<Destination> business, double height, ValueNotifier notifier) {

    bool notAd = !PathUtils.isAirportDiagram(Storage().currentPlate);
    if (notAd) {
      Storage().business = null;
    }

    final List<String> layers = Storage().settings.getLayers();
    final List<double> layersOpacity = Storage().settings.getLayersOpacity();
    final double opacity = layersOpacity[layers.indexOf("Elevation")];
    final Color overlayBg = Theme.of(context).colorScheme.surface.withAlpha(200);

    // Empty state when no airports/plates
    if (airports.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                "No plates available",
                style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 8),
              Text(
                "Search for an airport to view plates",
                style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          InteractiveViewer(
            transformationController: _transformationController,
            minScale: 0.1,
            maxScale: 8,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            child: SizedBox(
              height: Constants.screenHeight(context),
              width: Constants.screenWidth(context),
              child: CustomPaint(painter: _PlatePainter(notifier, _terrainCells, opacity)),
            ),
          ),

          // Instruments panel (top left)
          Positioned(
            child: Align(
              alignment: Alignment.topLeft,
              child: Storage().settings.isInstrumentsVisiblePlate()
                  ? SizedBox(height: Constants.screenHeightForInstruments(context), child: const InstrumentList())
                  : Container(),
            ),
          ),

          // Instrument toggle button (top right)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              decoration: BoxDecoration(
                color: overlayBg,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: () {
                  setState(() {
                    Storage().settings.setInstrumentsVisiblePlate(!Storage().settings.isInstrumentsVisiblePlate());
                  });
                },
                icon: Icon(
                  Storage().settings.isInstrumentsVisiblePlate() ? MdiIcons.arrowCollapseRight : MdiIcons.arrowCollapseLeft,
                  size: 20,
                ),
                tooltip: Storage().settings.isInstrumentsVisiblePlate() ? "Hide instruments" : "Show instruments",
              ),
            ),
          ),

          // Auto-show airport diagram toggle (top right, below instruments toggle)
          if (!notAd)
            Positioned(
              top: Constants.screenHeightForInstruments(context) + 12,
              right: 12,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    bool show = Storage().settings.isShowAirportDiagramOnLanding();
                    Toast.showToast(
                      context,
                      show ? "Airport diagram auto switch disabled" : "Airport diagram will be shown automatically on landing",
                      null,
                      3,
                    );
                    Storage().settings.setShowAirportDiagramOnLanding(!show);
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: overlayBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Storage().settings.isShowAirportDiagramOnLanding() ? Icons.flight_land : Icons.flight_land_outlined,
                    size: 24,
                    color: Storage().settings.isShowAirportDiagramOnLanding() ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
              ),
            ),

          // Center button (bottom center)
          Positioned(
            bottom: Constants.bottomPaddingSize(context) + 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  color: overlayBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  onPressed: () {
                    final double currentScale = _transformationController.value.getMaxScaleOnAxis();
                    _transformationController.value = Matrix4.identity()..scaleByDouble(currentScale, currentScale, 1, 1);
                  },
                  onLongPress: () {
                    _transformationController.value = Matrix4.identity();
                  },
                  child: const Text("Center"),
                ),
              ),
            ),
          ),

          // Plate selector (bottom left)
          if (plates.isNotEmpty && plates[0].isNotEmpty)
            Positioned(
              bottom: Constants.bottomPaddingSize(context) + 8,
              left: 12,
              child: Container(
                decoration: BoxDecoration(
                  color: overlayBg,
                  shape: BoxShape.circle,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton2<String>(
                    isDense: true,
                    customButton: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.menu, color: Theme.of(context).colorScheme.primary),
                    ),
                    buttonStyleData: ButtonStyleData(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.transparent),
                    ),
                    dropdownStyleData: DropdownStyleData(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
                      width: Constants.screenWidth(context) * 0.8,
                      maxHeight: Constants.screenHeight(context) * 0.6,
                    ),
                    isExpanded: false,
                    value: plates.contains(Storage().currentPlate) ? Storage().currentPlate : plates[0],
                    items: plates.map((String item) {
                      final bool isSelected = item == Storage().currentPlate;
                      return DropdownMenuItem<String>(
                        value: item,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: _getPlateColor(item).withAlpha(isSelected ? 180 : 100),
                            borderRadius: BorderRadius.circular(6),
                            border: isSelected ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2) : null,
                          ),
                          child: Row(
                            children: [
                              Icon(_getPlateIcon(item), size: 16, color: Colors.white),
                              const SizedBox(width: 8),
                              Expanded(
                                child: AutoSizeText(
                                  item,
                                  minFontSize: 8,
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        Storage().currentPlate = value ?? plates[0];
                        _transformationController.value = Matrix4.identity();
                      });
                    },
                  ),
                ),
              ),
            ),

          // Business selector (center right, only on airport diagrams)
          if (business.isNotEmpty && !notAd)
            Positioned(
              right: 8,
              top: Constants.screenHeight(context) / 2 - 20,
              child: Container(
                decoration: BoxDecoration(
                  color: overlayBg,
                  shape: BoxShape.circle,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton2<String>(
                    isDense: true,
                    customButton: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.business, color: Theme.of(context).colorScheme.primary),
                    ),
                    buttonStyleData: ButtonStyleData(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.transparent),
                    ),
                    dropdownStyleData: DropdownStyleData(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
                      width: Constants.screenWidth(context) * 0.75,
                    ),
                    isExpanded: false,
                    value: business.contains(Storage().business) ? Storage().business!.facilityName : business[0].facilityName,
                    items: business.map((Destination item) {
                      return DropdownMenuItem<String>(
                        value: item.facilityName,
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.location_on, size: 18),
                          title: Text(item.facilityName, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        Storage().business = value == null
                            ? business[0]
                            : business.firstWhere((element) => element.facilityName == value, orElse: () => business[0]);
                      });
                    },
                  ),
                ),
              ),
            ),

          // Airport selector and procedures (bottom right)
          Positioned(
            bottom: Constants.bottomPaddingSize(context) + 8,
            right: 8,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Procedures selector
                if (procedures.isNotEmpty && procedures[0].isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: overlayBg,
                        shape: BoxShape.circle,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton2<String>(
                          isDense: true,
                          customButton: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(Icons.add_road, color: Theme.of(context).colorScheme.primary),
                          ),
                          buttonStyleData: ButtonStyleData(
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.transparent),
                          ),
                          dropdownStyleData: DropdownStyleData(
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
                            width: Constants.screenWidth(context) * 0.8,
                          ),
                          isExpanded: false,
                          value: procedures[0],
                          items: procedures.map((String item) {
                            return DropdownMenuItem<String>(
                              value: item,
                              child: ListTile(
                                dense: true,
                                leading: TextButton(
                                  child: const Text("+Plan"),
                                  onPressed: () {
                                    Navigator.pop(context);
                                    MainDatabaseHelper.db.findProcedure(item).then((ProcedureDestination? procedure) {
                                      if (procedure != null) {
                                        Storage().route.addWaypoint(Waypoint(procedure));
                                        setState(() {
                                          Toast.showToast(context, "Added ${procedure.facilityName} to Plan", null, 3);
                                        });
                                      }
                                    });
                                  },
                                ),
                                title: AutoSizeText(item, minFontSize: 8, maxLines: 1),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              Storage().settings.setPlateProfileVisible(true);
                              Storage().settings.setPlateProfile(value ?? "");
                            });
                          },
                        ),
                      ),
                    ),
                  ),

                // Airport selector
                if (airports.isNotEmpty && airports[0].isNotEmpty)
                  Container(
                    decoration: BoxDecoration(
                      color: overlayBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton2<String>(
                        buttonStyleData: ButtonStyleData(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.transparent),
                        ),
                        dropdownStyleData: DropdownStyleData(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
                        ),
                        isExpanded: false,
                        value: airports.contains(Storage().settings.getCurrentPlateAirport())
                            ? Storage().settings.getCurrentPlateAirport()
                            : airports[0],
                        items: airports.map((String item) {
                          final bool isSelected = item == Storage().settings.getCurrentPlateAirport();
                          return DropdownMenuItem<String>(
                            value: item,
                            child: Text(
                              item,
                              style: TextStyle(
                                fontSize: Constants.dropDownButtonFontSize,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            Storage().settings.setCurrentPlateAirport(value ?? airports[0]);
                            Storage().settings.setPlateProfileVisible(true);
                            Storage().settings.setPlateProfile(value ?? "");
                            _transformationController.value = Matrix4.identity();
                          });
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Plate profile widget
          if (Storage().settings.isPlateProfileVisible())
            Positioned(
              bottom: Constants.bottomPaddingSize(context) + 70,
              right: 0,
              child: Stack(
                children: [
                  IgnorePointer(child: PlateProfileWidget(selectedProcedure: Storage().settings.getPlateProfile())),
                  Positioned(
                    top: 0,
                    right: 8,
                    child: Container(
                      decoration: BoxDecoration(
                        color: overlayBg,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        iconSize: 18,
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            Storage().settings.setPlateProfileVisible(false);
                            Storage().settings.setPlateProfile("");
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  IconData _getPlateIcon(String name) {
    if (name.startsWith("APD")) {
      return Icons.local_airport;
    } else if (name.startsWith("CSUP")) {
      return Icons.info;
    } else if (name.startsWith("DP")) {
      return Icons.flight_takeoff;
    } else if (name.startsWith("IAP")) {
      return Icons.flight_land;
    } else if (name.startsWith("STAR")) {
      return Icons.trending_down;
    } else if (name.startsWith("MIN")) {
      return Icons.vertical_align_bottom;
    } else if (name.startsWith("HOT")) {
      return Icons.warning;
    } else if (name.startsWith("LAH")) {
      return Icons.warning;
    }
    return Icons.description;
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

class _PlateTerrainCell {
  final Rect rect;
  final double elevationFt;
  const _PlateTerrainCell({required this.rect, required this.elevationFt});
}

