import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/demo/demo_ids.dart';
import 'package:avaremp/demo/demo_step.dart';
import 'package:avaremp/demo/demo_tour.dart';
import 'package:avaremp/storage.dart';

const String demoChecklistName = 'Demo Preflight';
const String demoChecklistSteps = 'Documents\nWeather\nFuel';

final DemoTour checklistsTour = DemoTour(
  id: 'checklists',
  title: 'Check lists',
  subtitle: 'Create a list, check items, and reset',
  steps: [
    Prepare(_removeDemoChecklist),
    const GoTab.mapWith(
        caption: 'Check Lists are in the drawer, from the MAP tab.'),
    const Tap(DemoIds.mapMenu, caption: 'Menu opens Check Lists under Flight.'),
    Wait.seconds(2),
    const Tap(
      DemoIds.drawerChecklists,
      caption:
          'Check Lists are for preflight and procedures you can tick off in order.',
      after: Duration(milliseconds: 1200),
    ),
    const Tap(DemoIds.checklistNew,
        caption:
            'New creates a list in the app — name plus one step per line.'),
    Wait.seconds(1),
    const TypeText(
      DemoIds.checklistNameField,
      demoChecklistName,
      caption: 'Give the list a short name.',
    ),
    const TypeText(
      DemoIds.checklistStepsField,
      demoChecklistSteps,
      caption: 'Type the steps, one per line.',
    ),
    const Tap(
      DemoIds.checklistCreate,
      caption: 'Create saves the list and opens it.',
      after: Duration(seconds: 2),
    ),
    const Narrate(
        'Tap a row to check it off. The bar at the top shows progress.'),
    const Tap(
      DemoIds.checklistFirstItem,
      caption: 'Check the first item — it turns green with a strikethrough.',
      after: Duration(seconds: 1),
    ),
    const Tap(
      DemoIds.checklistReset,
      caption: 'Reset all clears every check so you can run the list again.',
      timeout: Duration(seconds: 5),
    ),
    Wait.seconds(1),
    const Narrate(
        'Import reads a .txt file — first line is the title, the rest are steps. This demo does not open the file picker. Swipe Delete at the bottom to remove a list.'),
    const Pop(),
  ],
);

Future<void> _removeDemoChecklist() async {
  await UserDatabaseHelper.db.deleteChecklist(demoChecklistName);
  if (Storage().settings.getChecklist() == demoChecklistName) {
    Storage().settings.setChecklist('');
  }
  if (Storage().activeChecklistName == demoChecklistName) {
    Storage().activeChecklistName = '';
    Storage().activeChecklistSteps = <bool>[];
  }
}
