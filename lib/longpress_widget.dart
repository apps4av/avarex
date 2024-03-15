import 'dart:io';

import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/main_screen.dart';
import 'package:avaremp/path_utils.dart';
import 'package:avaremp/saa.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/taf.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/waypoint.dart';
import 'package:avaremp/weather/weather.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:widget_zoom/widget_zoom.dart';

import 'airport.dart';
import 'constants.dart';
import 'destination.dart';
import 'weather/metar.dart';
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
  double dimensions;
  Function(String value) labelCallback;
  Image? airportDiagram;
  Widget? ad;
  int? elevation;
  List<Saa> saa = [];

  LongPressFuture(this.destination, this.dimensions, this.labelCallback) : showDestination =
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

      elevation = (showDestination as AirportDestination).elevation.round();

      // made up airport dia
      ad = Airport.runwaysWidget(showDestination as AirportDestination, dimensions);

      // show first plate
      List<String> plates = await PathUtils.getPlatesAndCSupSorted(Storage().dataDir, showDestination.locationID);
      if(plates.isNotEmpty) {
        File file = File(PathUtils.getPlatePath(Storage().dataDir, showDestination.locationID, "AIRPORT-DIAGRAM"));
        if (await file.exists()) {
          airportDiagram = Image.file(file);
        }
      }

      pages.add(Airport.frequenciesWidget(Airport.parseFrequencies(showDestination as AirportDestination)));

    }
    else if(showDestination is NavDestination) {
      pages.add(Nav.mainWidget(Nav.parse(showDestination as NavDestination)));
    }
    else if(showDestination is FixDestination) {
    }
    else if(showDestination is AirwayDestination) {
    }
    else if (showDestination is GpsDestination) {
      // add labeling support
      pages.add(Container(padding: const EdgeInsets.all(50), child:TextFormField(
        decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Set Label'),
        onFieldSubmitted: (value) {
          Destination d = GpsDestination(
              locationID: showDestination.locationID,
              type: showDestination.type,
              facilityName: value,
              coordinate: showDestination.coordinate);
          UserDatabaseHelper.db.addRecent(d);

          labelCallback(value);
      },)));
    }
    // SUA for every press
    saa = await MainDatabaseHelper.db.getSaa(destination.coordinate);
  }

  Future<LongPressFuture> getAll() async {
    await _getAll();
    return this;
  }
}

class LongPressWidgetState extends State<LongPressWidget> {

  final CarouselController _controller = CarouselController();

  void labelCallback(String value) {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {

    double width = Constants.screenWidth(context);
    double height = Constants.screenHeight(context);
    double dimensions = width > height ? height : width;

    return FutureBuilder(
        future: LongPressFuture(widget.destination, dimensions, labelCallback).getAll(),
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


    // general direction from where we are
    GeoCalculations geo = GeoCalculations();
    LatLng ll = LatLng(Storage().position.latitude, Storage().position.longitude);
    double distance = geo.calculateDistance(ll, widget.destination.coordinate);
    double bearing = geo.calculateBearing(ll, widget.destination.coordinate);
    String direction = ("${distance.round()} ${GeoCalculations.getGeneralDirectionFrom(bearing, geo.getVariation(ll))}");
    String facility = future.showDestination.facilityName.length > 16 ? future.showDestination.facilityName.substring(0, 16) : future.showDestination.facilityName;
    String elevation = future.elevation == null ? "" : " @${future.elevation.toString()}ft";
    String label = "$facility (${future.showDestination.locationID})$elevation, $direction";

    Widget? airportDiagram; // if FAA AD is available show that, otherwise show self made AD
    if(future.airportDiagram != null) {
      airportDiagram = future.airportDiagram;
    }
    else if (future.ad != null) {
      airportDiagram = future.ad;
    }


    String k = Constants.useK ? "K" : "";

    int? metarPage;
    int? notamPage;
    int? saaPage;

    if(future.showDestination is AirportDestination) {
      Weather? w = Storage().metar.get("$k${future.showDestination.locationID}");
      Weather? w1 = Storage().taf.get("$k${future.showDestination.locationID}");
      if(w != null || w1 != null) {
        metarPage = future.pages.length;
        future.pages.add(ListView(
          children: [
            w != null
                ? ListTile(title: const Text("METAR"),
              subtitle: Text((w as Metar).text),
              leading: Icon(Icons.circle_outlined, color: w.getColor(),),)
                : Container(),
            w1 != null ? ListTile(title: const Text("TAF"),
                subtitle: Text((w1 as Taf).text),
                leading: const Icon(Icons.circle)) : Container(),
          ],
        ));
      }
      // NOATMS get downloaded on the fly so make this a future.
      notamPage = future.pages.length;
      future.pages.add(FutureBuilder(future: Storage().notam.getSync(
          "$k${future.showDestination.locationID}"),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              Weather? w2 = snapshot.data;
              if (w2 != null) {
                return SingleChildScrollView(child: Text(w2.toString()));
              }
              else {
                return Container();
              }
            }
            else {
              return const ListTile(leading: CircularProgressIndicator());
            }
          }
      ));
    }

    if(future.saa.isNotEmpty) {
      saaPage = future.pages.length;
      future.pages.add(ListView(
        children: [
          for(Saa s in future.saa)
            ListTile(title: Text(s.designator),
                subtitle: Text(s.toString())),
        ],
      ));
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
        Column(children: [
          Expanded(flex: 1, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(flex: 1, child: Row(children: [
            // top action buttons
            TextButton(
              child: const Text("->D"),
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
            if(future.showDestination is AirportDestination)
              TextButton(
                child: const Text("Plates"),
                onPressed: () { // go to plate
                  if(future.showDestination is AirportDestination) {
                    Storage().settings.setCurrentPlateAirport(future.showDestination.locationID);
                  }
                  MainScreenState.gotoPlate();
                  Navigator.of(context).pop(); // hide bottom sheet
                },
              ),
          ])),
          // various info
          Expanded(flex: 7, child: CarouselSlider(
            carouselController: _controller,
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
        // add various buttons that expand to diagram
        Positioned(child: Align(
          alignment: Alignment.bottomRight,
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children:[
          if (future.pages.length > 1)
            TextButton(
                child: const Text("Main"),
                onPressed: () => _controller.animateToPage(0)
            ),
          if (metarPage != null)
            TextButton(
                child: const Text("METAR"),
                onPressed: () => _controller.animateToPage(metarPage!)
            ),
          if(notamPage != null)
            TextButton(
              child: const Text("NOTAM"),
              onPressed: () => _controller.animateToPage(notamPage!)
            ),
          if(saaPage != null)
            TextButton(
                child: const Text("SUA"),
                onPressed: () => _controller.animateToPage(saaPage!)
            ),
          if(airportDiagram != null)
            SizedBox(
                width: 32, height: 32,
                child: WidgetZoom(zoomWidget: airportDiagram, heroAnimationTag: "airportDiagram",)),
          ]
          ),
        )),
      ],
      )
    );
  }
}
