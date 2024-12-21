import 'dart:io';

import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/main_screen.dart';
import 'package:avaremp/path_utils.dart';
import 'package:avaremp/saa.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/notam.dart';
import 'package:avaremp/weather/sounding.dart';
import 'package:avaremp/weather/taf.dart';
import 'package:avaremp/plan/waypoint.dart';
import 'package:avaremp/weather/weather.dart';
import 'package:avaremp/weather/winds_aloft.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:toastification/toastification.dart';

import 'destination/airport.dart';
import 'constants.dart';
import 'package:avaremp/destination/destination.dart';
import 'weather/metar.dart';
import 'package:avaremp/destination/nav.dart';

class LongPressWidget extends StatefulWidget {
  final List<Destination> destinations;

  const LongPressWidget({super.key, required this.destinations});

  @override
  State<StatefulWidget> createState() => LongPressWidgetState();

}

class LongPressFuture {

  Destination destination;
  Destination showDestination;
  Image? airportDiagram;
  int? elevation;
  List<Saa> saa = [];

  LongPressFuture(this.destination) : showDestination =
      Destination( // GPS default then others
          locationID: Destination.toSexagesimal(
              destination.coordinate),
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

      // show first plate
      String? apd = await PathUtils.getAirportDiagram(Storage().dataDir, showDestination.locationID);
      if(apd != null) {
        File file = File(PathUtils.getFilePath(Storage().dataDir, PathUtils.getFilePath(showDestination.locationID, apd)));
        airportDiagram = Image.file(file);
      }

      pages.add(Airport.parseFrequencies(showDestination as AirportDestination));

    }
    else if(showDestination is NavDestination) {
      pages.add(Nav.mainWidget(Nav.parse(showDestination as NavDestination)));
    }
    else if(showDestination is FixDestination) {
      pages.add(const Text("Fix"));
    }
    else if(showDestination is AirwayDestination) {
      pages.add(const Text(Destination.typeAirway));
    }
    else if(showDestination is ProcedureDestination) {
      pages.add(const Text(Destination.typeProcedure));
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

  final CarouselSliderController _controller = CarouselSliderController();

  @override
  Widget build(BuildContext context) {

    return FutureBuilder(
        future: LongPressFuture(widget.destinations[0]).getAll(),
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
    double distance = geo.calculateDistance(ll, widget.destinations[0].coordinate);
    double bearing = geo.calculateBearing(ll, widget.destinations[0].coordinate);
    String direction = ("${distance.round()} ${GeoCalculations.getGeneralDirectionFrom(bearing, Storage().area.variation)}");
    String facility = future.showDestination.facilityName.length > 16 ? future.showDestination.facilityName.substring(0, 16) : future.showDestination.facilityName;
    String elevation = future.elevation == null ? "" : " @${future.elevation.toString()}";
    String label = "$facility (${future.showDestination.locationID})$elevation, $direction";

    Widget? airportDiagram; // if FAA AD is available show that, otherwise show self made AD

    if(future.airportDiagram != null) {
      airportDiagram = Center(child: Container(
          child: future.airportDiagram,
        ),
      );
    }
    else if (future.showDestination is AirportDestination) {
      // made up airport dia
      double width = Constants.screenWidth(context);
      double height = Constants.screenHeight(context);
      double dimensions = width > height ? height : width;
      Widget ad = Airport.runwaysWidget(future.showDestination as AirportDestination, dimensions, context);
      airportDiagram = Center(child: ad);
    }

    int? metarPage;
    int? notamPage;
    int? saaPage;
    int? windsPage;
    Weather? winds;
    String? station = WindsCache.locateNearestStation(widget.destinations[0].coordinate);
    if(station != null) {
      winds = Storage().winds.get(station);
    }
    Widget? sounding = Sounding.getSoundingImage(widget.destinations[0].coordinate, context);

    if(future.showDestination is AirportDestination) {
      Weather? w = Storage().metar.get(future.showDestination.locationID);
      Weather? w1 = Storage().taf.get(future.showDestination.locationID);
      if(w != null || w1 != null) {
        metarPage = future.pages.length;
        future.pages.add(ListView(
          children: [
            w != null
                ? ListTile(title: const Text("METAR"),
              subtitle: Text((w as Metar).text),
              leading: Icon(Icons.circle_outlined, color: w.getColor(), size:32),)
                : Container(),
            w1 != null ? ListTile(title: const Text("TAF"),
                subtitle: Text((w1 as Taf).text),
                leading: w1.getIcon()) : Container(),
          ],
        ));
      }
      // NOTAMS get downloaded on the fly so make this a future.
      notamPage = future.pages.length;
      future.pages.add(FutureBuilder(future: Storage().notam.getSync(future.showDestination.locationID),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              Weather? w2 = snapshot.data;
              if (w2 != null) {
                return SingleChildScrollView(child:Text("NOTAMs - ${(w2 as Notam).text}"));
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
          const ListTile(title: Text("SUA")),
          for(Saa s in future.saa)
            ListTile(title: Text(s.designator),
                subtitle: Text(s.toString())),
        ],
      ));
    }

    if(winds != null) {
      windsPage = future.pages.length;
      WindsAloft wa = winds as WindsAloft;
      future.pages.add(
        ListView(children: [
          ListTile(title: Text(winds.toString())),
          if(sounding != null) ListTile(leading: sounding),
          for((String, String) wl in wa.toList()) ListTile(
            leading: Text(wl.$1),
            title: Text(wl.$2),
          ),
        ])
      );
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
          Expanded(flex: 1, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child:Row(children: [
            // top action buttons
            TextButton(
              child: const Text("->D"),
              onPressed: () {
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
                Storage().route.insertWaypoint(Waypoint(future.showDestination));
                Toastification().show(context: context, description: Text("Added ${future.showDestination.facilityName} to Plan"), autoCloseDuration: const Duration(seconds: 3), icon: const Icon(Icons.info));
                Navigator.of(context).pop(); // hide bottom sheet
              },
            ),
            if(future.showDestination is AirportDestination)
              TextButton(
                child: const Text("Plates"),
                onPressed: () { // go to plate
                  if(future.showDestination is AirportDestination) {
                    Storage().settings.setCurrentPlateAirport(future.showDestination.locationID);
                    UserDatabaseHelper.db.addRecent(future.showDestination);
                  }
                  MainScreenState.gotoPlate();
                  Navigator.of(context).pop(); // hide bottom sheet
                },
              ),

          ]))),
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

          // add various buttons that expand to diagram
          Expanded(flex: 1, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child:Row(mainAxisAlignment: MainAxisAlignment.end, children:[
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
            if(windsPage != null)
              TextButton(
                  child: const Text("Wind"),
                  onPressed: () => _controller.animateToPage(windsPage!)
            ),

            if(airportDiagram != null)
              TextButton(
                  child: const Text("AD"),
                  onPressed: () => {
                    showDialog(context: context,
                      builder: (BuildContext context) => Dialog.fullscreen(
                        child: Stack(children:[
                          InteractiveViewer(child: airportDiagram!),
                          Align(alignment: Alignment.topRight, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 36)))
                        ]
                      )
                    )),
                  }
              ),
            ]
            )),
          ),
      ],
      )]),
    );
  }
}
