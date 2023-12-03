import 'dart:async';
import 'dart:ui' as ui;

import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';

// implements a drawing screen with a center reset button.

class PlateScreen extends StatefulWidget {
  const PlateScreen({super.key});
  @override
  State<StatefulWidget> createState() => PlateScreenState();
}

class PlateScreenState extends State<PlateScreen> {


  String getPlateTitle() {
    String airport = Storage().currentPlateAirport;
    String plate = Storage().currentPlate;
    return "$airport $plate";
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleUpdate: (details) {print("scale$details.scale");},
      child: Scaffold(
        appBar: AppBar(
          title: Text(Storage().currentPlate),
        ),
        drawer: Drawer(
          // Add a ListView to the drawer. This ensures the user can scroll
          // through the options in the drawer if there isn't enough vertical
          // space to fit everything.
          child: ListView(
            // Important: Remove any padding from the ListView.
            padding: EdgeInsets.zero,
            children: [
              ListTile(
                title: const Text('AIRPORT-DIAGRAM'),
                onTap: () {
                  setState(() {
                    Storage().currentPlate = "AIRPORT-DIAGRAM";
                    Storage().loadPlate();
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('RNAV-GPS-RWY-09'),
                onTap: () {
                  setState(() {
                    Storage().currentPlate = "RNAV-GPS-RWY-09";
                    Storage().loadPlate();
                  });
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
        body : Stack(
          children: [CustomPaint(painter: _MapPainter()),

            Positioned(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: IconButton(onPressed: () {  }, icon: const Icon(Icons.gps_fixed)),)),
              ),
          ]
        ),
      ));
  }
}

class _MapPainter extends CustomPainter {

  @override
  void paint(Canvas canvas, Size size) {
    // Define a paint object
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..color = Colors.white;

    ui.Image? image = Storage().imagePlate;
    if(image != null) {
      canvas.drawImage(image!, const Offset(0, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_MapPainter oldDelegate) => false;
}

