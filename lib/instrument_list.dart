import 'dart:math';

import 'package:avaremp/destination/destination_calculations.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/map_screen.dart';
import 'package:avaremp/pfd_painter.dart';
import 'package:avaremp/plan/plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/plan/waypoint.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'constants.dart';
import 'package:avaremp/destination/destination.dart';
import 'gps.dart';


class InstrumentList extends StatefulWidget {
  const InstrumentList({super.key});

  @override
  State<InstrumentList> createState() => InstrumentListState();

  static double angularDifference(double hdg, double brg) {
    double absDiff = (hdg - brg).abs();
    if(absDiff > 180) {
      return 360 - absDiff;
    }
    return absDiff;
  }

  static bool leftOfCourseLine(double bT, double bC) {
    if(bC <= 180) {
      return (bT >= bC && bT <= bC + 180);
    }

    // brgCourse will be > 180 at this point
    return (bT > bC || bT < bC - 180);
  }

}

class InstrumentListState extends State<InstrumentList> {
  static final DateFormat _hourMinuteFormatter = DateFormat('HH:mm');
  final List<String> _items = Storage().settings.getInstruments().split(","); // get instruments
  late List<Color> _itemsColors;
  String _gndSpeed = "0";
  String _altitude = "0";
  String _magneticHeading = "0\u00b0";
  String _timerUp = "00:00";
  String _timerDown = "30:00";
  String _destination = "";
  String _previousDestination = "";
  String _bearing = "0\u00b0";
  String _distance = "";
  String _utc = "00:00";
  String _eta = "";
  String _ete = "";
  String _source = "";
  String _vsr = "";
  String _flightTime = "00:00";

  @override
  void dispose() {
    Storage().gpsChange.removeListener(_gpsListener);
    Storage().route.change.removeListener(_routeListener);
    Storage().timeChange.removeListener(_timeListener);
    super.dispose();
  }

  String _truncate(String value) {
    int maxLength = 10;
    return value.length > maxLength ? value.substring(0, maxLength) : value;
  }

  (double, double) _getDistanceBearing() {
    LatLng position = Gps.toLatLng(Storage().position);
    GeoCalculations calculations = GeoCalculations();

    Destination? d = Storage().route.getCurrentWaypoint()?.destination;
    if (d != null) {
      double distance = calculations.calculateDistance(
          position, d.coordinate);
      double bearing = GeoCalculations.getMagneticHeading(calculations.calculateBearing(
          position, d.coordinate), d.geoVariation?? 0);
      return (distance, bearing);
    }
    return (0, 0);
  }


