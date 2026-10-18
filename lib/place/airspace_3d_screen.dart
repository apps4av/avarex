import 'package:avaremp/place/airspace_3d_view.dart';
import 'package:flutter/material.dart';

/// Menu entry for the shared 3D airspace view, following the aircraft.
class Airspace3DScreen extends StatelessWidget {
  const Airspace3DScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('3D')),
      body: Airspace3DView(
        followAircraft: true,
        showTerrain: true,
        showTraffic: true,
      ),
    );
  }
}
