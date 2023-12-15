import 'package:avaremp/custom_widgets.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'chart.dart';


class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<StatefulWidget> createState() => MapScreenState();
}


class MapScreenState extends State<MapScreen> {

  final List<String> _charts = [ChartCategory.sectional, ChartCategory.tac, ChartCategory.ifrl];
  String _type = Storage().settings.getChartType();
  final MapController _mapController = MapController();
  double _maxZoom = ChartCategory.chartTypeToZoom(Storage().settings.getChartType());

  void _handlePress(TapPosition tapPosition, LatLng point) {
  }

  @override
  Widget build(BuildContext context) {
    Storage().setScreenDims(context);

    String index = ChartCategory.chartTypeToIndex(_type);
    _maxZoom = ChartCategory.chartTypeToZoom(_type);

    MapOptions opts = MapOptions(
      initialCenter: LatLng(42, -71),
      initialZoom: _maxZoom,
      maxZoom: _maxZoom,
      minZoom: 0,
      backgroundColor: Colors.black,
      onLongPress: _handlePress,
    );

    return Scaffold(
        body:
        Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: opts,
                children: [
                  TileLayer(
                    tms: true,
                    tileProvider: FileTileProvider(),
                    //urlTemplate: 'c:\\temp\\tiles\\$index\\{z}\\{x}\\{y}.webp',
                    urlTemplate: '/data/user/0/com.apps4av.avaremp/app_flutter/tiles/$index/{z}/{x}/{y}.webp',
                    userAgentPackageName: 'com.apps4av.avaremp',
                  ),
                  const MarkerLayer(
                      markers: [
                        Marker(
                            point: LatLng(42, -71),
                            width: 80,
                            height: 80,
                            child: FlutterLogo()
                        ),
                      ]),
                ],
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
                    _mapController.move(LatLng(42, -69.7), _maxZoom);
              })
          )
        ])
    );
  }
// implements a drawing screen with a center reset button.

}


