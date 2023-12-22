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
  List<String> _plates = [];
  List<String> _airports = [];
  List<String> _csup = [];
  String _currentPlateAirport = Storage().currentPlateAirport;

  Future<void> _getAll() async {

    // get location ID only
    _airports = (await UserDatabaseHelper.db.getRecentAirports()).map((e) => e.locationID).toList();

    if(_currentPlateAirport.isEmpty) {
        if(_airports.isNotEmpty) {
          // start condition when no airport is known.
          _currentPlateAirport = _airports[0];
        }
    }
    else {
      // make current airport front
      _airports.insert(0, _currentPlateAirport);
    }
    _airports = _airports.toSet().toList();

    _plates = await PathUtils.getPlateNames(_currentPlateAirport);
    _csup = await MainDatabaseHelper.db.findCsup(_currentPlateAirport);

    // combine plates and csup
    for(String c in _csup) {
      _plates.add("CSUP:$c");
    }
    _plates = _plates.toSet().toList();
    _plates.sort();
  }

  Future<PlatesFuture> getAll() async {
    await _getAll();
    return this;
  }

  List<String> get airports => _airports;
  List<String> get plates => _plates;
  String get currentPlateAirport => _currentPlateAirport;
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

    double ? _height = Scaffold.of(context).appBarMaxHeight ?? 0;

    if(future == null) {
      return Container(); // hopeless of still not ready
    }

    List<String> plates = future.plates;
    List<String> airports = future.airports;
    Storage().currentPlateAirport = future.currentPlateAirport;

    if(airports.isEmpty) {
      return Container(); // hopeless, still not ready
    }

    if(plates.isEmpty) {
      // only airports
      return Stack(children: [
          CustomWidgets.dropDownButton(
            context,
            Storage().currentPlateAirport,
            airports,
            Alignment.bottomRight,
            MediaQuery.of(context).padding.bottom,
                (value) {
              setState(() {
                Storage().currentPlateAirport = value ?? airports[0];
              });
            },
          ),
        ]
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

    return Stack(children: [
        InteractiveViewer(
            transformationController: Storage().plateTransformationController,
            minScale: 1,
            maxScale: 8,
            child:
              SizedBox(
              height: MediaQuery.of(context).size.height,
              width: MediaQuery.of(context).size.width,
              child: CustomPaint(painter: _PlatePainter(repaint: _counter, height: _height))
            )
        ),
        CustomWidgets.dropDownButton(
          context,
          Storage().currentPlateAirport,
          airports,
          Alignment.bottomRight,
          MediaQuery.of(context).padding.bottom,
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
          MediaQuery.of(context).padding.bottom,
          (value) {
            setState(() {
              Storage().currentPlate = value ?? plates[0];
            });
          },
        ),
        CustomWidgets.centerButton(context,
            MediaQuery.of(context).padding.bottom,
            () => setState(() {
              Storage().resetPlate();
            })
        )
      ]
    );
  }
}

class _PlatePainter extends CustomPainter {

  Offset offset =  const Offset(0, 0);

  _PlatePainter({required Listenable repaint, required double? height}) : super(repaint: repaint) {
    _height = height;
  }

  double? _height;

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
      canvas.translate(0, _height ?? 0);
      canvas.scale(fac);
      canvas.drawImage(image, offset, _paint);
      canvas.restore();
    }

  }

  @override
  bool shouldRepaint(_PlatePainter oldDelegate) => true;
}

