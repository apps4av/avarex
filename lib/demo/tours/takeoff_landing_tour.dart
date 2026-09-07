import 'package:avaremp/aircraft/aircraft_performance.dart';
import 'package:avaremp/demo/demo_engine.dart';
import 'package:avaremp/demo/demo_ids.dart';
import 'package:avaremp/demo/demo_step.dart';
import 'package:avaremp/demo/demo_tour.dart';
import 'package:avaremp/storage.dart';

final DemoTour takeoffLandingTour = DemoTour(
  id: 'takeoff_landing',
  title: 'Takeoff and landing',
  subtitle: 'Pick an airplane and read T/O and L/D distances',
  steps: [
    Prepare(() async {
      DemoEngine.instance.snapshotPerfAircraft();
      Storage().settings.setLastPerformanceAircraft(
        CommonAircraftData.cessna172sp.name,
      );
      if (Storage().settings.getAircraftIcon() == 'helicopter') {
        Storage().settings.setAircraftIcon('plane');
      }
    }),
    const GoTab.mapWith(
      caption: 'Takeoff and landing distances are under Aircraft and Performance.',
    ),
    const Tap(DemoIds.mapMenu, caption: 'Menu opens Aircraft and Performance under Flight.'),
    Wait.seconds(2),
    const Tap(
      DemoIds.drawerPerformance,
      caption: 'Aircraft and Performance has profiles, takeoff, landing, cruise, and weight and balance.',
      after: Duration(milliseconds: 1400),
    ),
    const Tap(
      DemoIds.perfAircraftPicker,
      caption: 'The dropdown picks a built-in or saved airplane. This demo uses a Cessna 172.',
    ),
    Wait.seconds(1),
    const Tap(
      DemoIds.perfC172,
      caption: 'Cessna 172S Skyhawk SP — a fixed-wing profile so the T/O and L/D tabs stay visible.',
      after: Duration(seconds: 2),
    ),
    const Tap(DemoIds.perfTakeoffTab, caption: 'T/O calculates takeoff ground roll and fifty-foot obstacle distance.'),
    Wait.seconds(1),
    const TypeText(
      DemoIds.perfTakeoffAltitude,
      '3000',
      caption: 'Enter pressure altitude. Results update as you type.',
    ),
    const Tap(
      DemoIds.perfTakeoffResults,
      caption: 'Ground roll, over fifty feet, and density altitude come from the POH tables.',
      after: Duration(seconds: 2),
    ),
    const Tap(DemoIds.perfLandingTab, caption: 'L/D is the same layout for landing distances.'),
    Wait.seconds(1),
    const TypeText(
      DemoIds.perfLandingAltitude,
      '3000',
      caption: 'Enter landing pressure altitude the same way.',
    ),
    const Tap(
      DemoIds.perfLandingResults,
      caption: 'Check ground roll and obstacle distance before you commit to a runway.',
      after: Duration(seconds: 2),
    ),
    const Narrate(
      'T/O and L/D are hidden when the selected airplane uses the helicopter icon. This demo does not change your saved aircraft.',
    ),
    const Pop(),
  ],
);
