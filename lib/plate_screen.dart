import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:avaremp/data/business_database_helper.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/gps.dart';
import 'package:avaremp/path_utils.dart';
import 'package:avaremp/plan/waypoint.dart';
import 'package:avaremp/storage.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import 'constants.dart';
import 'data/main_database_helper.dart';
import 'instrument_list.dart';
import 'map_screen.dart';

// implements a drawing screen with a center reset button.

class PlateScreen extends StatefulWidget {
  const PlateScreen({super.key});
  @override
  State<StatefulWidget> createState() => PlateScreenState();
}

// give plate name like "RNAV RWY 27" find if the procedure name like "R27.AYBEE" applies to this plate and return false if not
bool doesProcedureBelongsToThisPlate(String plateName, String procedureName) {

  if(plateName.isEmpty || procedureName.isEmpty) {
    return false;
  }

  // of the form "IAP-MA-ILS RWY 27"
  RegExp exp = RegExp(r"([A-Z0-9]+)-[A-Z][A-Z]-(.*)");
  Match? match = exp.firstMatch(plateName);
  if(match == null) {
    return false;
  }
  String plate = match.group(2) ?? "";
  String plateType = match.group(1) ?? "";

  List<String> procedureParts = procedureName.split(".");
  if(procedureParts.length < 2) {
    return false;
  }

  // there could be a better way to do it but there is no mapping from d-tpp to cifp. For now less than perfect is fine
  if(plateType == "IAP") {
    if((procedureParts[1] == plate)) {
      return true; // simple straight match
    }
    if(
        (plate.startsWith("LOC") && procedureParts[1].startsWith("L")) ||
        (plate.startsWith("COPTER") && procedureParts[1].startsWith("H")) ||
        (plate.startsWith("VOR AND DME") && procedureParts[1].startsWith("D")) ||
        (plate.startsWith("LOC AND DME BC") && procedureParts[1].startsWith("LBC")) ||
        (plate.startsWith("LOC BC") && procedureParts[1].startsWith("B")) ||
        (plate.startsWith("ILS") && procedureParts[1].startsWith("I")) ||
        (plate.startsWith("RNAV") && procedureParts[1].startsWith("R")) ||
        (plate.startsWith("NDB") && procedureParts[1].startsWith("N")) ||
        (plate.startsWith("VOR") && procedureParts[1].startsWith("S")) ||
        (plate.startsWith("VOR") && procedureParts[1].startsWith("V")) ||
        (plate.startsWith("LDA") && procedureParts[1].startsWith("X")) ||
        false
    ) {
      String runway = procedureParts[1].substring(1);
      // just keep the number of the runway, for example "27" from "27-Y"
      runway = runway.replaceAll(RegExp(r'[^0-9LRC]'), '');
      if(plate.contains(runway)) {
        return true;
      }
    }
    return false;
  }
  else if(plateType == "DP") {
    if(procedureParts[1].length > 4) {
      String proc = procedureParts[1].substring(0, 5);
      if(plate.startsWith(proc)) {
        return true;
      }
    }
    return false;
  }

  return true;

}

// get plates and airports
class PlatesFuture {
  List<String> _plates = [];
  List<String> _airports = [];
  List<String> _procedures = [];
  List<Destination> _businesses = [];
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

    _plates = [];
    if(_currentPlateAirport.isNotEmpty) {
      _plates = await PathUtils.getPlatesAndCSupSorted(Storage().dataDir, _currentPlateAirport);
      _procedures = await MainDatabaseHelper.db.findProcedures(_currentPlateAirport);
      AirportDestination? d = await MainDatabaseHelper.db.findAirport(_currentPlateAirport);
      if(d != null) {
        _businesses = await BusinessDatabaseHelper.db.findBusinesses(d);
      }
    }
    // next one
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
  List<Destination> get business => _businesses;
  List<String> get procedures => _procedures;
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
    return ValueListenableBuilder(valueListenable: Storage().flightStatus.flightStateChange, builder: (BuildContext context, int value, Widget? child) {
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

    if(future == null || future.airports.isEmpty) {
      return makePlateView([], [], [], [], height, _notifier);
    }

    List<String> plates = future.plates;
    List<Destination> business = future.business;
    List<String> airports = future.airports;
    List<String> procedures = future.procedures;
    Storage().settings.setCurrentPlateAirport(future.currentPlateAirport);

    if(plates.isNotEmpty && (Storage().lastPlateAirport !=  Storage().settings.getCurrentPlateAirport())) {
      Storage().currentPlate = plates[0]; // new airport, change to plate 0
    }

    _loadPlate();

    // plate load notification, repaint
    Storage().plateChange.addListener(_notifyPaint);
    Storage().gpsChange.addListener(_notifyPaint);

    List<String> procedureNames = [];
    for(String prec in procedures) {
      if(doesProcedureBelongsToThisPlate(Storage().currentPlate, prec)) {
        procedureNames.add(prec);
      }
    }

    return makePlateView(airports, plates, procedureNames, business, height, _notifier);
  }

  Widget makePlateView(List<String> airports, List<String> plates, List<String> procedures, List<Destination> business, double height, ValueNotifier notifier) {

    bool notAd = !PathUtils.isAirportDiagram(Storage().currentPlate);
    if(notAd) {
      Storage().business = null;
    }

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
          child: (Storage().settings.isInstrumentsVisiblePlate()) ?
            SizedBox(height: Constants.screenHeightForInstruments(context), child: const InstrumentList()) : Container(),
        )
      ),

