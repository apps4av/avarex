import 'demo_tour.dart';
import 'tours/build_plan_tour.dart';
import 'tours/checklists_tour.dart';
import 'tours/find_destination_tour.dart';
import 'tours/map_controls_tour.dart';
import 'tours/write_notes_tour.dart';

/// All playable demos.
///
/// To add a topic:
/// 1. Wrap the control with `DemoTarget(id: DemoIds.foo, child: ...)`.
/// 2. Add `DemoIds.foo` in [demo_ids.dart].
/// 3. Write a [DemoTour] in `lib/demo/tours/`.
/// 4. Append it to [tours] below.
class DemoRegistry {
  static final List<DemoTour> tours = <DemoTour>[
    mapControlsTour,
    buildPlanTour,
    findDestinationTour,
    writeNotesTour,
    checklistsTour,
  ];

  static DemoTour? byId(String id) {
    for (final DemoTour tour in tours) {
      if (tour.id == id) {
        return tour;
      }
    }
    return null;
  }
}
