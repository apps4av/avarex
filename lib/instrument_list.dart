import 'dart:async';

import 'package:avaremp/conversions.dart';
import 'package:avaremp/projection.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import 'constants.dart';
import 'destination.dart';


class InstrumentList extends StatefulWidget {
  const InstrumentList({super.key});

  @override
  State<InstrumentList> createState() => InstrumentListState();
}

class InstrumentListState extends State<InstrumentList> {
  final List<String> _items = Storage().settings.getInstruments().split(","); // get instruments
  String _gndSpeed = "0";
  String _altitude = "0";
  String _track = "0\u00b0";
  String _timerUp = "00:00";
  String _destination = "";
  String _bearing = "0\u00b0";
  String _utc = "00:00";
  Timer? _clockTimer;
  int _countUp = 0;
  bool _doCountUp = false;

  InstrumentListState() {

    _startClock(); // this always runs

    String getBearing() {
      Destination? d = Storage().currentDestination;
      Position position = Storage().position;
      if(d != null) {
        Projection p = Projection(position.longitude, position.latitude, d.coordinate.longitude.value, d.coordinate.latitude.value);
        return "${p.getBearing().round()}\u00b0";
      }
      return "0\u00b0";
    }

    // connect to GPS
    Storage().gpsChange.addListener(() {
      setState(() {
        _gndSpeed = Conversions.convertSpeed(Storage().position.speed);
        _altitude = Conversions.convertAltitude(Storage().position.altitude);
        _track = Conversions.convertTrack(Storage().position.heading);
        _bearing = getBearing();
      });
    });

    // connect to dest change
    Storage().destinationChange.addListener(() {
      setState(() {
        Destination? d = Storage().currentDestination;
        _destination = d != null? d.locationID : "";
        _bearing = getBearing();
      });
    });
  }

  // up timer
  void _startUpTimer() {
    _doCountUp = _doCountUp ? false : true;
    _countUp = 0;
    Duration d = Duration(seconds: _countUp);
    setState(() {
      _timerUp = d.toString().substring(2, 7);
    });
  }

  // up timer
  void _startClock() {
    if(_clockTimer != null) {
      _clockTimer!.cancel();
      _clockTimer = null;
    }
    else {
      _clockTimer = Timer.periodic(const Duration(seconds: 1), (tim) {
        setState(() {
          _countUp = _doCountUp ? _countUp + 1 : _countUp;
          Duration d = Duration(seconds: _countUp);
          _timerUp = d.toString().substring(2, 7);
          DateFormat formatter = DateFormat('HH:mm');
          _utc =   formatter.format(DateTime.now().toUtc());
        });
      });
    }
  }


  // make an instrument for top line
  Widget _makeInstrument(int index) {
    bool portrait = Constants.isPortrait(context);
    double width = Constants.screenWidth(context) / 6; // get more instruments in
    if(portrait) {
      width = Constants.screenWidth(context) / 4;
    }

    String value = "";
    Function() cb = () {};

    // set callbacks and connect values
    switch(_items[index]) {
      case "Gnd Speed":
        value = _gndSpeed;
        break;
      case "Alt":
        value = _altitude;
        break;
      case "Track":
        value = _track;
        break;
      case "Dest.":
        value = _destination;
        break;
      case "Bearing":
        value = _bearing;
        break;
      case "UTC":
        value = _utc;
        break;
      case "Up Timer":
        value = _timerUp;
        cb = _startUpTimer;
        break;
    }

    return SizedBox(
        key: Key(index.toString()),
        width: width,
        child:ListTile(
          onTap: cb,
          title: Text(_items[index], style: const TextStyle(color: Constants.instrumentsNormalLabelColor, fontWeight: FontWeight.w900, fontSize: 10, fontStyle: FontStyle.italic),),
          subtitle: Text(value, style: const TextStyle(color: Constants.instrumentsNormalValueColor, fontSize: 24, fontWeight: FontWeight.w600)
          )
        )
    );
  }

  @override
  Widget build(BuildContext context) {

    // user can rearrange widgets
    return ReorderableListView(
      scrollDirection: Axis.horizontal,
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
