import 'dart:io';

import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/main_screen.dart';
import 'package:avaremp/path_utils.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/taf.dart';
import 'package:avaremp/user_database_helper.dart';
import 'package:avaremp/waypoint.dart';
import 'package:avaremp/weather.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'airport.dart';
import 'constants.dart';
import 'destination.dart';
import 'metar.dart';
import 'nav.dart';

class LongPressWidget extends StatefulWidget {
  final Destination destination;
  final CarouselController buttonCarouselController = CarouselController();

  // it crashes if not static

  LongPressWidget({super.key, required this.destination});

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
      Weather? w = Storage().metar.get("K${showDestination.locationID}");
      Weather? w1 = Storage().taf.get("K${showDestination.locationID}");

      if(w != null || w1 != null) {
        pages.add(ListView(
          children: [
            w != null ? ListTile(title: const Text("METAR"), subtitle: Text((w as Metar).text), leading: Icon(Icons.circle_outlined, color: w.getColor(),),) : Container(),
            w1 != null ? ListTile(title: const Text("TAF"), subtitle: Text((w1 as Taf).text), leading: const Icon(Icons.circle)) : Container(),
          ],
        ));
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

    // general direction from where we are
    GeoCalculations geo = GeoCalculations();
    LatLng ll = LatLng(Storage().position.latitude, Storage().position.longitude);
    double distance = geo.calculateDistance(ll, widget.destination.coordinate);
    double bearing = geo.calculateBearing(ll, widget.destination.coordinate);
    String direction = ("${distance.round()} ${GeoCalculations.getGeneralDirectionFrom(bearing, geo.getVariation(ll))}");

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
          Expanded(flex: 1, child: Text("${future.showDestination.facilityName}(${future.showDestination.locationID}) $direction", style: const TextStyle(fontWeight: FontWeight.w700),)),
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

            cards.length > 1 ? // left right arrows
              IconButton(
                onPressed: () => widget.buttonCarouselController.previousPage(
                    duration: const Duration(milliseconds: 300), curve: Curves.linear),
                icon: const Icon(Icons.chevron_left),
              ) : Container(),
            cards.length > 1 ? // left right arrows
            IconButton(
              onPressed: () => widget.buttonCarouselController.nextPage(
                  duration: const Duration(milliseconds: 300), curve: Curves.linear),
              icon: const Icon(Icons.chevron_right),
            ) : Container(),
          ])),
          // various info
          Expanded(flex: 18, child: CarouselSlider(
            carouselController: widget.buttonCarouselController,
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
