import 'package:auto_size_text/auto_size_text.dart';
import 'package:avaremp/ai/ai_screen.dart';
import 'package:avaremp/business/airport_businesses_gate.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:avaremp/main_screen.dart';
import 'package:avaremp/map_screen.dart';
import 'package:avaremp/place/saa.dart';
import 'package:avaremp/place/airspace_3d_view.dart';
import 'package:avaremp/plan/hold_tab.dart';
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

class LongPressScreenState extends State<LongPressScreen> {

  int _index = 0;
  static const List<String> labels = ["Main", "AD", "METAR", "NOTAM", "SUA", "Wind", "3D", "ST", "Business"];

  late List<Destination> _nearby;
  late Destination _show;
  List<NavDestination>? _navs;
  List<Saa> _saa = [];
  bool _ready = false;
  int _loadId = 0;

  @override
  void initState() {
    super.initState();
    _nearby = List<Destination>.of(widget.destinations);
    _show = _nearby.first;
    _load();
  }

  /// The sheet is already up. Find what was under the finger, then load the
  /// airport record, nearest VORs, and special-use airspace together.
  Future<void> _load() async {
    final int loadId = ++_loadId;
    List<Destination> nearby = _nearby;
    if (nearby.length == 1 && Destination.isGps(nearby.first.type)) {
      nearby = await MainDatabaseHelper.db.findNear(nearby.first.coordinate);
      if (!mounted || loadId != _loadId) {
        return;
      }
      setState(() {
        _nearby = nearby;
        _show = nearby.first;
      });
    }
    final Destination primary = nearby.first;
    final List<Object> details = await Future.wait([
      DestinationFactory.make(primary),
      MainDatabaseHelper.db.findNearestVOR(primary.coordinate),
      MainDatabaseHelper.db.getSaa(primary.coordinate),
    ]);
    if (!mounted || loadId != _loadId) {
      return;
    }
    setState(() {
      _show = details[0] as Destination;
      _navs = details[1] as List<NavDestination>;
      _saa = details[2] as List<Saa>;
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _makeContent();
  }

  Widget _makeContent() {

    double width = Constants.screenWidth(context);
    double height = Constants.screenHeight(context);
    Destination showDestination = _show;

    GeoCalculations geo = GeoCalculations();
    LatLng ll = LatLng(Storage().position.latitude, Storage().position.longitude);
    double distance = geo.calculateDistance(ll, _nearby.first.coordinate);
    double bearing = geo.calculateBearing(ll, _nearby.first.coordinate);
    String direction = ("${distance.round()} ${GeoCalculations.getGeneralDirectionFrom(bearing, Storage().area.variation)}");
    String facility = showDestination.facilityName.length > 16 ? showDestination.facilityName.substring(0, 16) : showDestination.facilityName;
    List<Widget?> pages = List.generate(labels.length, (index) => null);
    String label = "$facility (${showDestination.locationID}) $direction${showDestination.elevation != null ? "; EL ${showDestination.elevation!.round()}" : ""}";

    if (_ready) {
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
                        leading: Constants.shouldShowProServices
                            ? IconButton(
                                icon: const Icon(Icons.translate),
                                tooltip: "Translate",
                                onPressed: () {
                                  String query = "Translate this NOTAM for ${showDestination.facilityName} (${showDestination.locationID}) into plain English:\n\n$v";
                                  AiScreenState.teleportToAiScreen(context, query);
                                },
                              )
                            : null,
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
                    Text("No NOTAMs / Unable to Download", style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                  ],
                ),
              );
            }
        },
      );
    } else {
      if (_navs != null && _navs!.isNotEmpty) {
        List<Widget> navRows = [];
        for (NavDestination nav in _navs!) {
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
        pages[labels.indexOf("Main")] = Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: navList,
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

    pages[labels.indexOf("3D")] = Airspace3DView(
      center: showDestination.coordinate,
      ownship: Storage().gpsChange,
      showPressPoint: true,
      showTerrain: true,
    );
    pages[labels.indexOf("ST")] = Sounding.getSoundingImage(showDestination.coordinate, context);

    if (_saa.isNotEmpty) {
      pages[labels.indexOf("SUA")] = ListView(
        padding: const EdgeInsets.all(8),
        children: [
          for (Saa s in _saa)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: s.toWidget(),
              ),
            ),
        ],
      );
    }

    // Build the Business tab for any airport. All cloud/Firebase logic lives
    // in AirportBusinessesTab; this screen only decides whether the platform
    // supports the feature. It is never gated by Pro.
    final bool isAirport = showDestination is AirportDestination;
    if (isAirport && AirportBusinessesGate.available) {
      pages[labels.indexOf("Business")] = AirportBusinessesTab(
          airport: showDestination.locationID,
          origin: showDestination.coordinate);
    }

    if (!isAirport) {
      final int main = labels.indexOf("Main");
      final Widget? mainPage = pages[main];
      final String facility = showDestination.facilityName.trim();
      final String ident = facility.isNotEmpty &&
              facility.toUpperCase() != showDestination.type.toUpperCase()
          ? facility
          : showDestination.locationID.trim();
      pages[main] = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "$ident, ${showDestination.type}",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: () => HoldSetup.open(
                    context,
                    fix: showDestination.coordinate,
                    name: showDestination.locationID,
                  ),
                  child: const Text("Hold"),
                ),
              ],
            ),
          ),
          Expanded(
            child: mainPage ?? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.info_outline, size: 48, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 8),
                  Text("No data available", style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                ],
              ),
            ),
          ),
        ],
      );
    }
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
          if (_nearby.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Expanded(flex: 1, child: Divider()),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: Text(
                      "Nearby (${_nearby.length - 1})",
                      style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline),
                    ),
                  ),
                  const Expanded(flex: 16, child: Divider()),
                ],
              ),
            ),
          if (_nearby.length > 1)
            SizedBox(
              height: 40,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    for (int index = 1; index < _nearby.length; index++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: ActionChip(
                          avatar: DestinationFactory.getIcon(_nearby[index].type, Theme.of(context).colorScheme.primary),
                          label: Text(_nearby[index].locationID, style: const TextStyle(fontSize: 12)),
                          onPressed: () {
                            Navigator.of(context).pushReplacementNamed("/popup", arguments: [_nearby[index]]);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            flex: 10,
            child: !_ready
                ? const Center(child: CircularProgressIndicator())
                : pages[_index] == null
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
