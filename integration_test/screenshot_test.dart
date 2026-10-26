// Captures screenshots of all major app screens for the user manual.
//
// Run with:
//   flutter test integration_test/screenshot_test.dart -d macos
//
// Screenshots are written to <project>/assets/docs/screenshots/ when run
// from the project root. If Directory.current is not writable (e.g. on
// other platforms), screenshots fall back to the app documents directory
// under "screenshots/".

import 'dart:io';
import 'dart:ui' as ui;

import 'package:avaremp/main.dart';
import 'package:avaremp/main_screen.dart';
import 'package:avaremp/plan/plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/path_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

late Directory _outDir;
final GlobalKey _rootKey = GlobalKey();

Future<Directory> _resolveOutputDir() async {
  // App-sandbox friendly: always write to the app documents directory.
  // After the test runs, copy this folder to assets/docs/screenshots/.
  final docs = await getApplicationDocumentsDirectory();
  final d = Directory('${docs.path}/avarex_screenshots');
  if (!d.existsSync()) d.createSync(recursive: true);
  return d;
}

Future<void> _mark(String step) async {
  debugPrint('SCREENSHOT STEP: $step');
  try {
    await File('${_outDir.path}/_progress.txt').writeAsString(
      '${DateTime.now().toIso8601String()} $step\n',
      mode: FileMode.append,
    );
  } catch (_) {}
}

Future<void> _shot(WidgetTester tester, String name) async {
  await _mark('shot $name');
  // Fixed pumps only. pumpAndSettle never returns while the map animates,
  // and a long encode can drop the test connection.
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final ctx = _rootKey.currentContext;
  if (ctx == null) {
    debugPrint('Screenshot $name: no root context');
    return;
  }
  final ro = ctx.findRenderObject();
  if (ro is! RenderRepaintBoundary) {
    debugPrint('Screenshot $name: root render object is not a RepaintBoundary');
    return;
  }
  try {
    final image = await ro.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      debugPrint('Screenshot $name: byteData null');
      return;
    }
    final bytes = byteData.buffer.asUint8List();
    final file = File('${_outDir.path}/$name.png');
    await file.writeAsBytes(bytes);
    debugPrint('Screenshot saved: ${file.path} (${bytes.length} bytes)');
  } catch (e) {
    debugPrint('Screenshot $name failed: $e');
    await _mark('shot $name FAILED: $e');
  }
}

