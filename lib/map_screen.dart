import 'package:avaremp/custom_widgets.dart';
import 'package:avaremp/main_database_helper.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'chart.dart';
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

  Future<bool> showDestination(BuildContext context, FindDestination destination) async {
    bool? exitResult = await showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return LongPressWidget(destination: destination);
      },
    );
    return exitResult ?? false;
  }


  void _handlePress(TapPosition tapPosition, LatLng point) async {
    List<FindDestination> items = await MainDatabaseHelper.db.findNear(point);
    if(items.isEmpty) {
      return;
    }
    setState(() {
      showDestination(context, items[0]);
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
      backgroundColor: Colors.black,
      onLongPress: _handlePress,
    );

    // for track up
    Storage().gpsChange.addListener(() {
      // in track up mode rotate chart
      Storage().settings.getNorthUp() ? {} : _controller.rotate(Storage().position.heading);
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
                  ValueListenableBuilder<int>(
                    valueListenable: Storage().gpsChange,
                    builder: (context, value, _) {
                      return MarkerLayer(
                        markers: [
                          Marker( // our position
                            width: MediaQuery.of(context).size.height / 20,
                            height: MediaQuery.of(context).size.height / 20,
                            point: LatLng(Storage().position.latitude, Storage().position.longitude),
                            child: Transform.rotate(
                              angle: Storage().settings.getNorthUp() ? Storage().position.heading * pi / 180 : -Storage().position.heading * pi / 180,
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
                  MediaQuery.of(context).padding.bottom,
              (value) {
                setState(() {
                  Storage().settings.setChartType(value ?? _charts[0]);
                  _type = Storage().settings.getChartType();
                });
              }
          ),

          CustomWidgets.centerButton(context,
              MediaQuery.of(context).padding.bottom,
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


