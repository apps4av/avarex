import 'dart:math';
import 'dart:ui' as ui;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/flight_status.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/path_utils.dart';
import 'package:avaremp/storage.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'constants.dart';
import 'data/main_database_helper.dart';
import 'instrument_list.dart';

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

  Future<void> _getAll(landed) async {
    if(landed) {
      // on landing, add to recent the airport we landed at, then set it as current airport
      List<Destination> airports = await MainDatabaseHelper.db
          .findNearestAirportsWithRunways(
          LatLng(Storage().position.latitude, Storage().position.longitude), 0);
      if (airports.isNotEmpty) {
        String? plate = await PathUtils.getAirportDiagram(
            Storage().dataDir, airports[0].locationID);
        if (plate != null) {
          _currentPlateAirport = airports[0].locationID;
          UserDatabaseHelper.db.addRecent(airports[0]);
        }
      }
    }

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

  Future<PlatesFuture> getAll(bool landed) async {
    await _getAll(landed);
    return this;
  }

  AirportDestination? get airportDestination => _airportDestination;
  List<String> get airports => _airports;
  List<String> get plates => _plates;
  String get currentPlateAirport => _currentPlateAirport;
}

class PlateScreenState extends State<PlateScreen> {

  final ValueNotifier _notifier = ValueNotifier(0);

  @override
  void dispose() {
    super.dispose();
    Storage().plateChange.removeListener(_notifyPaint);
    Storage().gpsChange.removeListener(_notifyPaint);
  }

  @override
  Widget build(BuildContext context) {
    // this is to listen for landing event, show airport diagram on landing when this screen shows
    return ValueListenableBuilder(valueListenable: Storage().flightStateChange, builder: (BuildContext context, int value, Widget? child) {
      return FutureBuilder(
        future: PlatesFuture().getAll(value == FlightStatus.flightStateLanded),
        builder: (context, snapshot) {
          if(snapshot.hasData) {
            return _makeContent(snapshot.data);
          }
          else {
            return _makeContent(null);
          }
        }
      );
    });
  }

  // on change of airport, reload first item of the new airport
  Future _loadPlate() async {
    // load plate in background
    await Storage().loadPlate();
    Storage().lastPlateAirport = Storage().settings.getCurrentPlateAirport();
  }


  void _notifyPaint() {
    _notifier.value++;
  }

  Widget _makeContent(PlatesFuture? future) {

    double height = 0;

    if(future == null) {
      return makePlateView([], [], height, _notifier);
    }

    List<String> plates = future.plates;
    List<String> airports = future.airports;
    Storage().settings.setCurrentPlateAirport(future.currentPlateAirport);

    if(airports.isEmpty) {
      return makePlateView([], plates, height, _notifier);
    }

    if(plates.isEmpty) {
      return makePlateView(airports, [], height, _notifier);
    }

    if((Storage().lastPlateAirport !=  Storage().settings.getCurrentPlateAirport())) {
      Storage().currentPlate = plates[0]; // new airport, change to plate 0
    }

    _loadPlate();

    // plate load notification, repaint
    Storage().plateChange.addListener(_notifyPaint);
    Storage().gpsChange.addListener(_notifyPaint);

    return makePlateView(airports, plates, height, _notifier);
  }

