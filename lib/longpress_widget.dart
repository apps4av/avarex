import 'dart:io';

import 'package:avaremp/main_screen.dart';
import 'package:avaremp/path_utils.dart';
import 'package:avaremp/plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/user_database_helper.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';

import 'airport.dart';
import 'constants.dart';
import 'destination.dart';
import 'nav.dart';

class LongPressWidget extends StatefulWidget {
  final Destination destination;

  // it crashes if not static

  const LongPressWidget({super.key, required this.destination});

  @override
  State<StatefulWidget> createState() => LongPressWidgetState();
}

class LongPressFuture {

  Destination destination;
  Destination showDestination;
  double width;
  double height;
  LongPressFuture(this.destination, this.width, this.height) : showDestination =
      Destination( // GPS default then others
          locationID: Destination.formatSexagesimal(
              destination.coordinate.toSexagesimal()),
              type: Destination.typeGps,
              facilityName: Destination.typeGps,
              coordinate: destination.coordinate);
  List<Widget> pages = [];

  // get everything from database about this destination
  Future<void> _getAll() async {
    // make airport cards

    showDestination = await DestinationFactory.make(destination);

    if(showDestination is AirportDestination) {
      pages.add(Airport.frequenciesWidget(Airport.parseFrequencies(showDestination as AirportDestination)));
      pages.add(Airport.runwaysWidget(showDestination as AirportDestination, width, height));
      // show first plate
      List<String> plates = await PathUtils.getPlatesAndCSupSorted(Storage().dataDir, showDestination.locationID);
      if(plates.isNotEmpty) {
        File ad = File(PathUtils.getPlatePath(
            Storage().dataDir, showDestination.locationID, plates[0]));
        if (await ad.exists()) {
          Image? airportPlate = Image.file(ad);
          pages.add(Card(child:airportPlate));
        }
      }
    }
    else if(showDestination is NavDestination) {
      pages.add(Nav.mainWidget(Nav.parse(showDestination as NavDestination)));
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
        future: LongPressFuture(widget.destination, Constants.screenWidth(context), Constants.screenHeight(context)).getAll(),
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

    if(null == future) {
      return Container();
    }

    // carousel
    List<Card> cards = [];
    for (Widget page in future.pages) {
      cards.add(Card(
          child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox.expand(
                  child: page
              )
          )
      ));
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
          const Expanded(
              flex: 1,
              child: Icon(Icons.drag_handle)),

          Expanded(flex: 1, child: Text("${future.showDestination.facilityName}(${future.showDestination.locationID})", style: const TextStyle(fontWeight: FontWeight.w700),)),
          Expanded(flex: 1, child: Row(children: [
            // top action buttons
            TextButton(
              child: const Text("->D", style: TextStyle(fontSize: 20)),
              onPressed: () {
                UserDatabaseHelper.db.addRecent(future.showDestination);
                Storage().setDestination(future.showDestination);
                if(future.showDestination is AirportDestination) {
                  Storage().settings.setCurrentPlateAirport(future.showDestination.locationID);
                }
                MainScreenState.gotoMap();
                Navigator.of(context).pop(); // hide bottom sheet
              },
            ),
            TextButton(
              child: const Text("+Plan"),
              onPressed: () {
                UserDatabaseHelper.db.addRecent(future.showDestination);
                Storage().route.addWaypoint(Waypoint(future.showDestination));
                MainScreenState.gotoPlan();
                Navigator.of(context).pop(); // hide bottom sheet
              },
            ),
            future.showDestination is AirportDestination ?
              TextButton(
                child: const Text("Plates"),
                onPressed: () { // go to plate
                  if(future.showDestination is AirportDestination) {
                    Storage().settings.setCurrentPlateAirport(future.showDestination.locationID);
                  }
                  MainScreenState.gotoPlate();
                  Navigator.of(context).pop(); // hide bottom sheet
                },
              ) : Container(),
          ])),
          // various info
          Expanded(flex: 20, child: CarouselSlider(
            items: cards,
            options: CarouselOptions(
              viewportFraction: 1,
              enlargeFactor: 0.5,
              enableInfiniteScroll: false,
              enlargeCenterPage: true,
              aspectRatio: Constants.carouselAspectRatio(context),
            ),
          )),
        ],
        ),
      ],
    ));
  }
}
