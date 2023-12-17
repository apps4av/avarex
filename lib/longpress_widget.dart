import 'package:avaremp/main_screen.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';

import 'main_database_helper.dart';

class LongPressWidget extends StatefulWidget {
  final FindDestination destination;

  const LongPressWidget({super.key, required this.destination});
  @override
  State<StatefulWidget> createState() => LongPressWidgetState();
}


class LongPressWidgetState extends State<LongPressWidget> {

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
          Text(widget.destination.locationID),
          IconButton(
            onPressed: () { // go to plate
              Storage().currentPlateAirport = widget.destination.locationID;
              MainScreenState.gotoPlate();
              Navigator.of(context).pop(); // hide bottom sheet
            },
            icon: const Icon(Icons.book)),
        ],
      ),
    );

  }


}
