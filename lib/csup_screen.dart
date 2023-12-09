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
          return _makeContent(snapshot.data);
        }
    );
  }


  Widget _makeContent(List<String>? items) {

    if(null == items) {
      return Container();
    }

    // on change of airport, reload first item of the new airport
    if(Storage().lastCSupAirport != Storage().currentCSupAirport) {
      Future re() async {
        Storage().currentCSup = items[0].toString();
        await Storage().loadCSup();
        _counter.notifyListeners();
        Storage().lastCSupAirport = Storage().currentCSupAirport;
      }
      re();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(Storage().currentCSup),
        actions: [
          DropdownButton<String>( // airport selection
            value: Storage().currentCSupAirport,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            items: ["BVY", "MA6", "OWD"].map((String item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(item),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                Storage().currentCSupAirport = val ?? "BVY";
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
                  Storage().currentCSup = items[index].toString();
                  Storage().loadCSup();
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
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
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
      canvas.scale(fac);
      canvas.drawImage(image, offset, _paint);
      canvas.restore();
    }

  }

  @override
  bool shouldRepaint(_MapPainter oldDelegate) => true;
}


