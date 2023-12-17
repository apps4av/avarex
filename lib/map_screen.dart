import 'package:avaremp/custom_widgets.dart';
import 'package:avaremp/main_database_helper.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/svg.dart';
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


const String svgString = '''
<svg xmlns="http://www.w3.org/2000/svg" version="1.1" viewBox="0 0 166 202">
  <defs>
    <linearGradient id="triangleGradient">
      <stop offset="20%" stop-color="#000000" stop-opacity=".55" />
      <stop offset="85%" stop-color="#616161" stop-opacity=".01" />
    </linearGradient>
    <linearGradient id="rectangleGradient" x1="0%" x2="0%" y1="0%" y2="100%">
      <stop offset="20%" stop-color="#000000" stop-opacity=".15" />
      <stop offset="85%" stop-color="#616161" stop-opacity=".01" />
    </linearGradient>
  </defs>
  <path fill="#42A5F5" fill-opacity=".8" d="M37.7 128.9 9.8 101 100.4 10.4 156.2 10.4" />
  <path fill="#42A5F5" fill-opacity=".8" d="M156.2 94 100.4 94 79.5 114.9 107.4 142.8" />
  <path fill="#0D47A1" d="M79.5 170.7 100.4 191.6 156.2 191.6 156.2 191.6 107.4 142.8" />
  <g transform="matrix(0.7071, -0.7071, 0.7071, 0.7071, -77.667, 98.057)">
    <rect width="39.4" height="39.4" x="59.8" y="123.1" fill="#42A5F5" />
    <rect width="39.4" height="5.5" x="59.8" y="162.5" fill="url(#rectangleGradient)" />
  </g>
  <path d="M79.5 170.7 120.9 156.4 107.4 142.8" fill="url(#triangleGradient)" />
</svg>
''';

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
    Storage().setScreenDims(context);

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
                    valueListenable: Storage().gpsUpdate,
                    builder: (context, value, _) {
                      return MarkerLayer(
                        markers: [
                          Marker( // our position
                            width: Storage().screenHeight / 20,
                            height: Storage().screenHeight / 20,
                            point: LatLng(Storage().position!.latitude, Storage().position!.longitude),
                            child: Transform.rotate(
                              angle: Storage().position!.heading * pi / 180,
                              child: SvgPicture.asset(
                                "assets/images/airplane.svg",
                              ),
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
              Storage().screenBottom,
              (value) {
                setState(() {
                  Storage().settings.setChartType(value ?? _charts[0]);
                  _type = Storage().settings.getChartType();
                });
              }
          ),

          CustomWidgets.centerButton(context,
              Storage().screenBottom,
                  () => setState(() {
                    // get to current position
                    Position? p = Storage().position;
                    LatLng l = Gps.positionToLatLong(p);
                    _controller.moveAndRotate(l, _maxZoom, 0);
              })
          )
        ])
    );
  }
// implements a drawing screen with a center reset button.

}


