import 'dart:ui' as ui;

import 'package:avaremp/path_utils.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';

// implements a drawing screen with a center reset button.

class PlateScreen extends StatefulWidget {
  const PlateScreen({super.key});
  @override
  State<StatefulWidget> createState() => PlateScreenState();
}

class PlateScreenState extends State<PlateScreen> {

  final _counter = ValueNotifier<int>(0);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: PathUtils.getPlateNames(Storage().currentPlateAirport),
        builder: (context, snapshot) {
          return _makeContent(snapshot.data);
        }
    );
  }

  Widget _makeContent(List<String>? items) {

    if(null == items) {
      return Container();
    }

    // on change of airport, reload first item of the new airport
    if(Storage().lastPlateAirport != Storage().currentPlateAirport) {
      Future re() async {
        Storage().currentPlate = items[0].toString();
        await Storage().loadPlate();
        _counter.notifyListeners();
        Storage().lastPlateAirport = Storage().currentPlateAirport;
      }
      re();
    }

    return Scaffold(
       appBar: AppBar(
         title: Text(Storage().currentPlate),
         actions: [
           DropdownButton<String>( // airport selection
             value: Storage().currentPlateAirport,
             padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
             items: ["BVY", "BOS"].map((String item) {
               return DropdownMenuItem<String>(
                 value: item,
                 child: Text(item),
               );
             }).toList(),
             onChanged: (val) {
               setState(() {
                 Storage().currentPlateAirport = val ?? "BVY";
               });
             },
           ),
         ],
       ),
        drawer: Drawer(
          // Add a ListView to the drawer. This ensures the user can scroll
          // through the options in the drawer if there isn't enough vertical
          // space to fit everything.
          child: ListView.separated(
            itemCount: items.length,
            padding: const EdgeInsets.all(30),
            // Important: Remove any padding from the ListView.
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(items[index].toString()),
                onTap: () {
                  setState(() {
                    Storage().currentPlate = items[index].toString();
                    Storage().loadPlate();
                  });
                  Navigator.pop(context);
                },
              );
            },
            separatorBuilder: (context, index) {
              return const Divider();
            },
          ),
        ),
        body: Stack(
          children: [
            InteractiveViewer(
                transformationController: Storage().plateTransformationController,
                minScale: 1,
                maxScale: 8,
                child:
                  SizedBox(
                  height: MediaQuery.of(context).size.height,
                  width: MediaQuery.of(context).size.width,
                  child: CustomPaint(painter: _MapPainter(repaint: _counter))
                )
            ),
            Positioned(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: IconButton(onPressed: () {
                    setState(() {
                      Storage().plateTransformationController.value.setEntry(0, 0, 1);
                      Storage().plateTransformationController.value.setEntry(1, 1, 1);
                      Storage().plateTransformationController.value.setEntry(2, 2, 1);
                      Storage().plateTransformationController.value.setEntry(0, 3, 0);
                      Storage().plateTransformationController.value.setEntry(1, 3, 0);
                    });
                  }, icon: const Icon(Icons.gps_fixed)),
                )
              ),
            ),
          ]
        ),
      );
    }
}

class _MapPainter extends CustomPainter {

  Offset offset =  const Offset(0, 0);

  _MapPainter({required Listenable repaint}) : super(repaint: repaint);

  // Define a paint object
  final _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4.0
    ..color = Colors.red;

  @override
  void paint(Canvas canvas, Size size) {

    ui.Image? image = Storage().imagePlate;

    if(image != null) {

      // make in center
      double h = size.height;
      double ih = image.height.toDouble();
      double w = size.width;
      double iw = image.width.toDouble();
      double fac = h / ih;
      double fac2 = w / iw;
      if(fac > fac2) {
        fac = fac2;
      }

      canvas.save();
      canvas.scale(fac);
      canvas.drawImage(image, offset, _paint);
      canvas.restore();
    }

  }

  @override
  bool shouldRepaint(_MapPainter oldDelegate) => true;
}

