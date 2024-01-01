import 'dart:math';
import 'dart:ui' as ui;

import 'package:avaremp/destination.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/path_utils.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/user_database_helper.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';

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

    _plates = await PathUtils.getPlatesAndCSupSorted(Storage().dataDir, _currentPlateAirport);

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

    double height = Constants.appbarMaxSize(context) ?? 0;
    ValueNotifier notifier = ValueNotifier(0);

    if(future == null) {
      return makePlateView([], [], height, 0, 0, notifier);
    }

    List<String> plates = future.plates;
    List<String> airports = future.airports;
    Storage().settings.setCurrentPlateAirport(future.currentPlateAirport);
    AirportDestination? destination = future.airportDestination;

    double lon = destination == null ? 0 : destination.coordinate.longitude;
    double lat =  destination == null ? 0: destination.coordinate.latitude;

    if(airports.isEmpty) {
      return makePlateView([], plates, height, lon, lat, notifier);
    }

    if(plates.isEmpty) {
      return makePlateView(airports, [], height, lon, lat, notifier);
    }

    if((Storage().lastPlateAirport !=  Storage().settings.getCurrentPlateAirport())) {
      Storage().currentPlate = plates[0]; // new airport, change to plate 0
    }

    _loadPlate();

    // plate load notification, repaint
    Storage().plateChange.addListener(() {
      notifier.value++;
    });

    Storage().gpsChange.addListener(() {
      // gps change, repaint plate
      notifier.value++;
    });

    return makePlateView(airports, plates, height, lon, lat, notifier);
  }

  Widget makePlateView(List<String> airports, List<String> plates, double height, double lon, double lat, ValueNotifier notifier) {
    return Scaffold(body: Stack(children: [
      // always return this so to reduce flicker
      InteractiveViewer(
          minScale: 1,
          maxScale: 8,
          child:
          SizedBox(
            height: Constants.screenHeight(context),
            width: Constants.screenWidth(context),
            child: CustomPaint(painter: _PlatePainter(height: height, lon: lon, lat: lat, repaint: notifier)),
          )
      ),
      airports.isEmpty ? Container() : // nothing to show here is airports is empty


      Positioned(
          child: Align(
              alignment: Alignment.bottomRight,
              child: airports[0].isEmpty ? Container() : Container(
                  padding: EdgeInsets.fromLTRB(5, 5, 5, Constants.bottomPaddingSize(context)),
                  child:DropdownButtonHideUnderline(
                      child:DropdownButton2<String>( // airport selection
                        buttonStyleData: ButtonStyleData(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Constants.dropDownButtonBackgroundColor),
                        ),
                        dropdownStyleData: DropdownStyleData(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                        ),
                        isExpanded: false,
                        value: Storage().settings.getCurrentPlateAirport(),
                        items: airports.map((String item) {
                          return DropdownMenuItem<String>(
                              value: item,
                              child: Text(item, style: TextStyle(fontSize: Constants.dropDownButtonFontSize))
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            Storage().settings.setCurrentPlateAirport(value ?? airports[0]);
                          });
                        },
                      )
                  )
              )
          )
      ),

      plates.isEmpty ? Container() : // nothing to show here if plates is empty
        Positioned(
          child: Align(
              alignment: Alignment.bottomLeft,
              child: plates[0].isEmpty ? Container() : Container(
                  padding: EdgeInsets.fromLTRB(5, 5, 5, Constants.bottomPaddingSize(context)),
                  child:DropdownButtonHideUnderline(
                      child:DropdownButton2<String>( // airport selection
                        buttonStyleData: ButtonStyleData(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Constants.dropDownButtonBackgroundColor),
                        ),
                        dropdownStyleData: DropdownStyleData(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                        ),
                        isExpanded: false,
                        value: plates.contains(Storage().currentPlate) ? Storage().currentPlate : plates[0],
                        items: plates.map((String item) {
                          return DropdownMenuItem<String>(
                              value: item,
                              child: Text(item, style: TextStyle(fontSize: Constants.dropDownButtonFontSize))
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            Storage().currentPlate = value ?? plates[0];
                          });
                        },
                      )
                  )
              )
          )
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
        double pixX = 0;
        double pixY = 0;
        Offset offsetCircle = const Offset(0, 0);
        double angle = 0;

        if(_matrix!.length == 4) {
          double dx = _matrix![0];
          double dy = _matrix![1];
          double lonTopLeft = _matrix![2];
          double latTopLeft = _matrix![3];
          pixX = (lon - lonTopLeft) * dx;
          pixY = (lat - latTopLeft) * dy;
          double pixAirportX = (_airportLon - lonTopLeft) * dx;
          double pixAirportY = (_airportLat - latTopLeft) * dy;
          offsetCircle = Offset(pixAirportX, pixAirportY);
          angle = 0;
        }
        else if(_matrix!.length == 12) {
          double wftA = _matrix![6];
          double wftB = _matrix![7];
          double wftC = _matrix![8];
          double wftD = _matrix![9];
          double wftE = _matrix![10];
          double wftF = _matrix![11];

          pixX = (wftA * lon + wftC * lat + wftE) / 2;
          pixY = (wftB * lon + wftD * lat + wftF) / 2;
          double pixAirportX = (wftA * _airportLon + wftC * _airportLat + wftE) / 2;
          double pixAirportY = (wftB * _airportLon + wftD * _airportLat + wftF) / 2;
          offsetCircle = Offset(pixAirportX, pixAirportY);

          double pixXn = (wftA * lon + wftC * (lat + 0.1) + wftE) / 2;
          double pixYn = (wftB * lon + wftD * (lat + 0.1) + wftF) / 2;
          double diffX = pixXn - pixX;
          double diffY = pixYn - pixY;
          angle = GeoCalculations.toDegrees(atan2(diffX, -diffY));
        }

        // draw circle at center of airport of 1/16th of screen size
        canvas.drawCircle(offsetCircle, (size.height + size.width) / 32, _paintCenter);
        //draw airplane
        canvas.translate(pixX, pixY);
        canvas.rotate((heading + angle) * pi / 180);
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

