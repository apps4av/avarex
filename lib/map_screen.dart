import 'dart:io';

import 'package:avaremp/custom_widgets.dart';
import 'package:avaremp/download_list.dart';
import 'package:avaremp/main_database_helper.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/warnings_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart';

import 'coordinate.dart';
import 'airport.dart';
import 'chart.dart';
import 'constants.dart';
import 'destination.dart';
import 'longpress_widget.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<StatefulWidget> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {

  final List<String> _charts = DownloadListState.getCategories();

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

    List<Destination> items = await MainDatabaseHelper.db.findNear(Coordinate(Longitude(point.longitude), Latitude(point.latitude)));
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

    //add layers
    List<Widget> layers = [];

    String index = ChartCategory.chartTypeToIndex(_type);
    _maxZoom = ChartCategory.chartTypeToZoom(_type);

    // start from known location
    MapOptions opts = MapOptions(
      initialCenter: LatLng(Storage().settings.getCenterLatitude(), Storage().settings.getCenterLongitude()),
      initialZoom: Storage().settings.getZoom(),
      minZoom: 0,
      maxZoom: 18,
      interactionOptions: InteractionOptions(flags: Storage().settings.getNorthUp() ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.all),  // no rotation in track up
      initialRotation: Storage().settings.getRotation(),
      backgroundColor: Constants.mapBackgroundColor,
      onLongPress: _handlePress,
      onMapEvent: (event) {
      },
    );

    if(Storage().settings.showOSMBackground()) {
      layers.add(
        // map layer OSM for backup
        TileLayer(
          urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
          userAgentPackageName: 'dev.fleaflet.flutter_map.example',
          tileProvider: FMTC.instance('mapStore').getTileProvider(),
        ),
      );
    }

    layers.add(
      // map layer charts
      TileLayer(
        tms: true,
        maxNativeZoom: _maxZoom,
        tileProvider: ChartTileProvider(),
        //urlTemplate: 'c:\\temp\\tiles\\$index\\{z}\\{x}\\{y}.webp' for testing on PC,
        urlTemplate: "${Storage().dataDir}/tiles/$index/{z}/{x}/{y}.webp",
        userAgentPackageName: 'com.apps4av.avaremp',
      ),
    );

    layers.add( // route layer
      ValueListenableBuilder<Destination?>(
        valueListenable: Storage().destinationChange,
        builder: (context, value, _) {
          return PolylineLayer(
            polylines: [
              // route
              Polyline(
                borderStrokeWidth: 2,
                borderColor: Colors.black,
                strokeWidth: 4,
                strokeCap: StrokeCap.round,
                points: [LatLng(Storage().position.latitude, Storage().position.longitude), LatLng(value == null? Storage().position.latitude : value.coordinate.latitude.value, value == null? Storage().position.longitude : value.coordinate.longitude.value),],
                color: Colors.purpleAccent,
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
          return MarkerLayer(
            markers: [
              Marker( // our position and heading to destination
                  width: (Constants.screenWidth(context) + Constants.screenHeight(context)) / 4,
                  height: (Constants.screenWidth(context) + Constants.screenHeight(context)) / 4,
                  point: LatLng(value.latitude, value.longitude),
                  child: CustomPaint(painter: Plane(value))
              ),
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

    return Scaffold(
        endDrawer: Padding(padding: EdgeInsets.fromLTRB(0, Constants.screenHeight(context) / 8, 0, Constants.screenHeight(context) / 10),
          child: const WarningsWidget(),
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

          const Positioned(
            child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                    padding: EdgeInsets.fromLTRB(5, 5, 5, 5),
                    child: WarningsButtonWidget()
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

  Position position;

  Plane(this.position);

  final _paintCenter = Paint()
    ..style = PaintingStyle.fill
    ..strokeWidth = 6
    ..strokeCap = StrokeCap.square
    ..color = const Color.fromARGB(255, 255, 0, 0);

  final _paintToDestination = Paint()
    ..style = PaintingStyle.fill
    ..strokeWidth = 6
    ..strokeCap = StrokeCap.square
    ..color = const Color.fromARGB(255, 0, 0, 0);

  @override
  void paint(Canvas canvas, Size size) {

    double rotate = position.heading  * pi / 180;
    Destination? destination = Storage().currentDestination;
    // path to destination always points to dest
    double rotate2 = (null == destination)? 0 : Geolocator.bearingBetween(position.latitude, position.longitude,
          destination.coordinate.latitude.value, destination.coordinate.longitude.value)  * pi / 180;

    // draw path to dest
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);canvas.rotate(rotate2 * pi / 180);
    canvas.rotate(rotate2);
    canvas.translate(-size.width / 2, -size.height / 2);
    canvas.drawLine(Offset(size.width / 2, size.height / 2), Offset(size.width / 2, 0), _paintToDestination);
    canvas.restore();

    // draw plane
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(rotate);
    canvas.translate(-size.width / 2, -size.height / 2);
    canvas.drawLine(Offset(size.width / 2, size.height / 2 + 16), Offset(size.width / 2, 0), _paintCenter);
    canvas.drawLine(Offset(size.width / 2 - 16, size.height / 2), Offset(size.width / 2 + 16, size.height / 2), _paintCenter);
    canvas.restore();
  }

  @override
  bool shouldRepaint(Plane oldDelegate) => true;
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