  Widget makePlateView(List<String> airports, List<String> plates, double height, ValueNotifier notifier) {

    return Scaffold(body: Stack(children: [
      // always return this so to reduce flicker
      InteractiveViewer(
          minScale: 1,
          maxScale: 8,
          child:
          SizedBox(
            height: Constants.screenHeight(context),
            width: Constants.screenWidth(context),
            child: CustomPaint(painter: _PlatePainter(notifier)),
          )
      ),

      Positioned(
          child: Align(
              alignment: Alignment.topLeft,
              child: Stack(children:[
                if (Storage().settings.isInstrumentsVisiblePlate())
                  SizedBox(height: Constants.screenHeightForInstruments(context), child: const InstrumentList()),
                // allow to hide instruments on plate
                CircleAvatar(
                  backgroundColor: Theme.of(context).dialogBackgroundColor.withOpacity(0.7),
                  child: IconButton(onPressed: () {
                    setState(() {
                      Storage().settings.setInstrumentsVisiblePlate(!Storage().settings.isInstrumentsVisiblePlate());
                    });
                  }, icon: Icon(Storage().settings.isInstrumentsVisiblePlate() ? Icons.open_in_new_off_rounded : Icons.open_in_new_rounded),),)
              ]),
          )
      ),

      plates.isEmpty ? Container() : // nothing to show here if plates is empty
      Positioned(
          child: Align(
              alignment: Alignment.bottomLeft,
              child: plates[0].isEmpty ? Container() : Container(
                  padding: EdgeInsets.fromLTRB(15, 5, 5, Constants.bottomPaddingSize(context) + 5),
                  child:DropdownButtonHideUnderline(
                      child:DropdownButton2<String>(
                        isDense: true,// plate selection
                        customButton: CircleAvatar(backgroundColor: Theme.of(context).dialogBackgroundColor.withOpacity(0.7),child: const Icon(Icons.more_horiz),
                        ),
                        buttonStyleData: ButtonStyleData(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.transparent),
                        ),
                        dropdownStyleData: DropdownStyleData(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                          width: Constants.screenWidth(context) * 0.75,
                        ),
                        isExpanded: false,
                        value: plates.contains(Storage().currentPlate) ? Storage().currentPlate : plates[0],
                        items: plates.map((String item) {
                          return DropdownMenuItem<String>(
                            value: item,
                            child: Row(children:[
                              Expanded(child:
                                Container(
                                  decoration: BoxDecoration(color: _getPlateColor(item),
                                    borderRadius: BorderRadius.circular(5),),
                                    child: Padding(padding: const EdgeInsets.all(5), child:
                                      AutoSizeText(item, minFontSize: 2, maxLines: 1,)),
                                )
                              )
                            ])
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
      ),

      airports.isEmpty ? Container() : // nothing to show here is airports is empty
      Positioned(
          child: Align(
              alignment: Alignment.bottomRight,
              child: airports[0].isEmpty ? Container() : Container(
                  padding: EdgeInsets.fromLTRB(5, 5, 15, Constants.bottomPaddingSize(context) + 5),
                  child:DropdownButtonHideUnderline(
                      child:DropdownButton2<String>( // airport selection
                        buttonStyleData: ButtonStyleData(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Theme.of(context).dialogBackgroundColor.withOpacity(0.7)),
                        ),
                        dropdownStyleData: DropdownStyleData(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                        ),
                        isExpanded: false,
                        value: airports.contains(Storage().settings.getCurrentPlateAirport()) ? Storage().settings.getCurrentPlateAirport() : airports[0],
                        items: airports.map((String item) {
                          return DropdownMenuItem<String>(
                              value: item,
                              child:Text(item, style: TextStyle(fontSize: Constants.dropDownButtonFontSize))
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

    ]
    ));
  }
  
  Color _getPlateColor(String name) {
    if(name.startsWith("APD")) {
      return Colors.green;
    }
    else if(name.startsWith("CSUP")) {
      return Colors.blue;
    }
    else if(name.startsWith("DP")) {
      return Colors.pinkAccent;
    }
    else if(name.startsWith("IAP")) {
      return Colors.purpleAccent;
    }
    else if(name.startsWith("STAR")) {
      return Colors.cyan;
    }
    else if(name.startsWith("MIN")) {
      return Colors.brown;
    }
    else if(name.startsWith("HOT")) {
      return Colors.red;
    }
    else if(name.startsWith("LAH")) {
      return Colors.red;
    }

    return Colors.grey;
  }
}

class _PlatePainter extends CustomPainter {

  List<double>? _matrix;
  ui.Image? _image;
  ui.Image? _imagePlane;

  // Define a paint object
  final _paint = Paint();
  // Define a paint object for circle
  final _paintCenter = Paint()
    ..style = PaintingStyle.fill
    ..color = Constants.plateMarkColor;

  final _paintLine = Paint()
    ..strokeWidth = 6
    ..color = Constants.planeColor;

  _PlatePainter(ValueNotifier repaint): super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {

    _image = Storage().imagePlate;
    _imagePlane = Storage().imagePlane;
    _matrix = Storage().matrixPlate;
    Destination? center = Storage().plateAirportDestination;

    if(_image != null && center != null) {

      // make in center
      double h = size.height;
      double ih = _image!.height.toDouble();
      double w = size.width;
      double iw = _image!.width.toDouble();
      double fac = h / ih;
      double fac2 = w / iw;
      if (fac > fac2) {
        fac = fac2;
      }

      canvas.save();
      canvas.translate(0, 0);
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
          double pixAirportX = (center.coordinate.longitude - lonTopLeft) * dx;
          double pixAirportY = (center.coordinate.latitude - latTopLeft) * dy;
          offsetCircle = Offset(pixAirportX, pixAirportY);
          angle = 0;
        }
        else if(_matrix!.length == 6) {
          double wftA = _matrix![0];
          double wftB = _matrix![1];
          double wftC = _matrix![2];
          double wftD = _matrix![3];
          double wftE = _matrix![4];
          double wftF = _matrix![5];

          pixX = (wftA * lon + wftC * lat + wftE) / 2;
          pixY = (wftB * lon + wftD * lat + wftF) / 2;
          double pixAirportX = (wftA * center.coordinate.longitude + wftC * center.coordinate.latitude + wftE) / 2;
          double pixAirportY = (wftB * center.coordinate.longitude + wftD * center.coordinate.latitude + wftF) / 2;
          offsetCircle = Offset(pixAirportX, pixAirportY);

          double pixXn = (wftA * lon + wftC * (lat + 0.1) + wftE) / 2;
          double pixYn = (wftB * lon + wftD * (lat + 0.1) + wftF) / 2;
          double diffX = pixXn - pixX;
          double diffY = pixYn - pixY;
          angle = GeoCalculations.toDegrees(atan2(diffX, -diffY));
        }

        // draw circle at center of airport
        canvas.drawCircle(offsetCircle, 16  , _paintCenter);
        //draw airplane
        canvas.translate(pixX, pixY);
        canvas.rotate((heading + angle) * pi / 180);
        canvas.drawImage(_imagePlane!, Offset(-_imagePlane!.width / 2, -_imagePlane!.height / 2), _paint);
        // draw all based on screen width, height
        _paintLine.shader = ui.Gradient.linear(Offset(0, 2 * (size.height + size.width) / 64), Offset(0, -(size.height + size.width) / 2), [Colors.red, Colors.white]);
        canvas.drawLine(Offset(0, (size.height + size.width) / 64 - _imagePlane!.height), Offset(0, -(size.height + size.width) / 2), _paintLine);
        _paintLine.shader = null;
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PlatePainter oldDelegate) => true;
}

