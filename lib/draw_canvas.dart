import 'package:avaremp/custom_widgets.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'chart.dart';


class DrawCanvas extends StatefulWidget {
  const DrawCanvas({super.key});
  @override
  State<StatefulWidget> createState() => DrawCanvasState();
}

void _handlePress(TapPosition tapPosition, LatLng point) {
  print(point);
}

class DrawCanvasState extends State<DrawCanvas> {

  final List<String> _charts = [ChartCategory.sectional, ChartCategory.tac, ChartCategory.ifrl];

  @override
  Widget build(BuildContext context) {

    Storage().setScreenDims(context);

    return Scaffold(
        body:
        Stack(
            children: [
          FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(42, -71),
              initialZoom: 10,
              maxZoom: 11,
              minZoom: 0,
              backgroundColor: Colors.black,
              onLongPress: _handlePress,
            ),
            children: [
              TileLayer(
                tms: true,
                tileSize:256,
                tileProvider: FileTileProvider(),
                urlTemplate: '/data/user/0/com.apps4av.avaremp/app_flutter/{z}/{x}/{y}.webp',
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
              Storage().settings.getChartType(),
              _charts,
              Alignment.bottomLeft,
              Storage().screenBottom,
              (value) {
                setState(() {
                  Storage().settings.setChartType(value ?? _charts[0]);
                });
              }
          ),

          CustomWidgets.centerButton(context,
              Storage().screenBottom,
                  () => setState(() {
              })
          )
        ])
    );
  }
// implements a drawing screen with a center reset button.

}


