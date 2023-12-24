import 'dart:async';
import 'dart:ui';

import 'package:avaremp/conversions.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';


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
  String _timer = "00:00";
  Timer? _upTimer;

  InstrumentListState() {

    // connect to GPS
    Storage().gpsChange.addListener(() {
      setState(() {
        _gndSpeed = Conversions.convertSpeed(Storage().position.speed);
        _altitude = Conversions.convertAltitude(Storage().position.altitude);
        _track = Conversions.convertTrack(Storage().position.heading);
      });
    });
  }

  // up timer
  void _startUpTimer() {
    if(_upTimer != null) {
      _upTimer!.cancel();
      _upTimer = null;
      setState(() {
        _timer = "00:00";
      });
    }
    else {
      _upTimer = Timer.periodic(const Duration(seconds: 1), (tim) {
        setState(() {
          Duration d = Duration(seconds: tim.tick);
          _timer = d.toString().substring(2, 7);
        });
      });
    }
  }

  // make an instrument for top line
  Widget _makeInstrument(int index) {
    bool portrait = MediaQuery.of(context).orientation == Orientation.portrait;
    double width = MediaQuery.of(context).size.width / 6; // get more instruments in
    if(portrait) {
      width = MediaQuery.of(context).size.width / 4;
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
      case "Up Timer":
        value = _timer;
        cb = _startUpTimer;
        break;
    }

    return SizedBox(
        key: Key(index.toString()),
        width: width,
        child:ListTile(
          onTap: cb,
          title: Text(_items[index], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10, fontStyle: FontStyle.italic),),
          subtitle: Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600)
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