Future<void> _press(WidgetTester tester, Finder finder, String label) async {
  if (!tester.any(finder)) {
    await _mark('missing $label');
    return;
  }
  final Widget widget = tester.widget(finder.first);
  final VoidCallback? onPressed = widget is TextButton
      ? widget.onPressed
      : widget is IconButton
          ? widget.onPressed
          : widget is ListTile
              ? widget.onTap
              : null;
  if (onPressed == null) {
    await tester.tap(finder.first, warnIfMissed: false);
  } else {
    onPressed();
  }
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _restorePlan(
  String savedJson,
  String savedName,
  int savedIndex,
  int savedDest,
  String savedEntry,
) async {
  try {
    if (savedJson.isEmpty || savedJson == '[]') {
      Storage().route.clear();
    } else {
      final PlanRoute restored = await PlanRoute.fromJson(savedJson, savedName, false);
      Storage().route.copyFrom(restored);
      if (savedIndex >= 0 && savedIndex < Storage().route.length) {
        Storage().route.setCurrentWaypoint(savedIndex);
        Storage().route.setCurrentWaypointDestinationIndex(savedDest);
      }
    }
  } catch (e) {
    await _mark('restore plan failed: $e');
  }
  Storage().settings.setActivePlanRoute(savedJson);
  Storage().settings.setActivePlanName(savedName);
  Storage().settings.setActivePlanIndex(savedIndex);
  Storage().settings.setActivePlanDestinationIndex(savedDest);
  Storage().settings.setLastRouteEntry(savedEntry);
  // The plan is written on a 1-second timer from the in-memory route.
  await Future.delayed(const Duration(milliseconds: 1200));
}

Future<void> _closeDrawer(WidgetTester tester) async {
  final Finder scaffolds = find.byType(Scaffold);
  final int n = scaffolds.evaluate().length;
  for (int i = 0; i < n; i++) {
    final ScaffoldState state = tester.state<ScaffoldState>(scaffolds.at(i));
    if (state.hasDrawer && state.isDrawerOpen) {
      state.closeDrawer();
    }
  }
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _closeOverlay(WidgetTester tester) async {
  try {
    final close = find.byIcon(Icons.close);
    if (tester.any(close)) {
      await tester.tap(close.last, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      return;
    }
    final back = find.byTooltip('Back');
    if (tester.any(back)) {
      await tester.tap(back.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
    }
  } catch (e) {
    await _mark('close overlay failed: $e');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Capture all screen screenshots',
      (tester) async {
    _outDir = await _resolveOutputDir();
    debugPrint('Screenshots will be written to: ${_outDir.path}');
    final File progress = File('${_outDir.path}/_progress.txt');
    if (progress.existsSync()) progress.deleteSync();

    String? savedPlanJson;
    String savedPlanName = 'New Plan';
    int savedPlanIndex = -1;
    int savedPlanDest = 0;
    String savedRouteEntry = '';
    try {
    // Initialize storage but keep existing user state (databases, signed flag).
    await Storage().init();
    savedPlanJson = Storage().settings.getActivePlanRoute();
    savedPlanName = Storage().settings.getActivePlanName();
    savedPlanIndex = Storage().settings.getActivePlanIndex();
    savedPlanDest = Storage().settings.getActivePlanDestinationIndex();
    savedRouteEntry = Storage().settings.getLastRouteEntry();
    // Make sure we don't show the intro pages: capture them in a separate
    // section below by toggling intro back on for a fresh widget tree.
    Storage().settings.setIntro(false);

    await tester.pumpWidget(RepaintBoundary(
      key: _rootKey,
      child: const MainApp(),
    ));

    // Give the app time to settle and load initial data
    await Future.delayed(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));

    Finder fab;

    // Sometimes a permissions / GPS toast appears — try to dismiss
    fab = find.byTooltip('Close');
    if (tester.any(fab)) {
      await tester.tap(fab.first);
      await tester.pump(const Duration(milliseconds: 300));
    }

    // ===========================================
    // MAP tab (default screen after onboarding)
    // ===========================================
    fab = find.byTooltip('View the maps and overlays');
    if (tester.any(fab)) {
      await tester.tap(fab);
      await tester.pump(const Duration(milliseconds: 500));
    }
    await _shot(tester, '01_map_tab');

    // Open layers popup. Tooltip avoids the Chart layer's Icons.map.
    fab = find.byTooltip('Select the layers to show on the Map screen');
    if (tester.any(fab)) {
      await tester.tap(fab);
      await tester.pump(const Duration(milliseconds: 600));
      await _shot(tester, '02_map_layers_popup');
      await _closeOverlay(tester);
    }

    // Open chart-type popup
    fab = find.byTooltip('Select the chart type');
    if (tester.any(fab)) {
      await tester.tap(fab);
      await tester.pump(const Duration(milliseconds: 600));
      await _shot(tester, '03_map_chart_types');
      await _closeOverlay(tester);
    }

    // ===========================================
    // Drawer (Menu)
    // ===========================================
    fab = find.widgetWithText(TextButton, 'Menu');
    if (tester.any(fab)) {
      await tester.tap(fab);
      await tester.pump(const Duration(milliseconds: 700));
      await _shot(tester, '04_drawer_menu');

      await _closeDrawer(tester);
    }

    // ===========================================
    // Download screen (via route)
    // ===========================================
    final navState = tester.state<NavigatorState>(find.byType(Navigator).first);
    Future<void> goRoute(String route, String shotName) async {
      navState.pushNamed(route);
      await tester.pump(const Duration(milliseconds: 600));
      await Future.delayed(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 400));
      await _shot(tester, shotName);
      // Pop back
      navState.pop();
      await tester.pump(const Duration(milliseconds: 500));
    }

    await goRoute('/download', '05_download_screen');

    // Download screen with a category expanded
    navState.pushNamed('/download');
    await tester.pump(const Duration(milliseconds: 1000));
    await Future.delayed(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));
    fab = find.widgetWithText(ExpansionTile, 'Sectional');
    if (tester.any(fab)) {
      await tester.tap(fab.first);
      await tester.pump(const Duration(milliseconds: 800));
      await _shot(tester, '06_download_sectional_expanded');
    }
    navState.pop();
    await tester.pump(const Duration(milliseconds: 500));

    await goRoute('/documents', '07_documents_screen');
    await goRoute('/checklists', '08_checklists_screen');

    // 3D airspace follows the aircraft. Wait out the vector-database load.
    navState.pushNamed('/airspace3d');
    await tester.pump(const Duration(milliseconds: 600));
    for (int i = 0; i < 25; i++) {
      await Future.delayed(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 200));
      final bool waiting = tester.any(find.byType(CircularProgressIndicator)) ||
          tester.any(find.text('Waiting for a GPS position.'));
      if (!waiting) break;
    }
    await Future.delayed(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, '33_airspace_3d');
    navState.pop();
    await tester.pump(const Duration(milliseconds: 500));

    // Aircraft & Performance with all tabs
    navState.pushNamed('/performance');
    await tester.pump(const Duration(milliseconds: 800));
    await Future.delayed(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, '09_aircraft_performance');

    final tabs = <String, String>{
      'T/O': '10_aircraft_takeoff',
      'L/D': '11_aircraft_landing',
      'Cruise': '12_aircraft_cruise',
      'W&B': '13_aircraft_wnb',
      'My Aircraft': '14_aircraft_my',
    };
    for (final entry in tabs.entries) {
      final f = find.text(entry.key);
      if (tester.any(f)) {
        await tester.tap(f.first);
        await tester.pump(const Duration(milliseconds: 600));
        await Future.delayed(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 300));
        await _shot(tester, entry.value);
      }
    }
    navState.pop();
    await tester.pump(const Duration(milliseconds: 500));

    await goRoute('/logbook', '15_logbook_screen');

    // Notes screen with sheet picker and CRAFT
    navState.pushNamed('/notes');
    await tester.pump(const Duration(milliseconds: 800));
    await Future.delayed(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 300));
    await _shot(tester, '16_notes_screen');

    fab = find.byIcon(Icons.note_alt_outlined);
    if (tester.any(fab)) {
      await tester.tap(fab.first);
      await tester.pump(const Duration(milliseconds: 700));
      await _shot(tester, '17_notes_sheet_picker');
      fab = find.text('CRAFT');
      if (tester.any(fab)) {
        await tester.tap(fab.first);
        await tester.pump(const Duration(milliseconds: 700));
        await Future.delayed(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 300));
        await _shot(tester, '18_notes_craft_sheet');
      }
    }
    navState.pop();
    await tester.pump(const Duration(milliseconds: 500));

    // ===========================================
    // PLAN tab
    // The map's Center control sits over the PLAN nav item, so drive the
    // bar callback. Action tabs are inline buttons, not a separate screen.
    // ===========================================
    await _closeDrawer(tester);
    Storage().route.clear();
    MainScreenState.gotoPlan();
    await tester.pump(const Duration(milliseconds: 700));
    await _shot(tester, '19_plan_tab_empty');

    await _press(tester, find.widgetWithText(TextButton, 'Create'), 'Create');
    await _shot(tester, '21_plan_create');

    fab = find.ancestor(
        of: find.text('Route'), matching: find.byType(TextFormField));
    if (tester.any(fab)) {
      await tester.enterText(fab.first, 'KBOS BOS CMK KHPN');
      await tester.pump(const Duration(milliseconds: 400));
      await _shot(tester, '25_plan_actions_create');
      await _press(
          tester, find.widgetWithText(ListTile, 'Create As Entered'), 'Create As Entered');
      await Future.delayed(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 600));
    }
    await _shot(tester, '22_plan_with_route');

    final Finder navLog = find.ancestor(
      of: find.byTooltip('Navigation log and terrain'),
      matching: find.byType(IconButton),
    );
    await _press(tester, navLog, 'nav log');
    await Future.delayed(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 600));
    await _shot(tester, '23_plan_navlog');
    await _closeOverlay(tester);

    await _press(tester, find.widgetWithText(TextButton, 'Load & Save'), 'Load & Save');
    await _shot(tester, '20_plan_actions');
    await _shot(tester, '24_plan_actions_load_save');

    await _press(tester, find.widgetWithText(TextButton, 'Brief & File'), 'Brief & File');
    await _shot(tester, '26_plan_actions_brief_file');

    await _press(tester, find.widgetWithText(TextButton, 'Manage'), 'Manage');
    for (int i = 0; i < 30; i++) {
      if (tester.any(find.text('No flight plans on file')) ||
          !tester.any(find.byType(CircularProgressIndicator))) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 200));
    }
    await _shot(tester, '27_plan_actions_manage');

    await _press(tester, find.widgetWithText(TextButton, 'Plan'), 'Plan');

    // ===========================================
    // FIND tab
    // ===========================================
    fab = find.byTooltip('Search for Airports, NavAids, etc.');
    if (tester.any(fab)) {
      await tester.tap(fab);
      await tester.pump(const Duration(milliseconds: 700));
      await _shot(tester, '28_find_tab_recent');

      // Nearest
      fab = find.widgetWithText(TextButton, 'Nearest');
      if (tester.any(fab)) {
        await tester.tap(fab);
        await tester.pump(const Duration(milliseconds: 600));
        await Future.delayed(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 500));
        await _shot(tester, '29_find_tab_nearest');
      }

      // Search
      fab = find.ancestor(
          of: find.text('Search'), matching: find.byType(TextFormField));
      if (tester.any(fab)) {
        await tester.enterText(fab, 'KBOS');
        await tester.pump(const Duration(milliseconds: 600));
        await Future.delayed(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 500));
        await _shot(tester, '30_find_tab_search_kbos');
      }
    }

    // ===========================================
    // PLATE tab — KBVY airport diagram, after the chart has decoded
    // ===========================================
    final String savedPlateAirport = Storage().settings.getCurrentPlateAirport();
    final String savedPlate = Storage().currentPlate;
    final String savedLastPlate = Storage().lastPlateAirport;
    Storage().settings.setCurrentPlateAirport('KBVY');
    Storage().lastPlateAirport = '';
    final List<String> kbvyPlates =
        await PathUtils.getPlatesAndCSupSorted(Storage().dataDir, 'KBVY');
    final String diagram = kbvyPlates.firstWhere(
      PathUtils.isAirportDiagram,
      orElse: () => '',
    );
    if (diagram.isNotEmpty) {
      Storage().currentPlate = diagram;
    }
    await _mark('plate KBVY diagram=$diagram count=${kbvyPlates.length}');
    if (diagram.isNotEmpty) {
      await Storage().loadPlate();
    }
    MainScreenState.gotoPlate();
    await tester.pump(const Duration(milliseconds: 400));
    bool plateReady = false;
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      final ui.Image? img = Storage().imagePlate;
      plateReady = img != null &&
          img.width > 200 &&
          Storage().currentPlate.contains('AIRPORT DIAGRAM') &&
          tester.any(find.text('KBVY'));
      if (plateReady) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
    await _mark('plate ready=$plateReady image=${Storage().imagePlate?.width}x${Storage().imagePlate?.height} plate=${Storage().currentPlate}');
    await tester.pump(const Duration(milliseconds: 600));
    await _shot(tester, '31_plate_tab');
    Storage().settings.setCurrentPlateAirport(savedPlateAirport);
    Storage().currentPlate = savedPlate;
    Storage().lastPlateAirport = savedLastPlate;

    // Back to MAP for final shot. The nav item sits under the plate, so use the bar callback.
    MainScreenState.gotoMap();
    await tester.pump(const Duration(milliseconds: 700));
    await _shot(tester, '32_map_tab_final');

    debugPrint('Screenshot test complete. Output dir: ${_outDir.path}');
    await _mark('complete');
    } catch (e, st) {
      debugPrint('SCREENSHOT TEST ERROR: $e\n$st');
      await _mark('ERROR: $e\n$st');
    } finally {
      final String? json = savedPlanJson;
      if (json != null) {
        await _restorePlan(
          json,
          savedPlanName,
          savedPlanIndex,
          savedPlanDest,
          savedRouteEntry,
        );
      }
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
