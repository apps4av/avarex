import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:avaremp/path_utils.dart';
import 'package:flutter/material.dart';

// implements a drawing screen with a center reset button.

class PlateScreen extends StatefulWidget {
  const PlateScreen({super.key});
  @override
  State<StatefulWidget> createState() => PlateScreenState();
}

class PlateScreenState extends State<PlateScreen> {

  String currentPlate = "AIRPORT-DIAGRAM";
  String currentAirport = "BVY";
  MapPainter currentPainter = MapPainter();
  late Future<ui.Image> plateImage;

  String getPlateTitle() {
    return "$currentAirport $currentPlate";
  }

  @override
  Widget build(BuildContext context) {
    return
      Scaffold(
        appBar: AppBar(
          title: Text(currentPlate),
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
                    currentPlate = "AIRPORT-DIAGRAM";
                    currentPainter.setImage(currentAirport, currentPlate);
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('RNAV-GPS-RWY-09'),
                onTap: () {
                  setState(() {
                    currentPlate = "RNAV-GPS-RWY-09";
                    currentPainter.setImage(currentAirport, currentPlate);
                  });
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
        body : Stack(
          children: [
            CustomPaint(painter: currentPainter),
            Positioned(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: IconButton(onPressed: () {  }, icon: const Icon(Icons.gps_fixed)),)),
              ),
          ]
        ),
      );
  }
}

class MapPainter extends CustomPainter {

  ui.Image? image;

  Future<ui.Image> loadPlateImage(Uint8List bytes) async {
    final Completer<ui.Image> completer = Completer();
    ui.decodeImageFromList(bytes, (ui.Image img) {
      return completer.complete(img);
    });
    return completer.future;
  }

  Future<ui.Image> loadPlate(String airport, String plate) async {
    String path = await PathUtils.getPlateFilePath(airport, plate);
    File file = File(path);
    Uint8List bytes = await file.readAsBytes();
    return await loadPlateImage(bytes);
  }

  void setImage(String airport, String plate) async {
    if(image != null) {
      image!.dispose();
    }
    image = await loadPlate(airport, plate);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Define a paint object
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..color = Colors.white;

    if(image != null) {
      canvas.drawImage(image!, const Offset(0, 0), paint);
    }
  }

  @override
  bool shouldRepaint(MapPainter oldDelegate) => false;
}

