import 'dart:math';

import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/waypoint.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'constants.dart';
import 'destination.dart';
import 'gps.dart';


class InstrumentList extends StatefulWidget {
  const InstrumentList({super.key});

  @override
  State<InstrumentList> createState() => InstrumentListState();
}

class InstrumentListState extends State<InstrumentList> {
  final List<String> _items = Storage().settings.getInstruments().split(","); // get instruments
  String _gndSpeed = "0";
  String _altitude = "0";
  String _magneticHeading = "0\u00b0";
  String _timerUp = "00:00";
  String _destination = "";
  String _bearing = "0\u00b0";
  String _distance = "";
  String _utc = "00:00";
  int _countUp = 0;
  bool _doCountUp = false;

  @override
  void dispose() {
    Storage().gpsChange.removeListener(_gpsListener);
    Storage().route.change.removeListener(_routeListener);
    Storage().timeChange.removeListener(_timeListener);
    super.dispose();
  }

  String _truncate(String value) {
    int maxLength = 5;
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
          position, d.coordinate), calculations.getVariation(d.coordinate));
      return (distance, bearing);
    }
    return (0, 0);
  }

  double _angularDifference(double hdg, double brg) {
    double absDiff = (hdg - brg).abs();
    if(absDiff > 180) {
      return 360 - absDiff;
    }
    return absDiff;
  }

  bool _leftOfCourseLine(double bT, double bC) {
    if(bC <= 180) {
      return (bT >= bC && bT <= bC + 180);
    }

    // brgCourse will be > 180 at this point
    return (bT > bC || bT < bC - 180);
  }


  void _gpsListener() {
    // connect to GPS
    double variation = GeoCalculations().getVariation(
        Gps.toLatLng(Storage().position));
    setState(() {
      double q = GeoCalculations.convertSpeed(Storage().position.speed);
      _gndSpeed = _truncate(q.round().toString());
      Storage().pfdData.speed = q;
      q = GeoCalculations.convertAltitude(Storage().position.altitude);
      _altitude = _truncate(q.round().toString());
      Storage().pfdData.altitude = q;
      q = GeoCalculations.getMagneticHeading(
              Storage().position.heading, variation);
      _magneticHeading = _truncate("${q.round()}\u00b0");
      Storage().pfdData.yaw = q;
      var (distance, bearing) = _getDistanceBearing();
      _distance = _truncate(distance.round().toString());
      _bearing = _truncate("${bearing.round().toString()}\u00b0");
      Storage().pfdData.to = bearing;

      // CDI
      Waypoint? next = Storage().route.getCurrentWaypoint();
      Waypoint? prev = Storage().route.getLastWaypoint();

      if (next != null && prev != null) {
        LatLng prevCoordinate = prev.destination.coordinate;
        LatLng nextCoordinate = next.destination.coordinate;

        // The bearing from our CURRENT location to the target
        double brgOrg = GeoCalculations.getMagneticHeading(GeoCalculations().calculateBearing(prevCoordinate, nextCoordinate), variation);
        double brgCur = bearing;
        double brgDif = _angularDifference(brgOrg, brgCur);
        // Distance from our CURRENT position to the destination
        double dstCur = distance;

        // calculate deviation based on bearing diff and distance
        double deviation = dstCur * sin(brgDif * pi / 180); // nm
        // now find course deviation in degrees based on distance and deviation
        double cdi = atan2(deviation, dstCur) * 180 / pi;

        // if distance is less than 15 miles then multiple by 4 for LOC sensitivity
        cdi = dstCur < 15 ? min(cdi * 4, 5) : min(cdi, 5);

        // Now determine whether we are LEFT.
        // Account for REVERSE SENSING if we are already BEYOND the target (>90deg)
        bool bLeftOfCourseLine = _leftOfCourseLine(brgCur,  brgOrg);
        if ((bLeftOfCourseLine && brgDif <= 90) || (!bLeftOfCourseLine && brgDif >= 90)) {
          cdi = -cdi;
        }
        Storage().pfdData.cdi = -cdi;
      }
      else {
        Storage().pfdData.cdi = 0;
      }

      // VDI

    });
  }

  void _routeListener() {
    setState(() {
      PlanRoute? route = Storage().route;
      Destination? d = route.getCurrentWaypoint()?.destination;
      _destination = _truncate(d != null ? d.locationID : "");
      var (distance, bearing) = _getDistanceBearing();
      _distance = _truncate(distance.round().toString());
      _bearing = _truncate("${bearing.round().toString()}\u00b0");
    });
  }

  void _timeListener() {
    setState(() {
      _countUp = _doCountUp ? _countUp + 1 : _countUp;
      Duration d = Duration(seconds: _countUp);
      _timerUp = _truncate(d.toString().substring(2, 7));
      DateFormat formatter = DateFormat('HH:mm');
      _utc = _truncate(formatter.format(DateTime.now().toUtc()));
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
    _doCountUp = _doCountUp ? false : true;
    _countUp = 0;
    Duration d = Duration(seconds: _countUp);
    setState(() {
      _timerUp = _truncate(d.toString().substring(2, 7));
    });
  }

  // make an instrument for top line
  Widget _makeInstrument(int index) {
    bool portrait = Constants.isPortrait(context);
    double width = Constants.screenWidth(context) / 9.5; // get more instruments in
    if(portrait) {
      width = Constants.screenWidth(context) / 5.5;
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
      case "MH":
        value = _magneticHeading;
        break;
      case "NXT":
        value = _destination;
        break;
      case "BRG":
        value = _bearing;
        break;
      case "DST":
        value = _distance;
        break;
      case "UTC":
        value = _utc;
        break;
      case "UPT":
        value = _timerUp;
        cb = _startUpTimer;
        break;
    }

    return Container(
      key: Key(index.toString()),
      width: width,
      decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 0.5), borderRadius: BorderRadius.circular(0), color: Constants.instrumentBackgroundColor),
      child: GestureDetector(
        onTap: cb,
        child: ReorderableDelayedDragStartListener(index: index, child:Column(
          children: [
            Expanded(flex: 1, child: Text(_items[index], style: const TextStyle(color: Constants.instrumentsNormalLabelColor, fontWeight: FontWeight.w500, fontSize: 16), maxLines: 1,)),
            Expanded(flex: 1, child: Text(value, style: const TextStyle(color: Constants.instrumentsNormalValueColor, fontSize: 18, fontWeight: FontWeight.w600), maxLines: 1,)),
          ]
        ),
      )
    ));
  }

  @override
  Widget build(BuildContext context) {

    // user can rearrange widgets
    return ReorderableListView(
      scrollDirection: Axis.horizontal,
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
