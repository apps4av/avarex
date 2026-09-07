import 'package:avaremp/demo/demo_ids.dart';
import 'package:avaremp/demo/demo_step.dart';
import 'package:avaremp/demo/demo_tour.dart';

final DemoTour writeNotesTour = DemoTour(
  id: 'write_notes',
  title: 'Write a note',
  subtitle: 'Draw, pick a sheet, and use the keypad',
  steps: [
    const GoTab.mapWith(caption: 'Notes live in the drawer, from the MAP tab.'),
    const Tap(DemoIds.mapMenu,
        caption: 'Menu opens Write a Note under Flight.'),
    Wait.seconds(2),
    const Tap(
      DemoIds.drawerNotes,
      caption:
          'Write a Note is a canvas for handwriting and aviation copydown sheets.',
      after: Duration(milliseconds: 1200),
    ),
    const Narrate(
        'Draw with a finger or stylus. Colors, eraser, and the keypad sit along the bottom.'),
    const Tap(DemoIds.notesColorRed,
        caption: 'Tap a color to change the pen. Red is useful for emphasis.'),
    Wait.seconds(1),
    const Tap(DemoIds.notesSheetPicker,
        caption:
            'Background Sheet picks a copydown template — ATIS, CRAFT, taxi, and more.'),
    Wait.seconds(1),
    const Tap(
      DemoIds.notesSheetCraft,
      caption:
          'CRAFT is the IFR clearance sheet: clearance limit, route, altitude, frequency, transponder.',
      after: Duration(seconds: 2),
    ),
    const Tap(DemoIds.notesKeypad,
        caption:
            'The dialpad opens a number keypad for frequencies, altitudes, and squawk codes.'),
    Wait.seconds(2),
    const Narrate(
        'Undo, Redo, Clear, and Save are in the app bar. Notes auto-save when you leave. This demo does not clear or save a snapshot.'),
    const Pop(),
  ],
);
