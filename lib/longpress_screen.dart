import 'package:auto_size_text/auto_size_text.dart';
import 'package:avaremp/ai/ai_screen.dart';
import 'data/main_database_helper.dart';
import 'data/aeronautical_database.dart';
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
import 'package:avaremp/weather/open_meteo_winds.dart';
import 'package:avaremp/weather/open_meteo_credentials.dart';
import 'package:avaremp/weather/flybrief_notams.dart';
import 'package:avaremp/weather/flybrief_store.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'aip/aip_aero.dart';
import 'destination/airport.dart';
import 'constants.dart';
import 'package:avaremp/destination/destination.dart';
import 'weather/metar.dart';
import 'weather/decoded_metar_view.dart';
import 'ofm/ofm_constants.dart';

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
    navs = await AeronauticalDatabase.instance.findNearestVOR(_destination.coordinate);
    saa = await MainDatabaseHelper.db.getSaa(_destination.coordinate);
  }

  Future<LongPressFuture> getAll() async {
    await _getAll();
    return this;
  }
}

class LongPressScreenState extends State<LongPressScreen> {

  int _index = 0;
  static const List<String> labels = ["Main", "AD", "METAR", "NOTAM", "SUA", "Wind", "ST"];

  late Future<LongPressFuture> _loadFuture;

