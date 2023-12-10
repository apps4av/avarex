import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';


class DrawCanvas extends StatefulWidget {
  const DrawCanvas({super.key});
  @override
  State<StatefulWidget> createState() => DrawCanvasState();
}

class DrawCanvasState extends State<DrawCanvas> {
  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: const MapOptions(
        initialCenter: LatLng(42, -71),
        initialZoom: 10,
        maxZoom: 11,
        minZoom: 0,
        backgroundColor: Colors.black
      ),
      children: [
        TileLayer(
          tms: true,
          tileSize:256,
          tileProvider: FileTileProvider(),
          urlTemplate: '/data/user/0/com.apps4av.avaremp/app_flutter/{z}/{x}/{y}.webp',
          userAgentPackageName: 'com.apps4av.avaremp',
        ),
      ],
    );
  }
// implements a drawing screen with a center reset button.
}


