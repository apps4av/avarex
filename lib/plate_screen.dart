import 'dart:math';
import 'dart:ui' as ui;

import 'package:avaremp/custom_widgets.dart';
import 'package:avaremp/destination.dart';
import 'package:avaremp/path_utils.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/user_database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'constants.dart';
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
  AirportDestination? _airportDestination;
  String _currentPlateAirport = Storage().settings.getCurrentPlateAirport();

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

    _plates = await PathUtils.getPlateNames(Storage().dataDir, _currentPlateAirport);
    _csup = await MainDatabaseHelper.db.findCsup(_currentPlateAirport);

    // combine plates and csup
    for(String c in _csup) {
      _plates.add("CSUP:$c");
    }
    _plates = _plates.toSet().toList();
    _plates.sort();

    _airportDestination = await MainDatabaseHelper.db
        .findAirport(Storage().settings.getCurrentPlateAirport());

  }

  Future<PlatesFuture> getAll() async {
    await _getAll();
    return this;
  }

  AirportDestination? get airportDestination => _airportDestination;
  List<String> get airports => _airports;
  List<String> get plates => _plates;
  String get currentPlateAirport => _currentPlateAirport;
}

class PlateScreenState extends State<PlateScreen> {

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

  // on change of airport, reload first item of the new airport
  Future _loadPlate() async {
    // load plate in background
    await Storage().loadPlate();
    Storage().lastPlateAirport = Storage().settings.getCurrentPlateAirport();
  }


  Widget _makeContent(PlatesFuture? future) {

    double height = Scaffold.of(context).appBarMaxHeight ?? 0;
    ValueNotifier notifier = ValueNotifier(0);

    if(future == null) {
      return Container(); // hopeless of still not ready
    }

    List<String> plates = future.plates;
    List<String> airports = future.airports;
    Storage().settings.setCurrentPlateAirport(future.currentPlateAirport);
    AirportDestination? destination = future.airportDestination;

    double lon = destination == null ? 0 : destination.lon;
    double lat =  destination == null ? 0: destination.lat;

    if(airports.isEmpty) {
      return Container(); // hopeless, still not ready
    }

    if(plates.isEmpty) {
      // only airports
      return Scaffold(body: Stack(children: [
          CustomWidgets.dropDownButton(
            context,
            Storage().settings.getCurrentPlateAirport(),
            airports,
            Alignment.bottomRight,
            Constants.bottomPaddingSize(context),
                (value) {
              setState(() {
                Storage().settings.setCurrentPlateAirport(value ?? airports[0]);
              });
            },
          ),
        ]
      ));
    }

    if((Storage().lastPlateAirport !=  Storage().settings.getCurrentPlateAirport())) {
      Storage().currentPlate = plates[0]; // new airport, change to plate 0
    }

    _loadPlate();

    // plate load notification, repaint
    Storage().plateChange.addListener(() {
      notifier.notifyListeners();
    });

    Storage().gpsChange.addListener(() {
      // gps change, repaint plate
      notifier.notifyListeners();
    });

    return Scaffold(body: Stack(children: [
        InteractiveViewer(
            transformationController: Storage().plateTransformationController,
            minScale: 1,
            maxScale: 8,
            child:
              SizedBox(
              height: Constants.screenHeight(context),
              width: Constants.screenWidth(context),
              child: CustomPaint(painter: _PlatePainter(height: height, lon: lon, lat: lat, repaint: notifier)),
            )
        ),
        CustomWidgets.dropDownButton(
          context,
          Storage().settings.getCurrentPlateAirport(),
          airports,
          Alignment.bottomRight,
          Constants.bottomPaddingSize(context),
          (value) {
            setState(() {
              Storage().settings.setCurrentPlateAirport(value ?? airports[0]);
            });
          },
        ),
        CustomWidgets.dropDownButton(
          context,
          plates.contains(Storage().currentPlate) ? Storage().currentPlate : plates[0],
          plates,
          Alignment.bottomLeft,
          Constants.bottomPaddingSize(context),
          (value) {
            setState(() {
              Storage().currentPlate = value ?? plates[0];
            });
          },
        ),
        CustomWidgets.centerButton(context,
            Constants.bottomPaddingSize(context),
            () => setState(() {
              Storage().resetPlate();
            })
        )
      ]
    ));
  }
}

class _PlatePainter extends CustomPainter {

  double _height = 0;
  List<double>? _matrix;
  double _airportLon = 0;
  double _airportLat = 0;
  ui.Image? _image;

  // Define a paint object
  final _paint = Paint();
  // Define a paint object for circle
  final _paintCenter = Paint()
    ..style = PaintingStyle.fill
    ..strokeWidth = 10
    ..color = const Color.fromARGB(100, 0, 255, 0);

  final _paintLine = Paint()
    ..strokeWidth = 10
    ..color = const Color.fromARGB(127, 255, 0, 0);

  _PlatePainter({
    required ValueNotifier repaint,
    required double height,
    required double lon,
    required double lat}) : super(repaint: repaint) {
    _height = height;
    _airportLat = lat;
    _airportLon = lon;
  }

  @override
  void paint(Canvas canvas, Size size) {

    _image = Storage().imagePlate;
    _matrix = Storage().matrixPlate;

    if(_image != null) {

      // make in center
      double h = size.height - _height;
      double ih = _image!.height.toDouble();
      double w = size.width;
      double iw = _image!.width.toDouble();
      double fac = h / ih;
      double fac2 = w / iw;
      if (fac > fac2) {
        fac = fac2;
      }

      canvas.save();
      canvas.translate(0, _height);
      canvas.scale(fac);
      canvas.drawImage(_image!, const Offset(0, 0), _paint);

      if(null != _matrix) {
        double heading = Storage().position.heading;
        double lon = Storage().position.longitude;
        double lat = Storage().position.latitude;

        double dx = _matrix![0];
        double dy = _matrix![1];
        double lonTopLeft = _matrix![2];
        double latTopLeft = _matrix![3];
        double pixX = (lon - lonTopLeft) * dx;
        double pixY = (lat - latTopLeft) * dy;

        double pixAirportX = (_airportLon - lonTopLeft) * dx;
        double pixAirportY = (_airportLat - latTopLeft) * dy;
        Offset offsetCircle = Offset(pixAirportX, pixAirportY);

        // draw circle at center of airport of 1/16th of screen size
        canvas.drawCircle(offsetCircle, (size.height + size.width) / 32, _paintCenter);
        //draw airplane
        canvas.translate(pixX, pixY);
        canvas.rotate(heading * pi / 180);
        // draw all based on screen width, height
        canvas.drawLine(Offset(0, 2 * (size.height + size.width) / 64), Offset(0, -(size.height + size.width) / 2), _paintLine);
        canvas.drawLine(Offset(2 * (size.height + size.width) / 64, 0), Offset(-2 * (size.height + size.width) / 64, 0), _paintLine);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PlatePainter oldDelegate) => true;
}

