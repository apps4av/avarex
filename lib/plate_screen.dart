import 'dart:collection';
import 'dart:ui' as ui;

import 'package:avaremp/custom_widgets.dart';
import 'package:avaremp/path_utils.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/user_database_helper.dart';
import 'package:flutter/material.dart';

import 'main_database_helper.dart';

// implements a drawing screen with a center reset button.

class PlateScreen extends StatefulWidget {
  const PlateScreen({super.key});
  @override
  State<StatefulWidget> createState() => PlateScreenState();
}

// get plates and airports
class PlatesFuture {
  List<String>? _plates;
  List<String>? _airports;
  List<String>? _csup;

  Future<void> _getAll() async {

    _airports = await UserDatabaseHelper.db.getRecent();

    if(Storage().currentPlateAirport.isEmpty) {
      if(null != _airports && _airports!.isNotEmpty) {
        // start condition when no airport is known.
        Storage().currentPlateAirport = _airports![0];
      }
    }

    _plates = await PathUtils.getPlateNames(Storage().currentPlateAirport);
    _csup = await MainDatabaseHelper.db.findCsup(Storage().currentPlateAirport);

    // combine plates and csup
    if(null != _plates && null != _csup) {
      for(String c in _csup!) {
        _plates!.add("CSUP:$c");
      }
      _plates!.sort();
    }
    else if(null == _plates && null != _csup) {
      _plates = _csup;
      _plates!.sort();
    }
  }

  Future<PlatesFuture> getAll() async {
    await _getAll();
    return this;
  }

  List<String>? get airports => _airports;
  List<String>? get plates => _plates;
}

class PlateScreenState extends State<PlateScreen> {

  final _counter = ValueNotifier<int>(0);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: PlatesFuture().getAll(),
        builder: (context, snapshot) {
          if(snapshot.hasData) {
            return _makeContent(snapshot.data);
          }
          else {
            return _makeContent(null);
          }
        }
    );
  }

  Widget _makeContent(PlatesFuture? future) {

    final double bottom = MediaQuery.of(context).padding.bottom;
    final double? top = Scaffold.of(context).appBarMaxHeight;
    Storage().setScreenDims(top, bottom);

    if(future == null) {
      return Container(); // hopeless of still not ready
    }

    List<String>? plates = future.plates;
    List<String>? airports = future.airports;

    if(null == airports || airports.isEmpty) {
      return Container(); // hopeless, still not ready
    }

    if(null == plates || plates.isEmpty) {
      // only airports
      return Scaffold(
          body: Stack(
              children: [
                CustomWidgets.dropDownButton(
                  context,
                  Storage().currentPlateAirport,
                  airports,
                  Alignment.bottomRight,
                  Storage().screenBottom,
                      (value) {
                    setState(() {
                      Storage().currentPlateAirport = value ?? airports[0];
                    });
                  },
                ),
              ]
          )
      );
    }

    if((Storage().lastPlateAirport != Storage().currentPlateAirport)) {
      Storage().currentPlate = plates[0]; // new airport, change to plate 0
    }

    // on change of airport, reload first item of the new airport
    Future re() async {
      // load plate in background
      await Storage().loadPlate();
      Storage().lastPlateAirport = Storage().currentPlateAirport;
    }
    re().whenComplete(() => _counter.notifyListeners()); // redraw when loaded

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
                  child: CustomPaint(painter: _PlatePainter(repaint: _counter))
                )
            ),
            CustomWidgets.dropDownButton(
              context,
              Storage().currentPlateAirport,
              airports,
              Alignment.bottomRight,
              Storage().screenBottom,
                  (value) {
                setState(() {
                  Storage().currentPlateAirport = value ?? airports[0];
                });
              },
            ),
            CustomWidgets.dropDownButton(
              context,
              plates.contains(Storage().currentPlate) ? Storage().currentPlate : plates[0],
              plates,
              Alignment.bottomLeft,
              Storage().screenBottom,
              (value) {
                setState(() {
                  Storage().currentPlate = value ?? plates[0];
                });
              },
            ),
            CustomWidgets.centerButton(context,
                Storage().screenBottom,
                () => setState(() {
                  Storage().resetPlate();
                })
            )
          ]
        ),
      );
    }
}

class _PlatePainter extends CustomPainter {

  Offset offset =  const Offset(0, 0);

  _PlatePainter({required Listenable repaint}) : super(repaint: repaint);

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
      canvas.translate(0, Storage().screenTop);
      canvas.scale(fac);
      canvas.drawImage(image, offset, _paint);
      canvas.restore();
    }

  }

  @override
  bool shouldRepaint(_PlatePainter oldDelegate) => true;
}

