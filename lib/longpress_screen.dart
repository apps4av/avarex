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
      Destination(
          locationID: Destination.toSexagesimal(
              _destination.coordinate),
              type: Destination.typeGps,
              facilityName: Destination.typeGps,
              coordinate: _destination.coordinate);

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

    if (null == future) {
      return const Center(child: CircularProgressIndicator());
    }

    double width = Constants.screenWidth(context);
    double height = Constants.screenHeight(context);
    Destination showDestination = future.show;

    GeoCalculations geo = GeoCalculations();
    LatLng ll = LatLng(Storage().position.latitude, Storage().position.longitude);
    double distance = geo.calculateDistance(ll, widget.destinations[0].coordinate);
    double bearing = geo.calculateBearing(ll, widget.destinations[0].coordinate);
    String direction = ("${distance.round()} ${GeoCalculations.getGeneralDirectionFrom(bearing, Storage().area.variation)}");
    String facility = showDestination.facilityName.length > 16 ? showDestination.facilityName.substring(0, 16) : showDestination.facilityName;
    List<Widget?> pages = List.generate(labels.length, (index) => null);
    String label = "$facility (${showDestination.locationID}) $direction${showDestination.elevation != null ? "; EL ${showDestination.elevation!.round()}" : ""}";

    if (showDestination is AirportDestination) {

      pages[labels.indexOf("Main")] = Airport.parse(showDestination);

      Widget ad = Airport.runwaysWidget(showDestination, width, height, context);
      pages[labels.indexOf("AD")] = InteractiveViewer(maxScale: 5, child: ad);

      Metar? metar = Storage().metar.get(showDestination.locationID) as Metar?;
      Taf? taf = Storage().taf.get(showDestination.locationID) as Taf?;
      if (metar != null || taf != null) {
        pages[labels.indexOf("METAR")] = ListView(
          padding: const EdgeInsets.all(8),
          children: [
            if (metar != null)
              Card(
                child: ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: metar.getColor().withAlpha(50),
                      shape: BoxShape.circle,
                      border: Border.all(color: metar.getColor(), width: 2),
                    ),
                    child: Center(
                      child: Text(
                        "M",
                        style: TextStyle(fontWeight: FontWeight.bold, color: metar.getColor()),
                      ),
                    ),
                  ),
                  title: const Text("METAR", style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(metar.text),
                  ),
                ),
              ),
            if (taf != null)
              Card(
                child: ListTile(
                  leading: taf.getIcon(),
                  title: const Text("TAF", style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(taf.text),
                  ),
                ),
              ),
          ],
        );
      }
      pages[labels.indexOf("NOTAM")] = FutureBuilder(
        future: Storage().notam.getSync(showDestination.locationID),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            if (snapshot.data != null) {
              Notam n = snapshot.data as Notam;

              List<String> lines = n.toString().split("\n");
              lines = lines.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
              String title = lines.removeAt(0);
              return ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.info, color: Theme.of(context).colorScheme.onPrimaryContainer),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          Text(
                            "${lines.length}",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (String v in lines)
                    Card(
                      child: ListTile(
                        leading: Icon(Icons.warning_amber, color: Colors.orange.shade700),
                        title: Text(v, style: const TextStyle(fontSize: 13)),
                      ),
                    ),
                ],
              );
            } else {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, size: 48, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 8),
                    Text("No NOTAMs", style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                  ],
                ),
              );
            }
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      );
    } else {
      String type = "${showDestination.type}\n\n";
      if (future.navs != null && future.navs!.isNotEmpty) {
        List<Widget> navRows = [];
        for (NavDestination nav in future.navs!) {
          List<String> vorData = Nav.getVorLine(nav);
          navRows.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        vorData[0],
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          vorData[1],
                          style: const TextStyle(fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        vorData[2],
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    vorData[3],
                    style: const TextStyle(fontSize: 16, fontFamily: 'monospace', letterSpacing: 2),
                  ),
                ],
              ),
            ),
          );
        }
        Widget navList = ListView(
          children: navRows,
        );
        pages[labels.indexOf("Main")] =
            Padding(padding: const EdgeInsets.all(10), child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(type, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Expanded(child: navList),
            ])
            );
      }
    }

    Weather? winds;
    String? station = WindsCache.locateNearestStation(showDestination.coordinate);
    if (station != null) {
      winds = Storage().winds.get("${station}06H");
      if (winds != null) {
        WindsAloft wa = winds as WindsAloft;
        pages[labels.indexOf("Wind")] = ListView(
          padding: const EdgeInsets.all(8),
          children: [
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.air, color: Theme.of(context).colorScheme.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        winds.toString(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for ((String, String) wl in wa.toList())
              Card(
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(wl.$1, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  title: Text(wl.$2),
                ),
              ),
          ],
        );
      }
    }

    pages[labels.indexOf("ST")] = Sounding.getSoundingImage(showDestination.coordinate, context);

    if (future.saa.isNotEmpty) {
      pages[labels.indexOf("SUA")] = ListView(
        padding: const EdgeInsets.all(8),
        children: [
          for (Saa s in future.saa)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: s.toWidget(),
              ),
            ),
        ],
      );
    }

    if (future.businesses.isNotEmpty) {
      pages[labels.indexOf("Business")] = ListView(
        padding: const EdgeInsets.all(8),
        children: [
          for (Destination b in future.businesses)
            Card(
              child: ListTile(
                leading: Icon(Icons.business, color: Theme.of(context).colorScheme.primary),
                title: Text(b.facilityName),
                trailing: Constants.shouldShowProServices
                    ? TextButton(
                        onPressed: () {
                          if (Constants.shouldShowProServices) {
                            String query = "What are the address, telephone number, website, services (flight training, car rental, courtesy car, maintenance, fuel) at ${b.facilityName} (${b.locationID})";
                            if (mounted) {
                              AiScreenState.teleportToAiScreen(context, query);
                            }
                          }
                        },
                        child: const Text("Details"),
                      )
                    : null,
              ),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: AutoSizeText(label, maxLines: 2, minFontSize: 10, maxFontSize: 16, style: const TextStyle(fontWeight: FontWeight.w700),),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  TextButton(
                    child: const Text("\u2192D", style: TextStyle(fontSize: 40),),
                    onPressed: () {
                      Storage().setDestination(showDestination);
                      if (showDestination is AirportDestination) {
                        Storage().settings.setCurrentPlateAirport(showDestination.locationID);
                      }
                      MapScreenState.showOnMap(showDestination.coordinate);
                      MainScreenState.gotoMap();
                      Navigator.of(context).pop();
                    },
                  ),
                  TextButton(
                    child: const Text("+Plan"),
                    onPressed: () {
                      Storage().route.insertWaypoint(Waypoint(showDestination));
                      Toast.showToast(context, "Inserted ${showDestination.facilityName} to Plan", null, 2);
                      Navigator.of(context).pop();
                      if(Storage().planSearch) {
                        Storage().planSearch = false;
                        MainScreenState.gotoPlan();
                      }
                    },
                  ),
                  TextButton(
                    child: const Text("\u2193Plan"),
                    onPressed: () {
                      Storage().route.addWaypoint(Waypoint(showDestination));
                      Toast.showToast(context, "Appended ${showDestination.facilityName} to Plan", null, 2);
                      Navigator.of(context).pop();
                    },
                  ),
                  if (showDestination is AirportDestination)
                    TextButton(
                      child: const Text("Plates"),
                      onPressed: () {
                        Storage().settings.setCurrentPlateAirport(showDestination.locationID);
                        UserDatabaseHelper.db.addRecent(showDestination);
                        MainScreenState.gotoPlate();
                        Navigator.of(context).pop();
                      },
                    ),
                ],
              ),
            ),
          ),
          if (widget.destinations.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Expanded(flex: 1, child: Divider()),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Text(
                      "Nearby (${widget.destinations.length - 1})",
                      style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                  const Expanded(flex: 16, child: Divider()),
                ],
              ),
            ),
          if (widget.destinations.length > 1)
            SizedBox(
              height: 40,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    for (int index = 1; index < widget.destinations.length; index++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: ActionChip(
                          avatar: DestinationFactory.getIcon(widget.destinations[index].type, Theme.of(context).colorScheme.primary),
                          label: Text(widget.destinations[index].locationID, style: const TextStyle(fontSize: 12)),
                          onPressed: () {
                            Navigator.of(context).pushReplacementNamed("/popup", arguments: [widget.destinations[index]]);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            flex: 10,
            child: pages[_index] == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline, size: 48, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 8),
                        Text("No data available", style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                      ],
                    ),
                  )
                : pages[_index]!,
          ),
          Padding(
            padding: const EdgeInsets.all(5),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (int i = 0; i < labels.length; i++)
                    if (pages[i] != null)
                      TextButton(
                        style: _index == i
                            ? TextButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primaryContainer)
                            : null,
                        child: Text(labels[i]),
                        onPressed: () => setState(() => _index = i),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
