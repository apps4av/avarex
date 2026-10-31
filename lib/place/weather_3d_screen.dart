import 'package:avaremp/place/airspace_3d_view.dart';
import 'package:flutter/material.dart';

/// Menu entry for the 3D view in weather mode, following the aircraft.
class Weather3DScreen extends StatelessWidget {
  const Weather3DScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('3D Weather')),
      body: const Airspace3DView(
        weather: true,
        followAircraft: true,
        showTerrain: true,
      ),
    );
  }
}
