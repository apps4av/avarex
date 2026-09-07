import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/demo/demo_engine.dart';
import 'package:avaremp/demo/demo_ids.dart';
import 'package:avaremp/demo/demo_step.dart';
import 'package:avaremp/demo/demo_tour.dart';
import 'package:avaremp/demo/demo_target.dart';
import 'package:avaremp/io/gps.dart';
import 'package:avaremp/storage.dart';

final DemoTour findDestinationTour = DemoTour(
  id: 'find_destination',
  title: 'Find a destination',
  subtitle: 'Search, then open airport details',
  steps: [
    Prepare(() async {
      try {
        final nearest = await MainDatabaseHelper.db.findNearestAirportsWithRunways(
          Gps.toLatLng(Storage().position),
          0,
        );
        if (nearest.isNotEmpty) {
          DemoEngine.instance.sampleIdent = nearest.first.locationID;
        }
      } catch (_) {}
    }),
    const GoTab.findWith(caption: 'FIND searches airports, navaids, fixes, and recent destinations.'),
    const Narrate('Use the filters for Recent and Nearest, or type an identifier.'),
    const Tap(DemoIds.findNearest, caption: 'Nearest lists airports around ownship.'),
    Wait.seconds(1),
    TypeText(
      DemoIds.findSearch,
      'KBOS',
      textOf: () => DemoEngine.instance.sampleIdent,
      caption: 'Type an identifier to search the aviation database.',
    ),
    Wait.seconds(2),
    Prepare(() async {
      if (!DemoTargets.isMounted(DemoIds.findFirstResult)) {
        DemoEngine.instance.overlay.value = DemoEngine.instance.overlay.value.copyWith(
          caption:
              'No results — download Databases from Menu → Download so FIND and PLAN can resolve identifiers.',
        );
      }
    }),
    const Tap(
      DemoIds.findFirstResult,
      caption: 'Tap a result to open the destination popup — weather, plates, and plan actions.',
      timeout: Duration(seconds: 5),
      after: Duration(seconds: 2),
    ),
    const Pop(),
    const Narrate('That is FIND. From the popup you can add the destination to the plan or open plates.'),
  ],
);
