import 'dart:io';

import 'package:avaremp/main_database_helper.dart';
import 'package:avaremp/main_screen.dart';
import 'package:avaremp/path_utils.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/user_database_helper.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';

import 'airport.dart';
import 'constants.dart';
import 'destination.dart';

class LongPressWidget extends StatefulWidget {
  final Destination destination;

  // it crashes if not static
  final CarouselController controller = CarouselController();

  LongPressWidget({super.key, required this.destination});

  @override
  State<StatefulWidget> createState() => LongPressWidgetState();
}

class LongPressFuture {

  Destination destination;
  AirportDestination? airport;
  Image? airportPlate;

  LongPressFuture(this.destination);

  // get everything from database about this destination
  Future<void> _getAll() async {
    airport = await MainDatabaseHelper.db.findAirport(destination.locationID);

    if(null != airport) {
      // show first plate
      List<String> plates = await PathUtils.getPlatesAndCSupSorted(Storage().dataDir, airport!.locationID);
      if(plates.isNotEmpty) {
        File ad = File(PathUtils.getPlatePath(
            Storage().dataDir, airport!.locationID, plates[0]));
        if (await ad.exists()) {
          airportPlate = Image.file(ad);
        }
      }
    }
  }

  Future<LongPressFuture> getAll() async {
    await _getAll();
    return this;
  }
}

class LongPressWidgetState extends State<LongPressWidget> {

  @override
  Widget build(BuildContext context) {

    return FutureBuilder(
        future: LongPressFuture(widget.destination).getAll(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return _makeContent(snapshot.data);
          }
          else {
            return _makeContent(null);
          }
        }
    );
  }

  Widget _makeContent(LongPressFuture? future) {


    if(null == future || null == future.airport) {
      return Container();
    }

    // carousel
    List<Card> cards = [];

    String frequencies = Airport.parseFrequencies(future.airport!);
    if(frequencies.isNotEmpty) {
      cards.add(Card(
          child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox.expand(
                  child: Airport.frequenciesWidget(frequencies)
              )
          )
      )
      );
    }

    cards.add(Card(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.expand(
                  child: Airport.runwaysWidget(future.airport!)
              )
          )
        )
    );

    if(future.airportPlate != null) {
      cards.add(Card(child:future.airportPlate));
    }

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(10),
          topRight: Radius.circular(10),
        ),
      ),
      child: Stack(children:[

        Column(
        children: [
          Text("${future.airport!.facilityName}(${future.airport!.locationID})", style: const TextStyle(fontWeight: FontWeight.w700),),
          Row(children: [
            // top action buttons
            TextButton(
              child: const Text("->D"),
              onPressed: () { // go to plate
                UserDatabaseHelper.db.addRecent(future.airport!);
                MainScreenState.gotoMap();
                Navigator.of(context).pop(); // hide bottom sheet
              },
            ),
            TextButton(
              child: const Text("Plates"),
              onPressed: () { // go to plate
                Storage().settings.setCurrentPlateAirport(future.destination.locationID);
                MainScreenState.gotoPlate();
                Navigator.of(context).pop(); // hide bottom sheet
              },
            ),
          ]),
          // various info
          CarouselSlider(
            carouselController: widget.controller,
            items: cards,
            options: CarouselOptions(
              viewportFraction: 1,
              enlargeFactor: 0.5,
              enableInfiniteScroll: false,
              enlargeCenterPage: true,
              aspectRatio: Constants.carouselAspectRatio(context),
            ),
          ),
        ],
        ),
        Align(alignment: Alignment.bottomRight, child:
        TextButton(
          child: const Text("Next"), // Go Through pages of carousel
          onPressed: () => widget.controller.nextPage()
        )),
        Align(alignment: Alignment.bottomLeft, child:
        TextButton(
            child: const Text("Last"), // Go Through pages of carousel
            onPressed: () => widget.controller.previousPage()
        )),
      ],
    ));
  }
}