  void _gpsListener() {
    // connect to GPS
    double variation = Storage().area.variation;
    setState(() {
      double q = GeoCalculations.convertSpeed(Storage().position.speed);
      _gndSpeed = _truncate(q.round().toString());
      q = GeoCalculations.convertAltitude(Storage().position.altitude);
      _altitude = _truncate(q.round().toString());
      q = GeoCalculations.getMagneticHeading(Storage().position.heading, variation);
      _magneticHeading = _truncate("${q.round()}\u00b0");
      var (distance, bearing) = _getDistanceBearing();
      _distance = _truncate(distance.round().toString());
      _bearing = _truncate("${bearing.round().toString()}\u00b0");
      Storage().pfdData.to = bearing;

      // CDI
      Waypoint? next = Storage().route.getCurrentWaypoint();
      Waypoint? prev = Storage().route.getLastWaypoint();

      double cdi = 0;
      if (next != null && prev != null) {
        LatLng prevCoordinate = prev.destination.coordinate;
        LatLng nextCoordinate = next.destination.coordinate;

        // The bearing from our CURRENT location to the target
        double brgOrg = GeoCalculations.getMagneticHeading(GeoCalculations().calculateBearing(prevCoordinate, nextCoordinate), variation);
        double brgCur = bearing;
        double brgDif = InstrumentList.angularDifference(brgOrg, brgCur);
        // Distance from our CURRENT position to the destination
        double dstCur = distance;

        // calculate deviation based on bearing diff and distance
        double deviation = dstCur * sin(brgDif * pi / 180); // nm
        // now find course deviation in degrees based on distance and deviation
        cdi = atan2(deviation, dstCur) * 180 / pi;

        // if distance is less than 15 miles then multiple by 4 for LOC sensitivity
        cdi = dstCur < 15 ? min(cdi * 4, 5) : min(cdi, 5);

        // Now determine whether we are LEFT.
        // Account for REVERSE SENSING if we are already BEYOND the target (>90deg)
        bool bLeftOfCourseLine = InstrumentList.leftOfCourseLine(brgCur,  brgOrg);
        if ((bLeftOfCourseLine && brgDif <= 90) || (!bLeftOfCourseLine && brgDif >= 90)) {
          cdi = -cdi;
        }
      }
      Storage().pfdData.cdi = -cdi;

      // VDI

      double vdi = 0;
      double relativeAGL = 0;

      if(next != null) {
        // Fetch the elevation of our destination. If we can't find it
        // then we don't want to display any vertical information
        double? destElev = next.destination is AirportDestination ? (next.destination as AirportDestination).elevation : null;

        if(destElev != null) {
          // Calculate our relative AGL compared to destination. If we are
          // lower then no display info
          relativeAGL = Storage().units.mToF * Storage().position.altitude - destElev;

          // Convert the destination distance to feet.
          double destDist = distance;
          double destInFeet = destDist * 6076.12;

          // Figure out our glide slope now based on our AGL height and distance
          vdi = atan(relativeAGL / destInFeet) * 180 / pi;
          if(vdi >= PfdPainter.vnavHigh) {
            vdi = PfdPainter.vnavHigh;
          }
          else if(vdi <= PfdPainter.vnavLow) {
            vdi = PfdPainter.vnavLow;
          }
        }

        // find time to next, not interested in fuel
        double? ws;
        double? wd;
        (wd, ws) = WindsCache.getWindsAt(next.destination.coordinate, GeoCalculations.convertAltitude(Storage().position.altitude), 6); // 6HR wind

        Destination d = Destination.fromLatLng(Gps.toLatLng(Storage().position));
        DestinationCalculations calc = DestinationCalculations(d, next.destination,
            GeoCalculations.convertSpeed(Storage().position.speed), 0, wd, ws, GeoCalculations.convertAltitude(Storage().position.altitude));
        calc.calculateTo();
        if(calc.time.isFinite) {
          Duration time = Duration(seconds: calc.time.round());
          if(time > const Duration(hours: 23)) { // no flight more than this long and saves overflow in instrument
            _eta = "XX:XX";
            _ete = "XX:XX";
            _vsr = "0";
          }
          else {
            _eta =
                _truncate(
                    _hourMinuteFormatter.format(DateTime.now().add(time)));
            _ete = _truncate(
                "${time.inHours.toString().padLeft(2, '0')}:${time.inMinutes.remainder(60).toString().padLeft(2, '0')}");
            if(destElev == null) {
              _vsr = "-";
            }
            else {
              if(time.inMinutes.toDouble() == 0) {
                _vsr = "-";
              }
              else {
                _vsr = _truncate(
                    ((relativeAGL - 1000) / time.inMinutes.toDouble())
                        .round()
                        .toStringAsFixed(0));
              }
            }
          }
        }
        else {
          _eta = "-";
          _ete = "-";
          _vsr = "-";
        }
      }
      Storage().pfdData.vdi = vdi;
    });
  }

  String _formatDestination(Destination? d) {
    if(d == null) {
      return "";
    }
    if(Destination.typeGps == d.type) {
      return _truncate(d.facilityName);
    }
    else if((Destination.isAirway(d.type) || (Destination.isProcedure(d.type))) && d.secondaryName != null) {
      return _truncate(d.secondaryName!);
    }
    else {
      return _truncate(d.locationID);
    }
  }

