import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/demo/demo_engine.dart';
import 'package:avaremp/demo/demo_ids.dart';
import 'package:avaremp/demo/demo_step.dart';
import 'package:avaremp/demo/demo_tour.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/io/gps.dart';
import 'package:avaremp/storage.dart';

final DemoTour buildPlanTour = DemoTour(
  id: 'build_plan',
  title: 'Build a plan',
  subtitle: 'Create a route from typed waypoints',
  steps: [
    Prepare(() async {
      await DemoEngine.instance.snapshotPlan();
      try {
        final List<Destination> nearest =
            await MainDatabaseHelper.db.findNearestAirportsWithRunways(
          Gps.toLatLng(Storage().position),
          0,
        );
        if (nearest.length >= 2) {
          DemoEngine.instance.sampleIdent = nearest[0].locationID;
          DemoEngine.instance.sampleRoute =
              '${nearest[0].locationID} ${nearest[1].locationID}';
        }
      } catch (_) {
        // Keep the default sample route.
      }
    }),
    const GoTab.planWith(caption: 'PLAN is where you build, edit, and file a route.'),
    const Narrate('These tabs switch between the waypoint list and plan tools.'),
    const Tap(DemoIds.planCreateTab, caption: 'Create turns a typed route into a plan.'),
    const Wait.seconds(1),
    TypeText(
      DemoIds.planRouteField,
      'KBOS KORH',
      textOf: () => DemoEngine.instance.sampleRoute,
      caption: 'Type waypoints separated by spaces.',
    ),
    const Tap(DemoIds.planCreateAsEntered, caption: 'Create As Entered uses the waypoints exactly as typed.'),
    const Wait.seconds(3),
    const Narrate('The waypoint list is your plan. Swipe to delete a leg; tap a row to make it active.'),
    const Narrate('Brief & File is for FAA filing — this demo does not file anything.'),
  ],
);
