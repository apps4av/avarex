import 'package:avaremp/custom_widgets.dart';
import 'package:avaremp/main_database_helper.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'airport.dart';
import 'chart.dart';
import 'constants.dart';
import 'destination.dart';
import 'gps.dart';
import 'longpress_widget.dart';


class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<StatefulWidget> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {

  final List<String> _charts = [ChartCategory.sectional, ChartCategory.tac, ChartCategory.ifrl];
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


  void _handlePress(TapPosition tapPosition, LatLng point) async {
    List<Destination> items = await MainDatabaseHelper.db.findNear(point);
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
                  TileLayer(
                    tms: true,
                    tileProvider: FileTileProvider(),
                    //urlTemplate: 'c:\\temp\\tiles\\$index\\{z}\\{x}\\{y}.webp' for testing on PC,
                    urlTemplate: "${Storage().dataDir}/tiles/$index/{z}/{x}/{y}.webp",
                    userAgentPackageName: 'com.apps4av.avaremp',
                  ),
                  ValueListenableBuilder<Position>(
                    valueListenable: Storage().gpsChange,
                    builder: (context, value, _) {
                      return MarkerLayer(
                        markers: [
                          Marker( // our position
                            width: Constants.screenHeight(context) / 20,
                            height: Constants.screenHeight(context) / 20,
                            point: LatLng(value.latitude, value.longitude),
                            child: Transform.rotate(
                              angle: value.heading * pi / 180,
                              child: Image.asset("assets/images/plane.png"),
                              ),
                            ),
                        ],
                      );
                    },
                  ),                ],
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

          CustomWidgets.centerButton(context,
              Constants.bottomPaddingSize(context),
                  () => setState(() {
                    // get to current position
                    Position p = Storage().position;
                    LatLng l = Gps.positionToLatLong(p);
                    _controller.moveAndRotate(l, _maxZoom, 0);
              })
          )
        ])
    );
  }
// implements a drawing screen with a center reset button.

}