  void _routeListener() {
    setState(() {
      PlanRoute? route = Storage().route;
      Destination? d = route.getCurrentWaypoint()?.destination;
      if(d == null) {
        _eta = "";
        _ete = "";
        _vsr = "";
        _destination = "";
      }
      else {
        _destination = _formatDestination(d);
      }
      var (distance, bearing) = _getDistanceBearing();
      _distance = _truncate(distance.round().toString());
      _bearing = _truncate("${bearing.round().toString()}\u00b0");

      // previous destination
      d = Storage().route.getPreviousDestination();
      if(d == null) {
        _previousDestination = "";
      }
      else {
        _previousDestination = _formatDestination(d);
      }
    });


  }

  void _timeListener() {
    setState(() {
      _timerUp = _truncate(Storage().flightTimer.getTime().toString().substring(2, 7));
      _timerDown = _truncate(Storage().flightDownTimer.getTime().toString().substring(2, 7));
      _itemsColors[_items.indexOf("DNT")] = Storage().flightDownTimer.isExpired() ? Colors.red : Theme.of(context).cardColor.withValues(alpha: 0.6);
      _utc = _truncate(_hourMinuteFormatter.format(DateTime.now().toUtc()));
      _source = Storage().gpsInternal ? "Internal" : "External";
      _flightTime = _truncate((Storage().flightStatus.flightTime.toDouble() / 3600).toStringAsFixed(2));
    });
  }

  InstrumentListState() {
    Storage().gpsChange.addListener(_gpsListener);
    // connect to dest change
    Storage().route.change.addListener(_routeListener);
    // up timer
    Storage().timeChange.addListener(_timeListener);
  }

  // up timer
  void _startUpTimer() {
    if(Storage().flightTimer.isStarted()) {
      Storage().flightTimer.stop();
    }
    else {
      Storage().flightTimer.reset();
      Storage().flightTimer.start();
    }
    setState(() {
      _timerUp = _truncate(Storage().flightTimer.getTime().toString().substring(2, 7));
    });
  }

  // skip waypoint
  void _planNextWaypoint() {
    Storage().route.advance();
  }

  // skip waypoint
  void _planPreviousWaypoint() {
    Storage().route.back();
  }

  // down timer
  void _startDownTimer() {

    if(Storage().flightDownTimer.isStarted()) {
      Storage().flightDownTimer.stop();
    }
    else {
      Storage().flightDownTimer.reset();
      Storage().flightDownTimer.start();
    }
    setState(() {
      _itemsColors[_items.indexOf("DNT")] = Theme.of(context).cardColor.withValues(alpha: 0.6);
      _timerDown = _truncate(Storage().flightDownTimer.getTime().toString().substring(2, 7));
    });
  }

  // down timer
  void _resetTacTimer() {
    Storage().flightStatus.resetFlightTime();
  }

