import 'dart:ui';

import 'package:flutter/material.dart';


class InstrumentList extends StatefulWidget {
  const InstrumentList({super.key});

  @override
  State<InstrumentList> createState() => _InstrumentListState();
}

class _InstrumentListState extends State<InstrumentList> {
  final List<String> _items  = ["Gnd Speed", "Alt", "Track", "Bearing", "Next", "Dist", "ETE",   "ETA",   "Up Timer"];
  final List<String> _values = ["0",         "0"  , "000",   "000",     "BOS",  "112",  "00:00", "00:00", "00:00"];
  final List<Function> _cbs  = [(){},        (){},  (){},    (){},      (){},   (){},   (){},    (){},    (){}];

  // make an instrument for top line
  Widget makeInstrument(String name, String value, int index, Function onTap) {
    bool portrait = MediaQuery.of(context).orientation == Orientation.portrait;
    double width = MediaQuery.of(context).size.width / 6; // get more instruments in
    if(portrait) {
      width = MediaQuery.of(context).size.width / 4;
    }

    return SizedBox(
        key: Key(index.toString()),
        width: width,
        child:ListTile(onTap: onTap(),
            title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10, fontStyle: FontStyle.italic),),
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
          makeInstrument(_items[index], _values[index], index, _cbs[index]),
      ],
      onReorder: (int oldIndex, int newIndex) {
        setState(() {
          if (oldIndex < newIndex) {
            newIndex -= 1;
          }
          final String item = _items.removeAt(oldIndex);
          _items.insert(newIndex, item);
        });
      },
    );
  }
}
