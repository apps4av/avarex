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
          if(snapshot.hasData) {
            return _makeContent(snapshot.data);
          }
          else {
            return _makeContent([""]);
          }
        }
    );
  }

  Widget _makeContent(List<String>? items) {

    if(null == items) {
      return Container();
    }

    if((Storage().lastPlateAirport != Storage().currentPlateAirport)) {
      Storage().currentPlate = items[0]; // new airport, change to plate 0
    }

    Future re() async {
      await Storage().loadPlate();
      Storage().lastPlateAirport = Storage().currentPlateAirport;
    }
    re().whenComplete(() => _counter.notifyListeners()); // redraw when loaded

    // on change of airport, reload first item of the new airport

    return Scaffold(
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
                    alignment: Alignment.bottomLeft,
                    child: DropdownButton<String>(
                      iconEnabledColor: Colors.blueAccent,
                      underline: Container(),
                      padding: const EdgeInsets.all(5),
                      value: Storage().currentPlateAirport,
                      items: ["BVY", "MA6", "OWD", "SBA"].map((String item) {
                        return DropdownMenuItem<String>(
                          value: item,
                          child: Text(item, style: const TextStyle(color: Colors.blueAccent),),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          Storage().currentPlateAirport = val ?? items[0];
                        });
                      },
                    )
                )
            ),
            Positioned(
                child: Align(
                    alignment: Alignment.bottomCenter,
                    child: items[0].isEmpty ? Container() : DropdownButton<String>( // airport selection
                      padding: const EdgeInsets.all(5),
                      iconEnabledColor: Colors.blueAccent,
                      underline: Container(),
                      value: Storage().currentPlate,
                      items: items.map((String item) {
                        return DropdownMenuItem<String>(
                          value: item,
                          child: Text(item, style: const TextStyle(color: Colors.blueAccent),),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          Storage().currentPlate = val ?? items[0];
                        });
                      },
                    )
                )
            ),
            Positioned(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 60),
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