  // make an instrument for top line
  Widget _makeInstrument(int index) {
    bool portrait = Constants.isPortrait(context);
    double width = Constants.screenWidth(context) / 9.7 / Storage().settings.getInstrumentScaleFactor(); // get more instruments in
    if(portrait) {
      width = Constants.screenWidth(context) / 5.7 / Storage().settings.getInstrumentScaleFactor();
    }

    String value = "";
    Function() cb = () {};

    // set callbacks and connect values
    switch(_items[index]) {
      case "GS":
        value = _gndSpeed;
        break;
      case "ALT":
        value = _altitude;
        break;
      case "MT":
        value = _magneticHeading;
        break;
      case "PRV":
        value = _previousDestination;
        cb = _planPreviousWaypoint;
        break;
      case "NXT":
        value = _destination;
        cb = _planNextWaypoint;
        break;
      case "BRG":
        value = _bearing;
        break;
      case "DIS":
        value = _distance;
        break;
      case "ETA":
        value = _eta;
        break;
      case "ETE":
        value = _ete;
        break;
      case "VSR":
        value = _vsr;
        break;
      case "UTC":
        value = _utc;
        break;
      case "UPT":
        value = _timerUp;
        cb = _startUpTimer;
        break;
      case "DNT":
        value = _timerDown;
        cb = _startDownTimer;
        break;
      case "SRC":
        value = _source;
        break;
      case "FLT":
        value = _flightTime;
        cb = _resetTacTimer;
        break;
    }

    return ReorderableDelayedDragStartListener(
        index: index,
        key: Key(index.toString()),
        child: GestureDetector(
          onTap: cb,
          child: Container(
          width: width,
          decoration: BoxDecoration(borderRadius: const BorderRadius.all(Radius.circular(20)), color: _itemsColors[index]),
          child: Column(
            children: [
              Expanded(flex: 2, child: SizedBox(width: width - 10, child: FittedBox(child: Text(_items[index], style: const TextStyle( ), maxLines: 1,)))),
              Expanded(flex: 3, child: SizedBox(width: width - 10, child: FittedBox(child: Text(value,         style: const TextStyle( ), maxLines: 1,)))),
            ]),
          )
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    _itemsColors = List.generate(Storage().settings.getInstruments().split(",").length, (index) => Theme.of(context).cardColor.withValues(alpha: 0.6));

    // init everything
    _gpsListener();
    _routeListener();
    _timeListener();

    // user can rearrange widgets
    return ReorderableListView(
      shrinkWrap: true,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(5, 5, 5, 0),
      header: Column(children:[
        DropdownButtonHideUnderline(
          child:DropdownButton2<String>(
            dropdownStyleData: DropdownStyleData(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
              width: 96,
            ),
            isExpanded: false,
            customButton: CircleAvatar(radius: 16, backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7), child: const Icon(Icons.arrow_drop_down),),
              onChanged: (value) {
                setState(() {
                });
              },
            items: [
              DropdownMenuItem(
                value: "1",
                onTap:() {
                  Storage().settings.setInstrumentScaleFactor(Storage().settings.getInstrumentScaleFactor() - 0.1);
                },
                child: const Text("Expand", style: TextStyle(fontSize: 12),),
              ),
              DropdownMenuItem(
                value: "2",
                onTap:() {
                  Storage().settings.setInstrumentScaleFactor(Storage().settings.getInstrumentScaleFactor() + 0.1);
                },
                child: const Text("Contract", style: TextStyle(fontSize: 12),),
              ),

              DropdownMenuItem(
                value: "4",
                onTap:() {
                  // Make a toast and show
                  MapScreenState.showToast(context,
                      "You may adjust the size of the tiles using Expand/Contract.\n"
                      "You may drag a tile to adjust its position.\n\n"
                      "Available Tiles:\n"
                      "GS  - Ground speed.\n"
                      "ALT - GPS altitude.\n"
                      "MT  - Magnetic track.\n"
                      "PRV - Previous waypoint.\n"
                      "NXT - Next waypoint.\n"
                      "DIS - Distance to the next waypoint.\n"
                      "BRG - Bearing to the next waypoint.\n"
                      "ETA - Estimated time of arrival at the next waypoint.\n"
                      "ETE - Estimated time en-route to the next waypoint.\n"
                      "VSR - VSI required to arrive at the NXT airport 1000ft above its elevation.\n"
                      "UPT - Up count timer.\n"
                      "DNT - Down count timer.\n"
                      "UTC - Coordinated Universal Time.\n"
                      "SRC - Source of GPS data.\n"
                      "FLT - Total flight time in hours.\n\n"
                      "Tap PRV/NXT to skip to previous/next waypoint.\n"
                      "Tap UPT to start/stop the up timer.\n"
                      "Tap DNT to start/stop the down timer.\n"
                      "Tap FLT to reset the flight timer.\n",
                      null, 30);
                  },
                  child: const Text("?", style: TextStyle(fontSize: 12),),
                ),
            ],
          )
        ),
      ]),
      buildDefaultDragHandles: false,
      children: <Widget>[
        for(int index = 0; index < _items.length; index++)
          _makeInstrument(index),
      ],
      onReorder: (int oldIndex, int newIndex) {
        setState(() {
          if (oldIndex < newIndex) {
            newIndex -= 1;
          }
          final String item = _items.removeAt(oldIndex);
          _items.insert(newIndex, item);
        });
        // save order for next start
        Storage().settings.setInstruments(_items.join(","));
      },
    );
  }
}
