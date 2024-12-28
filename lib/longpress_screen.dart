import 'package:auto_size_text/auto_size_text.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/main_screen.dart';
import 'package:avaremp/saa.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/destination/nav.dart';
import 'package:avaremp/weather/notam.dart';
import 'package:avaremp/weather/sounding.dart';
import 'package:avaremp/weather/taf.dart';
import 'package:avaremp/plan/waypoint.dart';
import 'package:avaremp/weather/weather.dart';
import 'package:avaremp/weather/winds_aloft.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:toastification/toastification.dart';

import 'destination/airport.dart';
import 'constants.dart';
import 'package:avaremp/destination/destination.dart';
import 'weather/metar.dart';

class LongPressScreen extends StatefulWidget {
  final List<Destination> destinations;

  const LongPressScreen({super.key, required this.destinations});

  @override
  State<StatefulWidget> createState() => LongPressScreenState();

}

class LongPressFuture {

  Destination destination;
  Destination showDestination;
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

      pages.add(Airport.parseFrequencies(showDestination as AirportDestination));

    }
    else if(showDestination is NavDestination) {
      pages.add(Padding(padding: const EdgeInsets.all(10), child: Nav.mainWidget(Nav.parse(showDestination as NavDestination))));
    }
    else if(showDestination is FixDestination || showDestination is GpsDestination || showDestination is AirwayDestination || showDestination is ProcedureDestination) {
      List<NavDestination> navs = await MainDatabaseHelper.db.findNearestVOR(destination.coordinate);
      String type = "${showDestination.type}\n\n";
      int gridColumns = Nav.columns;
      List<Widget> values = [];
      for(NavDestination nav in navs) {
        values.addAll(Nav.getVorLine(nav).map((String s) => Padding(padding: const EdgeInsets.all(3), child: Text(s))));
      }
      Widget grid = GridView.count(
        crossAxisCount: gridColumns,
        scrollDirection: Axis.horizontal,
        children: values,
      );
      pages.add(
        Padding(padding: const EdgeInsets.all(10), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 1, child: Text(type),),
            Expanded(flex: 4, child: grid,)
        ])
        )
      );
    }
    // SUA for every press
    saa = await MainDatabaseHelper.db.getSaa(destination.coordinate);
  }

  Future<LongPressFuture> getAll() async {
    await _getAll();
    return this;
  }
}

class LongPressScreenState extends State<LongPressScreen> {

  int _index = 0;

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
    Widget? aDiagram;


    if (future.showDestination is AirportDestination) {
      // made up airport dia
      double width = Constants.screenWidth(context);
      double height = Constants.screenHeight(context);
      double dimensions = width > height ? height : width;
      Widget ad = Airport.runwaysWidget(future.showDestination as AirportDestination, dimensions, context);
      aDiagram = InteractiveViewer(constrained: false, child: ad);
    }

    int? metarPage;
    int? notamPage;
    int? saaPage;
    int? windsPage;
    int? adPage;
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
                return SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(10), child:Text("NOTAMs - ${(w2 as Notam).text}")));
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

    if(aDiagram != null) {
      adPage = future.pages.length;
      future.pages.add(aDiagram);
    }

    return Scaffold(
        appBar: AppBar(
          title: AutoSizeText(label, maxLines: 2, minFontSize: 10, maxFontSize: 16, style: const TextStyle(fontWeight: FontWeight.w700),),
        ),
        body: Column(children: [
            if(widget.destinations.length > 1)
              Expanded(flex: 1, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child:Row(children:
                List.generate(widget.destinations.length, (index) {
                  return TextButton(
                    onPressed: () {
                      Navigator.of(context).pushReplacementNamed("/popup", arguments: [widget.destinations[index]]);
                    },
                    child: Text(widget.destinations[index].locationID),
                  );
                }),
              )
              )),

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
          Expanded(flex: 8, child:
          SizedBox(width: 100000, child: future.pages[_index])),
          // add various buttons that expand to diagram
          Expanded(flex: 1, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child:Row(mainAxisAlignment: MainAxisAlignment.end, children:[
            if (future.pages.length > 1)
              TextButton(
                  child: const Text("Main"),
                  onPressed: () => setState(() => _index = 0)
              ),
            if(adPage != null)
              TextButton(
                  child: const Text("AD"),
                  onPressed: () => setState(() => _index = adPage!)
              ),
            if (metarPage != null)
              TextButton(
                  child: const Text("METAR"),
                  onPressed: () => setState(() => _index = metarPage!)
              ),
            if(notamPage != null)
              TextButton(
                child: const Text("NOTAM"),
                  onPressed: () => setState(() => _index = notamPage!)
              ),
            if(saaPage != null)
              TextButton(
                  child: const Text("SUA"),
                  onPressed: () => setState(() => _index = saaPage!)
              ),
            if(windsPage != null)
              TextButton(
                  child: const Text("Wind"),
                  onPressed: () => setState(() => _index = windsPage!)
            ),
          ])
      ))
    ]));
  }
}