  // Opens the airport's official-AIP index page on aip.aero in the platform
  // browser. aip.aero links straight to the country's official AIP; we only
  // hand off the URL (no data is fetched or cached by the app).
  Future<void> _openAip(BuildContext context, String icao) async {
    final uri = Uri.parse(AipAero.urlForAirport(icao));
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && messenger != null) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not open $uri')),
        );
      }
    } catch (e) {
      if (messenger != null) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not open $uri')),
        );
      }
    }
  }

  // Gathers NOTAM lines for a destination. Uses the built-in (US FAA) source
  // first; when it yields nothing (e.g. in Europe) it falls back to FlyBrief's
  // per-country georeferenced NOTAMs (offline-first). Returns the display
  // title, the NOTAM lines, and an optional data-source attribution.
  Future<(String, List<String>, String?)> _gatherNotams(
      Destination dest) async {
    // 1) Built-in source (FAA).
    final Notam? n = await Storage().notam.getSync(dest.locationID) as Notam?;
    if (n != null) {
      var lines = n.toString().split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      if (lines.isNotEmpty) {
        final title = lines.removeAt(0);
        return (title, lines, null);
      }
    }
    // 2) FlyBrief fallback (Europe / covered countries), offline-first.
    final fb = await FlybriefStore.nearbyForPoint(
        dest.coordinate.latitude, dest.coordinate.longitude);
    if (fb.isNotEmpty) {
      final lines = fb.map((e) => e.toLine()).toList();
      return ('NOTAMs near ${dest.locationID}', lines, FlybriefNotams.attribution);
    }
    return ('', <String>[], null);
  }

  @override
  void initState() {
    super.initState();
    _loadFuture = LongPressFuture(widget.destinations[0]).getAll();
  }

  // Renders the winds-aloft list for a WindsAloft, with an optional data-source
  // attribution footer (used for the Open-Meteo fallback).
  Widget _windsList(BuildContext context, WindsAloft wa, String? attribution) {
    return ListView(
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
                    wa.toString(),
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
        if (attribution != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(attribution,
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {

    return FutureBuilder<LongPressFuture>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            Storage().setException('${snapshot.error}\n${snapshot.stackTrace}');
          }
          if (snapshot.hasData) {
            return _makeContent(snapshot.data);
          }
          return _makeContent(null);
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

    if (showDestination.source == 'OFM' || showDestination.source == 'openAIP') {
      final isOpenAip = showDestination.source == 'openAIP';
      pages[labels.indexOf("Main")] = ListView(
        padding: const EdgeInsets.all(12),
        children: [
          ListTile(
            title: Text(showDestination.facilityName),
            subtitle: Text('${showDestination.locationID} • ${showDestination.source} ${showDestination.sourceRegion} ${showDestination.sourceCycle}'),
          ),
          Text('Coordinates: ${showDestination.coordinate.latitude.toStringAsFixed(6)}, ${showDestination.coordinate.longitude.toStringAsFixed(6)}'),
          if (showDestination.elevation != null) Text('Elevation: ${showDestination.elevation!.round()} ft'),
          if (showDestination is AirportDestination) ...[
            const SizedBox(height: 12),
            Text('Runways', style: Theme.of(context).textTheme.titleMedium),
            for (final runway in showDestination.runways)
              Text('${runway['RunwayID']} • ${(runway['Length'] as num).round()} x ${(runway['Width'] as num).round()} ft • ${runway['Surface']}'),
            const SizedBox(height: 12),
            Text('Communications', style: Theme.of(context).textTheme.titleMedium),
            for (final frequency in showDestination.frequencies)
              Text('${frequency['Use']}: ${frequency['Frequency']}'),
          ],
          const SizedBox(height: 16),
          Text(isOpenAip ? 'Data © openAIP, CC BY-NC 4.0' : OfmConstants.attribution,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(isOpenAip
              ? 'openAIP is community-maintained supplementary data and is not certified for primary navigation or flight planning.'
              : OfmConstants.disclaimer),
          if (!isOpenAip) const Text(OfmConstants.corrections),
          if (showDestination is AirportDestination &&
              AipAero.hasChartsFor(showDestination.locationID)) ...[
            const Divider(height: 24),
            Card(
              child: ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text('Official AIP & approach charts'),
                subtitle: Text(
                    'Open ${showDestination.locationID} on aip.aero — links to the '
                    'country\u2019s official AIP (VFR/IFR charts, aerodrome data). '
                    'External site; verify AIRAC currency before flight.'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => _openAip(context, showDestination.locationID),
              ),
            ),
          ],
        ],
      );
      if (showDestination is AirportDestination) {
        final Metar? metar = Storage().metar.get(showDestination.locationID) as Metar?;
        final Taf? taf = Storage().taf.get(showDestination.locationID) as Taf?;
        if (metar != null || taf != null) {
          pages[labels.indexOf("METAR")] = ListView(
            padding: const EdgeInsets.all(8),
            children: [
              if (metar != null) Card(child: ListTile(
                leading: metar.getIcon(),
                title: const Text('METAR'),
                subtitle: Text(metar.text),
              )),
              if (metar != null) DecodedMetarView(metar: metar),
              if (taf != null) Card(child: ListTile(
                leading: taf.getIcon(),
                title: const Text('TAF'),
                subtitle: Text(taf.text),
              )),
            ],
          );
        }
      }
    }

    if (showDestination.source != 'OFM' && showDestination.source != 'openAIP' && showDestination is AirportDestination) {

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
            if (metar != null) DecodedMetarView(metar: metar),
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
      pages[labels.indexOf("NOTAM")] = FutureBuilder<(String, List<String>, String?)>(
        future: _gatherNotams(showDestination),
        builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data;
            if (data != null && data.$2.isNotEmpty) {
              final String title = data.$1;
              final List<String> lines = data.$2;
              final String? attribution = data.$3;
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
                  if (Constants.shouldShowAi && lines.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text("Summarize"),
                          onPressed: () {
                            String query = "With the given NOTAMs below, what should I be aware of at ${showDestination.facilityName} (${showDestination.locationID}):\n\n${lines.join("\n")}";
                            AiScreenState.teleportToAiScreen(context, query);
                          },
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
                  if (attribution != null)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(attribution,
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
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
    // Distance (km) to the nearest US FB winds-aloft station. Beyond the US
    // coverage radius the FB product does not apply, so fall back to Open-Meteo.
    double? stationKm;
    if (station != null) {
      final LatLng? sc = WindsCache.stationLatLng(station);
      if (sc != null) {
        stationKm = OpenMeteoWinds.distanceKm(showDestination.coordinate, sc);
      }
      winds = Storage().winds.get("${station}06H");
    }
    final bool usCovered =
        winds != null && stationKm != null && stationKm <= OpenMeteoWinds.usStationMaxKm;

    if (usCovered) {
      pages[labels.indexOf("Wind")] = _windsList(context, winds as WindsAloft, null);
    }
    else {
      // Non-US (or no US data): fetch pressure-level winds from Open-Meteo.
      pages[labels.indexOf("Wind")] = FutureBuilder<WindsAloft?>(
        future: OpenMeteoCredentials().read().then((key) => OpenMeteoWinds.fetch(
              showDestination.coordinate,
              apiKey: key,
              station: showDestination.locationID,
            )),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final WindsAloft? wa = snapshot.data;
          if (wa == null) {
            // Last resort: show US data if we have any, else a message.
            if (winds != null) {
              return _windsList(context, winds as WindsAloft, null);
            }
            return Center(
              child: Text('Winds aloft unavailable for this location.',
                  style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            );
          }
          return _windsList(context, wa, OpenMeteoWinds.attribution);
        },
      );
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
