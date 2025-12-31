import 'package:auto_size_text/auto_size_text.dart';
import 'package:avaremp/ai/ai_screen.dart';
import 'package:avaremp/data/business_database_helper.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:avaremp/main_screen.dart';
import 'package:avaremp/map_screen.dart';
import 'package:avaremp/place/saa.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/destination/nav.dart';
import 'package:avaremp/utils/toast.dart';
import 'package:avaremp/weather/notam.dart';
import 'package:avaremp/weather/sounding.dart';
import 'package:avaremp/weather/taf.dart';
import 'package:avaremp/plan/waypoint.dart';
import 'package:avaremp/weather/weather.dart';
import 'package:avaremp/weather/winds_aloft.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

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

  final Destination _destination;
  Destination show;
  List<Saa> saa = [];
  List<Destination> businesses = [];
  List<NavDestination>? navs;

  LongPressFuture(this._destination) : show =
      Destination( // GPS default then others
          locationID: Destination.toSexagesimal(
              _destination.coordinate),
              type: Destination.typeGps,
              facilityName: Destination.typeGps,
              coordinate: _destination.coordinate);

  // get everything from database about this destination
  Future<void> _getAll() async {
    show = await DestinationFactory.make(_destination);
    navs = await MainDatabaseHelper.db.findNearestVOR(_destination.coordinate);
    saa = await MainDatabaseHelper.db.getSaa(_destination.coordinate);
    businesses = await BusinessDatabaseHelper.db.findBusinesses(_destination);
  }

  Future<LongPressFuture> getAll() async {
    await _getAll();
    return this;
  }
}

class LongPressScreenState extends State<LongPressScreen> {

  int _index = 0;
  static const List<String> labels = ["Main", "AD", "METAR", "NOTAM", "SUA", "Wind", "ST", "Business"];

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

    double width = Constants.screenWidth(context);
    double height = Constants.screenHeight(context);
    Destination showDestination = future.show;

    // general direction from where we are
    GeoCalculations geo = GeoCalculations();
    LatLng ll = LatLng(Storage().position.latitude, Storage().position.longitude);
    double distance = geo.calculateDistance(ll, widget.destinations[0].coordinate);
    double bearing = geo.calculateBearing(ll, widget.destinations[0].coordinate);
    String direction = ("${distance.round()} ${GeoCalculations.getGeneralDirectionFrom(bearing, Storage().area.variation)}");
    String facility = showDestination.facilityName.length > 16 ? showDestination.facilityName.substring(0, 16) : showDestination.facilityName;
    List<Widget?> pages = List.generate(labels.length, (index) => null);
    String label = "$facility (${showDestination.locationID}) $direction${showDestination.elevation != null ? "; EL ${showDestination.elevation!.round()}" : ""}";

