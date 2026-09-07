import 'package:avaremp/demo/demo_engine.dart';
import 'package:avaremp/demo/demo_ids.dart';
import 'package:avaremp/demo/demo_step.dart';
import 'package:avaremp/demo/demo_tour.dart';
import 'package:avaremp/storage.dart';

final DemoTour instrumentTilesTour = DemoTour(
  id: 'instrument_tiles',
  title: 'Instrument tiles',
  subtitle: 'Move, add, remove, lock, and unlock map tiles',
  steps: [
    Prepare(() async {
      DemoEngine.instance.snapshotTiles();
      Storage().settings.setInstrumentsLocked(false);
      Storage().settings.setInstrumentVisible('GS,ALT,MT,PRV,NXT');
    }),
    const GoTab.mapWith(
      caption: 'Instrument tiles float on the map. Drag them, or use the arrow menu.',
    ),
    const Narrate('The dropdown at the top left sizes tiles, locks them, and shows or hides each one.'),
    const Tap(DemoIds.tilesMenu, caption: 'Open the tiles menu.'),
    Wait.seconds(1),
    const Tap(
      DemoIds.tilesLock,
      caption: 'Lock Tiles so a drag on the map cannot bump a tile by accident.',
    ),
    Wait.seconds(1),
    const Tap(DemoIds.tilesMenu, caption: 'Open the menu again to unlock.'),
    Wait.seconds(1),
    const Tap(
      DemoIds.tilesLock,
      caption: 'Unlock Tiles to move them again.',
    ),
    Wait.seconds(1),
    const Drag(
      DemoIds.tilesGs,
      dx: 72,
      dy: 96,
      caption: 'Drag any tile to a new spot. The position is saved for this orientation.',
      after: Duration(seconds: 1),
    ),
    const Tap(DemoIds.tilesMenu, caption: 'Each tile has a plus to show it or a minus to hide it.'),
    Wait.seconds(1),
    const Tap(
      DemoIds.tilesToggleGs,
      caption: 'Minus hides the GS tile — remove it from the map.',
      after: Duration(seconds: 1),
    ),
    const Tap(DemoIds.tilesMenu, caption: 'Open the menu to add it back.'),
    Wait.seconds(1),
    const Tap(
      DemoIds.tilesToggleGs,
      caption: 'Plus shows GS again.',
      after: Duration(seconds: 1),
    ),
    const Narrate(
      'Reset Layout restores the default tiles and positions. This demo does not tap Reset — your layout is restored when the demo ends.',
    ),
  ],
);
