import 'dart:io';

import 'package:avaremp/main_database_helper.dart';
import 'package:avaremp/metar_cache.dart';
import 'package:avaremp/plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/warnings_widget.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:path/path.dart';

import 'chart.dart';
import 'constants.dart';
import 'destination.dart';
import 'download_screen.dart';
import 'gps.dart';
import 'longpress_widget.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<StatefulWidget> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {

  final List<String> _charts = DownloadScreenState.getCategories();
  LatLng? _previousPosition;
  bool _interacting = false;

  String _type = Storage().settings.getChartType();
  int _maxZoom = ChartCategory.chartTypeToZoom(Storage().settings.getChartType());
  MapController? _controller;
  // get layers and states from settings
  final List<String> _layers = Storage().settings.getLayers();
  final List<bool> _layersState = Storage().settings.getLayersState();
  bool _northUp = Storage().settings.getNorthUp();

  Future<bool> showDestination(BuildContext context, Destination destination) async {
    bool? exitResult = await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return LongPressWidget(destination: destination);
      },
    );
    return exitResult ?? false;
  }

  void _handlePress(TapPosition tapPosition, LatLng point) async {

    List<Destination> items = await MainDatabaseHelper.db.findNear(point);
    setState(() {
      showDestination(this.context, items[0]);
    });
  }

  @override
  void initState() {
    _controller = MapController();
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    // save ptz when we switch out
    if(_controller != null) {
      Storage().settings.setZoom(_controller!.camera.zoom);
      Storage().settings.setCenterLatitude(_controller!.camera.center.latitude);
      Storage().settings.setCenterLongitude(
          _controller!.camera.center.longitude);
      Storage().settings.setRotation(_controller!.camera.rotation);
      Storage().gpsChange.removeListener(listen);
      _previousPosition = null;
      _controller!.dispose();
      _controller = null;
    }
  }

  // this pans camera on move
  void listen() {
    LatLng cur = Gps.toLatLng(Storage().position);
    _previousPosition ??= cur;
    if(null != _controller) {
      LatLng diff = LatLng(cur.latitude - _previousPosition!.latitude,
          cur.longitude - _previousPosition!.longitude);
      LatLng now = _controller!.camera.center;
      LatLng next = LatLng(
          now.latitude + diff.latitude, now.longitude + diff.longitude);
      if (!_interacting) { // do not move when user is moving map
        _controller!.moveAndRotate(next, _controller!.camera.zoom, _northUp ? 0 : -Storage().position.heading);
      }
    }

    _previousPosition = Gps.toLatLng(Storage().position);
  }

  @override
  Widget build(BuildContext context) {

    String index = ChartCategory.chartTypeToIndex(_type);
    _maxZoom = ChartCategory.chartTypeToZoom(_type);

    //add layers
    List<Widget> layers = [];
    TileLayer networkLayer = TileLayer(
      urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
      userAgentPackageName: 'dev.fleaflet.flutter_map.example',
      tileProvider: FMTC.instance('mapStore').getTileProvider());
    TileLayer chartLayer = TileLayer(
      tms: true,
      maxNativeZoom: _maxZoom,
      tileProvider: ChartTileProvider(),
      //urlTemplate: 'c:\\temp\\tiles\\$index\\{z}\\{x}\\{y}.webp' for testing on PC,
      urlTemplate: "${Storage().dataDir}/tiles/$index/{z}/{x}/{y}.webp",
      userAgentPackageName: 'com.apps4av.avaremp');

    // start from known location
    MapOptions opts = MapOptions(
      initialCenter: LatLng(Storage().settings.getCenterLatitude(), Storage().settings.getCenterLongitude()),
      initialZoom: Storage().settings.getZoom(),
      minZoom: 0,
      maxZoom: 20, // max for USGS
      interactionOptions: InteractionOptions(flags: _northUp ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.all),  // no rotation in track up
      initialRotation: Storage().settings.getRotation(),
      backgroundColor: Constants.mapBackgroundColor,
      onLongPress: _handlePress,
      onMapEvent: (mapEvent) {
        if (mapEvent is MapEventMoveStart) {
          // do something
          _interacting = true;
        }
        if (mapEvent is MapEventMoveEnd) {
          // do something
          _interacting = false;
        }
      },
    );

    int lIndex = _layers.indexOf('OSM');
    if(_layersState[lIndex]) {
      layers.add(networkLayer);
    }
    lIndex = _layers.indexOf('Chart');
    if(_layersState[lIndex]) {
      layers.add(chartLayer);
    }

    lIndex = _layers.indexOf('METAR');
    if(_layersState[lIndex]) {
      layers.add(
          ValueListenableBuilder<int>(
              valueListenable: Storage().metar.change,
              builder: (context, value, _) {
                return OverlayImageLayer(
                  overlayImages: [
                    if(null != Storage().metar.image)
                      OverlayImage(
                        bounds: LatLngBounds(
                          MetarCache.topLeft,
                          MetarCache.bottomRight,
                        ),
                        opacity: 0.5,
                        imageProvider: MemoryImage(Storage().metar.image!),
                      ),
                  ],
                );
              }
          )
      );
    }

    lIndex = _layers.indexOf('Circles');
    if(_layersState[lIndex]) {
      layers.add( // circle layer
        ValueListenableBuilder<Position>(
          valueListenable: Storage().gpsChange,
          builder: (context, value, _) {
            return CircleLayer(
              circles: [
                // 10 nm circle
                CircleMarker(
                  borderStrokeWidth: 4,
                  borderColor: Constants.distanceCircleColor,
                  color: Colors.transparent,
                  radius: Constants.nmToM(10), // 10 nm circle
                  useRadiusInMeter: true,
                  point: Gps.toLatLng(value),
                ),
                // speed marker
                CircleMarker(
                  borderStrokeWidth: 4,
                  borderColor: Constants.speedCircleColor,
                  color: Colors.transparent,
                  radius: value.speed * 60, // 1 minute speed
                  useRadiusInMeter: true,
                  point: Gps.toLatLng(value),
                ),
              ],
            );
          },
        ),
      );
    }

    lIndex = _layers.indexOf('Nav');
    if(_layersState[lIndex]) {
      layers.add( // route layer
        ValueListenableBuilder<int>(
          valueListenable: Storage().route.change,
          builder: (context, value, _) {
            return PolylineLayer(
              polylines: [
                // route
                Polyline(
                    borderStrokeWidth: 1,
                    borderColor: Constants.planBorderColor,
                    strokeWidth: 6,
                    points: Storage().route.getPathPassed(),
                    color: Constants.planPassedColor,
                    isDotted: true
                ),
                Polyline(
                  borderStrokeWidth: 2,
                  borderColor: Constants.planBorderColor,
                  strokeWidth: 4,
                  strokeCap: StrokeCap.round,
                  points: Storage().route.getPathCurrent(),
                  color: Constants.planCurrentColor,
                ),
                Polyline(
                  borderStrokeWidth: 1,
                  borderColor: Constants.planBorderColor,
                  strokeWidth: 6,
                  points: Storage().route.getPathNext(),
                  color: Constants.planNextColor,
                  isDotted: true
                ),
              ],
            );
          },
        ),
      );

      layers.add( // track layer
        ValueListenableBuilder<Position>(
          valueListenable: Storage().gpsChange,
          builder: (context, value, _) {
            // this place
            PlanRoute here = Storage().route;
            List<LatLng> path = here.getPathFromLocation(value);
            return PolylineLayer(
              polylines: [
                Polyline(
                  isDotted: true,
                  strokeWidth: 4,
                  points: path,
                  color: Constants.trackColor,
                ),
              ],
            );
          },
        ),
      );

      layers.add(
        // aircraft layer
        ValueListenableBuilder<Position>(
          valueListenable: Storage().gpsChange,
          builder: (context, value, _) {
            LatLng current = LatLng(value.latitude, value.longitude);

            return MarkerLayer(
              markers: [
                Marker( // our position and heading to destination
                    width: 32,
                    height: (Constants.screenWidth(context) +
                        Constants.screenHeight(context)) / 4,
                    point: current,
                    child: Transform.rotate(angle: value.heading * pi / 180,
                        child: CustomPaint(painter: Plane())
                    )),
              ],
            );
          },
        ),
      );
    }

    FlutterMap map = FlutterMap(
      mapController: _controller,
      options: opts,
      children: layers,
    );

    // move with airplane but do not hold the map
    Storage().gpsChange.addListener(listen);

    return Scaffold(
        endDrawer: Padding(padding: EdgeInsets.fromLTRB(0, Constants.screenHeight(context) / 8, 0, Constants.screenHeight(context) / 10),
          child: ValueListenableBuilder<bool>(
              valueListenable: Storage().warningChange,
              builder: (context, value, _) {
                return WarningsWidget(gpsNotPermitted: Storage().gpsNotPermitted,
                  gpsDisabled: Storage().gpsDisabled, chartsMissing: Storage().chartsMissing,
                  dataExpired: Storage().dataExpired,);
              }
            )
        ),
        endDrawerEnableOpenDragGesture: false,
        body: Stack(
            children: [
              map, // map

              // warn
              Positioned(
                child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                        padding: EdgeInsets.fromLTRB(5, Constants.appbarMaxSize(context) ?? 5, 5, 5),
                        child: ValueListenableBuilder<bool>(
                            valueListenable: Storage().warningChange,
                            builder: (context, value, _) {
                              return WarningsButtonWidget(warning: value);
                            }
                        )
                    )
                ),
              ),

              // center
              Positioned(
                  child: Align(
                      alignment: Alignment.bottomCenter,
                      child:
                      Padding(
                        padding: EdgeInsets.fromLTRB(5, 5, 5, Constants.bottomPaddingSize(context)),
                        child:
                        TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: Constants.centerButtonBackgroundColor,
                            padding: const EdgeInsets.all(5.0),
                          ),
                          onPressed: () {
                            Position p = Storage().position;
                            LatLng l = LatLng(p.latitude, p.longitude);
                            if(_northUp) {
                              _controller == null ? {} : _controller!.moveAndRotate(l, _maxZoom.toDouble(), 0);// rotate to heading on center on track up
                            }
                            else {
                              _controller == null ? {} : _controller!.moveAndRotate(l, _maxZoom.toDouble(), -p.heading);
                            }
                          },
                          child: const Text("Center"),
                        ),
                      )
                  )
              ),

              // menus
              Positioned(
                  child: Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                          padding: EdgeInsets.fromLTRB(5, Constants.appbarMaxSize(context) ?? 5, 5, 5),
                          child: Row(children:[
                            // menu
                            Container(
                                padding: const EdgeInsets.fromLTRB(5, 5, 5, 5),
                                child:
                                TextButton(
                                  style: TextButton.styleFrom(
                                    backgroundColor: Constants.centerButtonBackgroundColor,
                                    padding: const EdgeInsets.all(5.0),
                                  ),
                                  onPressed: () {
                                    Scaffold.of(context).openDrawer();
                                  },
                                  child: const Text("Menu"),
                                )),

                            // chart select
                            DropdownButtonHideUnderline(
                                child:DropdownButton2<String>(

                                  buttonStyleData: ButtonStyleData(
                                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Constants.dropDownButtonBackgroundColor),
                                  ),
                                  dropdownStyleData: DropdownStyleData(
                                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  isExpanded: false,
                                  value: _type,
                                  items: _charts.map((String item) {
                                    return DropdownMenuItem<String>(
                                        value: item,
                                        child: Text(item, style: TextStyle(fontSize: Constants.dropDownButtonFontSize))
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    setState(() {
                                      Storage().settings.setChartType(value ?? _charts[0]);
                                      _type = Storage().settings.getChartType();
                                    });
                                  },
                                )
                            ),

                            // switch layers on off
                            PopupMenuButton( // airport selection

                                padding: const EdgeInsets.fromLTRB(5, 5, 5, 5),
                                icon: CircleAvatar(backgroundColor: Constants.dropDownButtonBackgroundColor, child: const Icon(Icons.layers)),
                                initialValue: _layers[0],
                                itemBuilder: (BuildContext context) =>
                                    List.generate(_layers.length, (int index) => PopupMenuItem(
                                        child: StatefulBuilder(
                                            builder: (context1, setState1) =>
                                                ListTile(
                                                  dense: true,
                                                  title: Text(_layers[index]),
                                                  subtitle: _layersState[index] ? const Text("Layer is On") : const Text("Layer is Off"),
                                                  leading: Switch(
                                                    value: _layersState[index],
                                                    onChanged: (bool value) {
                                                      setState1(() {
                                                        _layersState[index] = value; // this is state for the switch
                                                      });
                                                      // now save to settings
                                                      Storage().settings.setLayersState(_layersState);
                                                      setState(() {
                                                        _layersState[index] = value; // this is the state for the map
                                                      });
                                                    },
                                                  ),
                                                ),
                                        ),
                                      )
                                    ),
                            ),


                            // north up
                            IconButton(
                              padding: const EdgeInsets.fromLTRB(5, 5, 5, 5),
                              onPressed: () {
                                setState(() {
                                  _northUp = _northUp ? false : true;
                                });
                                Storage().settings.setNorthUp(_northUp); // save
                              },
                              icon: ValueListenableBuilder<Position>(
                                valueListenable: Storage().gpsChange,
                                builder: (context, value, _) {
                                  return CircleAvatar( // in track up, rotate icon
                                      backgroundColor: Constants.dropDownButtonBackgroundColor,
                                      child: _northUp ? Icon(MdiIcons.navigation) :
                                      Transform.rotate(
                                          angle: value.heading * pi / 180,
                                          child: Icon(MdiIcons.arrowUpThinCircleOutline)));
                                }
                              )),
                          ]
                        )
                      )
                  )
              )
            ]
        )
    );
  }
  // implements a drawing screen with a center reset button.
}

class Plane extends CustomPainter {


  final _paintCenter = Paint()
    ..style = PaintingStyle.fill
    ..strokeWidth = 6
    ..strokeCap = StrokeCap.square
    ..color = Constants.planeColor;

  @override
  void paint(Canvas canvas, Size size) {

    // draw plane
    canvas.drawLine(Offset(size.width / 2, size.height / 2 + 16), Offset(size.width / 2, size.height / 2 + 16), _paintCenter);
    canvas.drawLine(Offset(size.width / 2, size.height / 2 + 8), Offset(size.width / 2, 0), _paintCenter);
    canvas.drawLine(Offset(size.width / 2 - 16, size.height / 2), Offset(size.width / 2 + 16, size.height / 2), _paintCenter);
  }

  @override
  bool shouldRepaint(Plane oldDelegate) => false;
}

// custom tile provider
class ChartTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    File f = File(getTileUrl(coordinates, options));
    if(f.existsSync()) {
      // get rid of annoying tile name error problem by providing a transparent tile
      return FileImage(File(getTileUrl(coordinates, options)));
    }
    return FileImage(File(join(Storage().dataDir, "256.png")));
  }
}