    if(showDestination is AirportDestination) {

      pages[labels.indexOf("Main")] = Airport.parse(showDestination);

      // made up airport dia
      Widget ad = Airport.runwaysWidget(showDestination, width, height, context);
      pages[labels.indexOf("AD")] = InteractiveViewer(maxScale: 5, child: ad);

      Weather? w = Storage().metar.get(showDestination.locationID);
      Weather? w1 = Storage().taf.get(showDestination.locationID);
      if(w != null || w1 != null) {
        pages[labels.indexOf("METAR")] = ListView(children: [
          w != null ? ListTile(title: const Text("METAR"),
            subtitle: Text((w as Metar).text),
            leading: Icon(Icons.circle_outlined, color: w.getColor(), size: 32),)
              : Container(),
          w1 != null ? ListTile(title: const Text("TAF"),
              subtitle: Text((w1 as Taf).text),
              leading: w1.getIcon())
              : Container(),
        ]);
      }
      pages[labels.indexOf("NOTAM")] = FutureBuilder(future: Storage().notam.getSync(showDestination.locationID),
        builder: (context, snapshot) { // notmas are downloaded when not in cache and can be slow to download so do async
          if (snapshot.hasData) {
            if(snapshot.data != null) {
              Notam n = snapshot.data as Notam;

              List<String> lines = n.toString().split("\n");
              // remove empty lines
              lines = lines.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
              String title = lines.removeAt(0); // first line is title
              return ListView(
                children: [
                  ListTile(title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700),)),
                  for(String v in lines)
                    ListTile(leading: const Icon(Icons.warning_amber), title: Text(v)),
                ]);
            }
            else {
              return Container();
            }
          }
          else {
            return const ListTile(leading: CircularProgressIndicator());
          }
        });
    }
    else {
      String type = "${showDestination.type}\n\n";
      int gridColumns = Nav.columns;
      List<Widget> values = [];
      if(future.navs != null) {
        for (NavDestination nav in future.navs!) {
          values.addAll(Nav.getVorLine(nav).map((String s) => Text(s)));
        }
        Widget grid = GridView.count(
          crossAxisCount: gridColumns,
          scrollDirection: Axis.horizontal,
          mainAxisSpacing: 20,
          children: values,
        );
        pages[labels.indexOf("Main")] =
            Padding(padding: const EdgeInsets.all(10), child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 1, child: Text(type),),
              Expanded(flex: 4, child: grid,)
            ])
            );
      }
    }

    Weather? winds;
    String? station = WindsCache.locateNearestStation(showDestination.coordinate);
    if(station != null) {
      winds = Storage().winds.get("${station}06H"); // 6HR wind
      if(winds != null) {
        WindsAloft wa = winds as WindsAloft;
        pages[labels.indexOf("Wind")] = ListView(children: [
          ListTile(title: Text(winds.toString())),
          for((String, String) wl in wa.toList())
            ListTile(leading: Text(wl.$1), title: Text(wl.$2)),
        ]);
      }
    }

    pages[labels.indexOf("ST")] = Sounding.getSoundingImage(showDestination.coordinate, context);

    // SUA for every press
    if(future.saa.isNotEmpty) {
      pages[labels.indexOf("SUA")] = ListView(
        children: [
          for(Saa s in future.saa)
            Padding(padding: const EdgeInsets.fromLTRB(10, 10, 10, 10), child: s.toWidget())
        ],
      );
    }

    if(future.businesses.isNotEmpty) {
      pages[labels.indexOf("Business")] = ListView(
        children: [
          for(Destination b in future.businesses)
            Padding(padding: const EdgeInsets.fromLTRB(10, 10, 10, 10), child:
              ListTile(title: Text(b.facilityName),
                trailing: Constants.shouldShowProServices ? TextButton(onPressed: () {
                  if(Constants.shouldShowProServices) {
                    String query = "What are the address, telephone number, website, services (flight training, car rental, courtesy car, maintenance, fuel) at ${b
                        .facilityName} (${b.locationID})";
                    if(mounted) {
                      AiScreenState.teleportToAiScreen(context, query);
                    }
                  }
                },
                child: Text("Details"),
              ) : Container()
              ))
        ],
      );
    }

    return Scaffold(
        appBar: AppBar(
          title: AutoSizeText(label, maxLines: 2, minFontSize: 10, maxFontSize: 16, style: const TextStyle(fontWeight: FontWeight.w700),),
        ),
        body: Column(children: [
          Expanded(flex: 1, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child:Row(children: [
            // top action buttons
            TextButton(
              child: const Text("\u2192D"),
              onPressed: () {
                Storage().setDestination(showDestination);
                if(showDestination is AirportDestination) {
                  Storage().settings.setCurrentPlateAirport(showDestination.locationID);
                }
                MapScreenState.showOnMap(showDestination.coordinate);
                MainScreenState.gotoMap();
                Navigator.of(context).pop(); // hide bottom sheet
              },
            ),
            TextButton(
              child: const Text("+Plan"),
              onPressed: () {
                Storage().route.insertWaypoint(Waypoint(showDestination));
                Toast.showToast(context, "Added ${showDestination.facilityName} to Plan", null, 3);
                Navigator.of(context).pop(); // hide bottom sheet
              },
            ),

            if(showDestination is AirportDestination)
              TextButton(
                child: const Text("Plates"),
                onPressed: () { // go to plate
                  Storage().settings.setCurrentPlateAirport(showDestination.locationID);
                  UserDatabaseHelper.db.addRecent(showDestination);
                  MainScreenState.gotoPlate();
                  Navigator.of(context).pop(); // hide bottom sheet
                },
              ),
          ]))),
          // various info
          if(widget.destinations.length > 1)
            const Row( // nearby destinations
                children: <Widget>[
                  Expanded(flex: 1, child: Divider()),
                  Text(" Nearby ", style: TextStyle(fontSize: 10)),
                  Expanded(flex: 16, child: Divider()),
                ]
            ),
          if(widget.destinations.length > 1)
            Expanded(flex: 1, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child:
            Row(children: [
              for (int index = 1; index < widget.destinations.length; index++)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacementNamed("/popup", arguments: [widget.destinations[index]]);
                  },
                  child: Text(widget.destinations[index].locationID),
                ),
            ])
            )),
          Row( // nearby destinations
              children: <Widget>[
                const Expanded(flex: 1, child: Divider()),
                Text(" ${labels[_index]} ", style: const TextStyle(fontSize: 10)),
                const Expanded(flex: 16, child: Divider()),
              ]
          ),
          Expanded(flex: 10, child: pages[_index] == null ? Container() : pages[_index]!),
          // add various buttons that expand to diagram
          Expanded(flex: 1, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child:Row(mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (int i = 0; i < labels.length; i++)
                if (pages[i] != null)
                  TextButton(
                    child: Text(labels[i]),
                    onPressed: () => setState(() => _index = i)
                  ),
            ])
        ))
    ]));
  }
}