      // allow user to toggle instruments
      Positioned(
      child: Align(
        alignment: Alignment.topRight,
        child: CircleAvatar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7),
        child: IconButton(onPressed: () {
          setState(() {
            Storage().settings.setInstrumentsVisiblePlate(!Storage().settings.isInstrumentsVisiblePlate());
          });
        }, icon: Icon(Storage().settings.isInstrumentsVisiblePlate() ? MdiIcons.arrowCollapseRight : MdiIcons.arrowCollapseLeft),),),
      )),
      plates.isEmpty ? Container() : // nothing to show here if plates is empty
      Positioned(
          child: Align(
              alignment: Alignment.bottomLeft,
              child: plates[0].isEmpty ? Container() : Container(
                  padding: EdgeInsets.fromLTRB(15, 5, 5, Constants.bottomPaddingSize(context) + 5),
                  child:DropdownButtonHideUnderline(
                      child:DropdownButton2<String>(
                        isDense: true,// plate selection
                        customButton: CircleAvatar(backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7),child: const Icon(Icons.more_horiz),
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

      (business.isEmpty || notAd) ? Container() : // nothing to show here if plates is empty
      Positioned(
          child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                  padding: EdgeInsets.fromLTRB(15, 5, 5, Constants.bottomPaddingSize(context) + 5),
                  child:DropdownButtonHideUnderline(
                      child:DropdownButton2<String>(
                        isDense: true,// plate selection
                        customButton: CircleAvatar(backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7),child: const Icon(Icons.more_horiz),
                        ),
                        buttonStyleData: ButtonStyleData(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.transparent),
                        ),
                        dropdownStyleData: DropdownStyleData(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                          width: Constants.screenWidth(context) * 0.75,
                        ),
                        isExpanded: false,
                        value: business.contains(Storage().business) ? Storage().business!.facilityName : business[0].facilityName,
                        items: business.map((Destination item) {
                          return DropdownMenuItem<String>(
                              value: item.facilityName,
                              child: Row(children:[
                                Expanded(child:
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(5),),
                                  child: Padding(padding: const EdgeInsets.all(5), child:
                                  AutoSizeText(item.facilityName, minFontSize: 2, maxLines: 1,)),
                                )
                                )
                              ])
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            Storage().business = value == null ? business[0] : business.firstWhere((element) => element.facilityName == value, orElse: () => business[0]);
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  procedures.isEmpty || procedures[0].isEmpty ? Container() : // nothing to show here if plates is empty
                  Container(
                    padding: EdgeInsets.fromLTRB(15, 5, 5, Constants.bottomPaddingSize(context) + 5),
                    child:DropdownButtonHideUnderline(
                        child:DropdownButton2<String>(
                          isDense: true,// plate selection
                            customButton: CircleAvatar(radius: 14, backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7),child: const Icon(Icons.route)),
                            buttonStyleData: ButtonStyleData(
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.transparent),
                          ),
                          dropdownStyleData: DropdownStyleData(
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                            width: Constants.screenWidth(context) * 0.75,
                          ),
                          isExpanded: false,
                          value: procedures[0],
                          items: procedures.map((String item) {
                            return DropdownMenuItem<String>(
                                value: item,
                                child: Row(children:[
                                  Expanded(child:
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(5),),
                                    child: Padding(padding: const EdgeInsets.all(5), child:
                                    AutoSizeText(item, minFontSize: 2, maxLines: 1,)),
                                  ))
                                ])
                            );
                          }).toList(),
                          onChanged: (value) {
                            if(value == null) {
                              return;
                            }
                            MainDatabaseHelper.db.findProcedure(value).then((ProcedureDestination? procedure) {
                              if(procedure != null) {
                                Storage().route.addWaypoint(Waypoint(procedure));
                                setState(() {
                                  MapScreenState.showToast(context, "Added ${procedure.facilityName} to Plan", null, 3);
                                  // show toast message that the procedure is added to the plan
                                });
                              }
                            });
                          },
                        )
                    )
                  ),

                  airports[0].isEmpty ? Container() :
                  Container(
                    padding: EdgeInsets.fromLTRB(5, 5, 15, Constants.bottomPaddingSize(context) + 5),
                    child:DropdownButtonHideUnderline(
                      child:DropdownButton2<String>( // airport selection
                        buttonStyleData: ButtonStyleData(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7)),
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
            ]
          )
      ),
    )
    ])
    );
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
  Destination? _business;
  ui.Image? _image;
  ui.Image? _imagePlane;
  double? _variation;

  // Define a paint object
  final _paint = Paint()
    ..isAntiAlias = true
    ..filterQuality = FilterQuality.high;
  // Define a paint object for circle
  final _paintCenter = Paint()
    ..style = PaintingStyle.fill
    ..color = Constants.plateMarkColor;

  final _paintLine = Paint()
    ..strokeWidth = 6
    ..color = Constants.planeColor;

  final _paintCompass = Paint()
    ..strokeWidth = 3
    ..color = Colors.red;

  final _paintBusiness = Paint()
    ..strokeWidth = 3
    ..color = Colors.blueAccent.withAlpha(200)
    ..style = PaintingStyle.fill;

  _PlatePainter(ValueNotifier repaint): super(repaint: repaint);

  (Offset, double) _calculateOffset(LatLng ll) {
    double lon = ll.longitude;
    double lat = ll.latitude;
    Offset offset = const Offset(0, 0);
    double angle = 0;
    if(_matrix!.length == 4) {
      double dx = _matrix![0];
      double dy = _matrix![1];
      double lonTopLeft = _matrix![2];
      double latTopLeft = _matrix![3];
      double pixX = (lon - lonTopLeft) * dx;
      double pixY = (lat - latTopLeft) * dy;
      offset = Offset(pixX, pixY);
      angle = 0;
    }
    else if(_matrix!.length == 6) {
      double wftA = _matrix![0];
      double wftB = _matrix![1];
      double wftC = _matrix![2];
      double wftD = _matrix![3];
      double wftE = _matrix![4];
      double wftF = _matrix![5];

      double pixX = (wftA * lon + wftC * lat + wftE) / 2;
      double pixY = (wftB * lon + wftD * lat + wftF) / 2;
      offset = Offset(pixX, pixY);

      double pixXn = (wftA * lon + wftC * (lat + 0.1) + wftE) / 2;
      double pixYn = (wftB * lon + wftD * (lat + 0.1) + wftF) / 2;
      double diffX = pixXn - pixX;
      double diffY = pixYn - pixY;
      angle = GeoCalculations.toDegrees(atan2(diffX, -diffY));
    }
    return (offset, angle);
  }

  @override
  void paint(Canvas canvas, Size size) {

    _image = Storage().imagePlate;
    _business = Storage().business;
    _variation = Storage().area.variation;
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
        Offset offsetCircle = const Offset(0, 0);
        Offset offsetPlane = const Offset(0, 0);
        double angle = 0;

        (offsetCircle, _) = _calculateOffset(center.coordinate);
        (offsetPlane, angle) = _calculateOffset(Gps.toLatLng(Storage().position));

        // draw circle at center of airport
        canvas.drawCircle(offsetCircle, 16  , _paintCenter);

        if(_business != null) {
          // draw selected business
          Offset offsetBiz = const Offset(0, 0);
          (offsetBiz, _) = _calculateOffset(_business!.coordinate);
          canvas.drawCircle(offsetBiz, 10, _paintBusiness);
          offsetBiz = Offset(offsetBiz.dx + 12, offsetBiz.dy - 12);
          TextSpan span = TextSpan(text: _business!.facilityName.substring(0, min(_business!.facilityName.length, 24)),
              style: TextStyle(color: Colors.red, backgroundColor: Colors.white, fontWeight: FontWeight.bold, fontSize: 12));
          TextPainter tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
          tp.layout();
          tp.paint(canvas, offsetBiz);
        }

        //draw airplane
        canvas.translate(offsetPlane.dx, offsetPlane.dy);
        canvas.rotate((heading + angle) * pi / 180);
        canvas.drawImage(_imagePlane!, Offset(-_imagePlane!.width / 2, -_imagePlane!.height / 2), _paint);
        // draw all based on screen width, height
        _paintLine.shader = ui.Gradient.linear(Offset(0, 2 * (size.height + size.width) / 64), Offset(0, -(size.height + size.width) / 2), [Colors.red, Colors.white]);
        canvas.drawLine(Offset(0, (size.height + size.width) / 64 - _imagePlane!.height), Offset(0, -(size.height + size.width) / 2), _paintLine);
        double a = (_variation! - 90 - heading) * pi / 180;
        double x2 = 64 * cos(a);
        double y2 = 64 * sin(a);
        double x3 = 54 * cos(a - 0.1);
        double y3 = 54 * sin(a - 0.1);
        canvas.drawLine(const Offset(0, 0), Offset(x2, y2), _paintCompass);
        canvas.drawLine(Offset(x2, y2), Offset(x3, y3), _paintCompass);
        _paintLine.shader = null;
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PlatePainter oldDelegate) => true;
}

