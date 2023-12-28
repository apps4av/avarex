import 'package:avaremp/custom_widgets.dart';
import 'package:avaremp/download_list.dart';
import 'package:avaremp/main_database_helper.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'coordinate.dart';
import 'airport.dart';
import 'chart.dart';
import 'constants.dart';
import 'destination.dart';
import 'longpress_widget.dart';
import 'package:avaremp/projection.dart' as proj;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<StatefulWidget> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {

  final List<String> _charts = DownloadListState.getCategories();

  String _type = Storage().settings.getChartType();
  double _maxZoom = ChartCategory.chartTypeToZoom(Storage().settings.getChartType());
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

  void _handlePointerDown(PointerDownEvent event, LatLng point) {

  }


  void _handlePress(TapPosition tapPosition, LatLng point) async {
    List<Destination> items = await MainDatabaseHelper.db.findNear(Coordinate(Longitude(point.longitude), Latitude(point.latitude)));
    if(items.isEmpty) {
      return;
    }
    setState(() {
      if(Airport.isAirport(items[0].type)) {
        showDestination(context, items[0]);
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

    // start from known location
    MapOptions opts = MapOptions(
      initialCenter: LatLng(Storage().settings.getCenterLatitude(), Storage().settings.getCenterLongitude()),
      initialZoom: Storage().settings.getZoom(),
      initialRotation: Storage().settings.getRotation(),
      maxZoom: _maxZoom,
      minZoom: 0,
      backgroundColor: Constants.mapBackgroundColor,
      onLongPress: _handlePress,
      onPointerDown: _handlePointerDown,
    );

    // for track up
    Storage().gpsChange.addListener(() {
      // in track up mode rotate chart
      Storage().settings.getNorthUp() ? {} : _controller.rotate(-Storage().position.heading);
    });

    return Scaffold(
        body: Stack(
            children: [
              FlutterMap(
                mapController: _controller,
                options: opts,
                children: [
                  // map layer
                  TileLayer(
                    tms: true,
                    tileProvider: FileTileProvider(),
                    //urlTemplate: 'c:\\temp\\tiles\\$index\\{z}\\{x}\\{y}.webp' for testing on PC,
                    urlTemplate: "${Storage().dataDir}/tiles/$index/{z}/{x}/{y}.webp",
                    userAgentPackageName: 'com.apps4av.avaremp',
                  ),
                  // route layer
                  ValueListenableBuilder<Destination?>(
                    valueListenable: Storage().destinationChange,
                    builder: (context, value, _) {
                      return PolylineLayer(
                        polylines: [
                          // route
                          Polyline(
                            borderStrokeWidth: 2,
                            borderColor: Colors.black,
                            strokeWidth: 5,
                            strokeCap: StrokeCap.round,
                            points: [LatLng(Storage().position.latitude, Storage().position.longitude), LatLng(value == null? Storage().position.latitude : value.coordinate.latitude.value, value == null? Storage().position.longitude : value.coordinate.longitude.value),],
                            color: Colors.purpleAccent,
                          ),
                        ],
                      );
                    },
                  ),
                  // aircraft layer
                  ValueListenableBuilder<Position>(
                    valueListenable: Storage().gpsChange,
                    builder: (context, value, _) {
                      return MarkerLayer(
                        markers: [
                          Marker( // compass
                            width: (Constants.screenWidth(context) + Constants.screenHeight(context)) / 10,
                            height: (Constants.screenWidth(context) + Constants.screenHeight(context)) / 10,
                            point: LatLng(value.latitude, value.longitude),
                            child: Image.asset("assets/images/compass.png"),
                          ),
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
                ],
              ),
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
                        _controller.moveAndRotate(l, _maxZoom, 0);
                      },
                      child: const Text("Center"),
                    ))
            ),
          )
        ])
    );
  }
// implements a drawing screen with a center reset button.

}



class Plane extends CustomPainter {

  final Position _position;

  Plane(this._position);

  final _paintCenter = Paint()
    ..style = PaintingStyle.fill
    ..strokeWidth = 4
    ..strokeCap = StrokeCap.square
    ..color = const Color.fromARGB(255, 255, 0, 0);

  final _paintToDestination = Paint()
    ..style = PaintingStyle.fill
    ..strokeWidth = 4
    ..strokeCap = StrokeCap.square
    ..color = const Color.fromARGB(255, 0, 0, 255);

  @override
  void paint(Canvas canvas, Size size) {

    double rotate = _position == null ? 0 : _position.heading;
    Destination? destination = Storage().currentDestination;
    // path to destination always points to dest
    double rotate2 = (null == destination)? 0: proj.Projection.getStaticBearing(_position.longitude, _position.latitude,
          destination.coordinate.longitude.value, destination.coordinate.latitude.value);
    // draw path to dest
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(rotate2 * pi / 180);
    canvas.translate(-size.width / 2, -size.height / 2);
    canvas.drawLine(Offset(size.width / 2, size.height / 2 + 16), Offset(size.width / 2, 0), _paintToDestination);
    canvas.restore();

    // draw plane
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(rotate * pi / 180);
    canvas.translate(-size.width / 2, -size.height / 2);
    canvas.drawLine(Offset(size.width / 2, size.height / 2 + 16), Offset(size.width / 2, 0), _paintCenter);
    canvas.drawLine(Offset(size.width / 2 - 16, size.height / 2), Offset(size.width / 2 + 16, size.height / 2), _paintCenter);
    canvas.restore();
  }


  // Since this Sky painter has no fields, it always paints
  // the same thing and semantics information is the same.
  // Therefore we return false here. If we had fields (set
  // from the constructor) then we would return true if any
  // of them differed from the same fields on the oldDelegate.
  @override
  bool shouldRepaint(Plane oldDelegate) => false;
}