import 'dart:io';

import 'package:avaremp/custom_widgets.dart';
import 'package:avaremp/main_database_helper.dart';
import 'package:avaremp/plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/warnings_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart';

import 'airport.dart';
import 'chart.dart';
import 'constants.dart';
import 'destination.dart';
import 'download_screen.dart';
import 'longpress_widget.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<StatefulWidget> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {

  final List<String> _charts = DownloadScreenState.getCategories();

  String _type = Storage().settings.getChartType();
  int _maxZoom = ChartCategory.chartTypeToZoom(Storage().settings.getChartType());
  final MapController _controller = MapController();

  Future<bool> showDestination(BuildContext context, Destination destination) async {
    bool? exitResult = await showModalBottomSheet(
      context: context,
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
    if(items.isEmpty) {
      return;
    }
    setState(() {
      if(Airport.isAirport(items[0].type)) {
        showDestination(this.context, items[0]);
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    // save ptz when we switch out
    Storage().settings.setZoom(_controller.camera.zoom);
    Storage().settings.setCenterLatitude(_controller.camera.center.latitude);
    Storage().settings.setCenterLongitude(_controller.camera.center.longitude);
    Storage().settings.setRotation(_controller.camera.rotation);
    _controller.dispose();
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
      interactionOptions: InteractionOptions(flags: Storage().settings.getNorthUp() ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.all),  // no rotation in track up
      initialRotation: Storage().settings.getRotation(),
      backgroundColor: Constants.mapBackgroundColor,
      onLongPress: _handlePress,
      onMapEvent: (mapEvent) {
        if (mapEvent is MapEventMoveStart) {
          // do something
        }
        if (mapEvent is MapEventMoveEnd) {
          // do something
        }
      },
    );

    // for USGS and OSM type, use Network Provider
    if(ChartCategory.isNetworkMap(_type)) {
      layers.add(networkLayer);
    }
    else {
      if(Storage().settings.showOSMBackground()) {
        layers.add(networkLayer);
      }
      layers.add(chartLayer);
    }

    layers.add( // route layer
      ValueListenableBuilder<PlanRoute?>(
        valueListenable: Storage().routeChange,
        builder: (context, value, _) {
          return PolylineLayer(
            polylines: [
              // route
              Polyline(
                borderStrokeWidth: 2,
                borderColor: Colors.black,
                strokeWidth: 4,
                strokeCap: StrokeCap.round,
                points: value == null ? [] : value.getRoute(),
                color: Colors.purpleAccent,
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
          // this leg
          PlanRoute thisRoute = PlanRoute(LatLng(value.latitude, value.longitude));
          Storage().route != null && Storage().route!.getNextWaypoint() != null ? thisRoute.addWaypoint(Storage().route!.getNextWaypoint()!) : {};
          return PolylineLayer(
            polylines: [
              Polyline(
                isDotted: true,
                strokeWidth: 4,
                points: thisRoute.getRoute(),
                color: Colors.black,
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
                  width:32,
                  height: (Constants.screenWidth(context) + Constants.screenHeight(context)) / 4,
                  point: current,
                  child: Transform.rotate(angle: value.heading * pi / 180, child: CustomPaint(painter: Plane())
              )),
            ],
          );
        },
      ),
    );

    FlutterMap map = FlutterMap(
      mapController: _controller,
      options: opts,
      children: layers,
    );


    Storage().gpsChange.addListener(() {
    });

    return Scaffold(
        endDrawer: Padding(padding: EdgeInsets.fromLTRB(0, Constants.screenHeight(context) / 8, 0, Constants.screenHeight(context) / 10),
          child: WarningsWidget(gpsNotPermitted: Storage().gpsNotPermitted,
            gpsDisabled: Storage().gpsDisabled, chartsMissing: Storage().chartsMissing,
            dataExpired: Storage().dataExpired,),
        ),
        endDrawerEnableOpenDragGesture: false,
        body: Stack(
            children: [
              map,
              CustomWidgets.dropDownButton(
              context,
              _type,
              _charts,
              Alignment.bottomLeft,
                  Constants.bottomPaddingSize(context),
              (value) {
                setState(() {
                  Storage().settings.setChartType(value ?? _charts[0]);
                  _type = Storage().settings.getChartType();
                });
              }
          ),

          Positioned(
            child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                    padding: EdgeInsets.fromLTRB(0, 0, 0, Constants.bottomPaddingSize(context)),
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: Constants.centerButtonBackgroundColor,
                        padding: const EdgeInsets.all(5.0),
                      ),
                      onPressed: () {
                        Position p = Storage().position;
                        LatLng l = LatLng(p.latitude, p.longitude);
                        if(Storage().settings.getNorthUp()) {
                          _controller.moveAndRotate(l, _maxZoom.toDouble(), 0);// rotate to heading on center on track up
                        }
                        else {
                          _controller.moveAndRotate(l, _maxZoom.toDouble(), -p.heading);
                        }
                      },
                      child: const Text("Center"),
                    ))
            ),
          ),
          Positioned(
            child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                    padding: EdgeInsets.fromLTRB(5, Constants.appbarMaxSize(context) ?? 5, 5, 5),
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: Constants.centerButtonBackgroundColor,
                        padding: const EdgeInsets.all(5.0),
                      ),
                      onPressed: () {
                        Scaffold.of(context).openDrawer();
                      },
                      child: const Text("Menu"),
                    )
                )
            ),
          ),

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
    ..color = const Color.fromARGB(255, 255, 0, 0);

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
