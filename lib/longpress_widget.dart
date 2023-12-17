import 'package:avaremp/main_screen.dart';
import 'package:avaremp/plate_screen.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';

import 'main_database_helper.dart';

class LongPressWidget extends StatelessWidget {

  FindDestination _destination;

  LongPressWidget(this._destination, {super.key});

  @override
  Widget build(BuildContext context) {

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(10),
          topRight: Radius.circular(10),
        ),
      ),
      child: Row(
        children: [
          IconButton(onPressed: () { // go to plate
            Storage().currentPlateAirport = _destination.locationID;
            MainScreenState.gotoPlate();
            Navigator.of(context).pop(); // hide bottom sheet
          }, icon: const Icon(Icons.book)),
        ],
      ),
    );

  }


}
