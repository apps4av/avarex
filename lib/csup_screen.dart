import 'dart:ui' as ui;

import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';

import 'main_database_helper.dart';

// implements a drawing screen with a center reset button.

class CSupScreen extends StatefulWidget {
  const CSupScreen({super.key});
  @override
  State<StatefulWidget> createState() => CSupScreenState();
}

class CSupScreenState extends State<CSupScreen> {

  final _counter = ValueNotifier<int>(0);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: MainDatabaseHelper.db.findCsup(Storage().currentCSupAirport),
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

    final double bottom = MediaQuery.of(context).padding.bottom;
    final double? top = Scaffold.of(context).appBarMaxHeight;
    Storage().setScreenDims(top, bottom);

    if(null == items) {
      return Container();
    }

    // on change of airport, reload first item of the new airport
    if(Storage().lastCSupAirport != Storage().currentCSupAirport) {
      Storage().currentCSup = items[0];
    }

    Future re() async {
      await Storage().loadCSup();
      Storage().lastCSupAirport = Storage().currentCSupAirport;
    }
    re().whenComplete(() => _counter.notifyListeners()); // redraw when loaded

    return Scaffold(
      body: Stack(
          children: [
            InteractiveViewer(
                transformationController: Storage().csupTransformationController,
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
                    alignment: Alignment.bottomRight,
                    child: DropdownButton<String>(
                      iconEnabledColor: Colors.blueAccent,
                      underline: Container(),
                      padding: EdgeInsets.fromLTRB(0, 0, 0, Storage().screenBottom),
                      value: Storage().currentCSupAirport,
                      items: ["BVY", "MA6", "OWD", "SBA"].map((String item) {
                        return DropdownMenuItem<String>(
                          value: item,
                          child: Text(item, style: const TextStyle(color: Colors.blueAccent),),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          Storage().currentCSupAirport = val ?? items[0];
                        });
                      },
                    )
                )
            ),
            Positioned(
                child: Align(
                    alignment: Alignment.bottomLeft,
                    child: items[0].isEmpty ? Container() : DropdownButton<String>( // airport selection
                      iconEnabledColor: Colors.blueAccent,
                      underline: Container(),
                      padding: EdgeInsets.fromLTRB(0, 0, 0, Storage().screenBottom),
                      value: Storage().currentCSup,
                      items: items.map((String item) {
                        return DropdownMenuItem<String>(
                          value: item,
                          child: Text(item, style: const TextStyle(color: Colors.blueAccent),),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          Storage().currentCSup = val ?? items[0];
                        });
                      },
                    )
                )
            ),
            Positioned(
              child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(0, 0, 0, Storage().screenBottom + 40),
                    child: IconButton(onPressed: () {
                      setState(() {
                        Storage().csupTransformationController.value.setEntry(0, 0, 1);
                        Storage().csupTransformationController.value.setEntry(1, 1, 1);
                        Storage().csupTransformationController.value.setEntry(2, 2, 1);
                        Storage().csupTransformationController.value.setEntry(0, 3, 0);
                        Storage().csupTransformationController.value.setEntry(1, 3, 0);
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

    ui.Image? image = Storage().imageCSup;

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
      canvas.translate(0, Storage().screenTop);
      canvas.scale(fac);
      canvas.drawImage(image, offset, _paint);
      canvas.restore();
    }

  }

  @override
  bool shouldRepaint(_MapPainter oldDelegate) => true;
}


