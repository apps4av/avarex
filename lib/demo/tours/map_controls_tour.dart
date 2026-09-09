import 'package:avaremp/demo/demo_ids.dart';
import 'package:avaremp/demo/demo_step.dart';
import 'package:avaremp/demo/demo_tour.dart';

final DemoTour mapControlsTour = DemoTour(
  id: 'map_controls',
  title: 'Map controls',
  subtitle: 'Menu, Center, settings, charts, and layers',
  steps: [
    const GoTab.mapWith(caption: 'MAP is your moving map — ownship, charts, and overlays.'),
    const Narrate('The bottom row holds Menu, Center, and the chart tools.'),
    const Tap(DemoIds.mapMenu, caption: 'Menu opens Download, Aircraft, Help, and the rest of the drawer.'),
    Wait.seconds(2),
    const Tap(DemoIds.drawerDownload, caption: 'Download is where you add charts and databases.'),
    Wait.seconds(2),
    const Pop(),
    GoTab.map,
    const Tap(DemoIds.mapCenter, caption: 'Center recenters the map on ownship. Long-press zooms all the way in.'),
    Wait.seconds(1),
    const Tap(DemoIds.mapSettings, caption: 'Map settings: measure, rubber banding, alerts, north-up or track-up.'),
    Wait.seconds(2),
    const Pop(),
    const Tap(DemoIds.mapChart, caption: 'Pick the chart type — sectional, TAC, IFR, and more.'),
    Wait.seconds(2),
    const Pop(),
    const Tap(DemoIds.mapLayers, caption: 'Layers control weather, traffic, and other overlays.'),
    Wait.seconds(2),
    const Pop(),
    const Narrate('That is the MAP tab. Use Menu anytime you need tools that are not on the map.'),
  ],
);
