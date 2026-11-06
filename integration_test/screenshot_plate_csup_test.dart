// Captures only the PLATE, CSUP, and final MAP screenshots for the user manual.
//
// Run with:
//   flutter test integration_test/screenshot_plate_csup_test.dart -d macos
//
// Screenshots are written to <project>/assets/docs/screenshots/ when run
// from the project root. If Directory.current is not writable (e.g. on
// other platforms), screenshots fall back to the app documents directory
// under "screenshots/".

import 'dart:io';
import 'dart:ui' as ui;

import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
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

Future<void> _restorePlan(String savedJson, String savedName, int savedIndex, int savedDest, String savedEntry) async {
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Capture plate and csup screenshots', (tester) async {
    _outDir = await _resolveOutputDir();
    await Storage().init();
    Storage().settings.setIntro(false);
    await tester.pumpWidget(RepaintBoundary(
      key: _rootKey,
      child: const MainApp(),
    ));
    await Future.delayed(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));

    // ===========================================
    // PLATE tab — KBVY airport diagram, after the chart has decoded
    // ===========================================
    final String savedPlateAirport = Storage().settings.getCurrentPlateAirport();
    final String savedPlate = Storage().currentPlate;
    final String savedLastPlate = Storage().lastPlateAirport;
    final String savedPlanJson = Storage().settings.getActivePlanRoute();
    final String savedPlanName = Storage().settings.getActivePlanName();
    final int savedPlanIndex = Storage().settings.getActivePlanIndex();
    final int savedPlanDest = Storage().settings.getActivePlanDestinationIndex();
    final String savedRouteEntry = Storage().settings.getLastRouteEntry();
    final bool savedSync = Storage().settings.isSyncPlateToActiveWaypoint();
    try {
    // The plate loads when the active waypoint moves to a different airport:
    // start on another airport, then set KBVY as the destination.
    final AirportDestination? kbvy = await tester.runAsync<AirportDestination?>(() async {
      final AirportDestination? airport = await MainDatabaseHelper.db.findAirport('KBVY');
      if (airport != null) {
        await UserDatabaseHelper.db.addRecent(airport);
      }
      return airport;
    });
    await _mark('KBVY found=${kbvy != null}');
    Storage().settings.setSyncPlateToActiveWaypoint(true);
    Storage().settings.setCurrentPlateAirport('KBOS');
    Storage().lastPlateAirport = '';
    Storage().currentPlate = '';
    Storage().route.clear();
    Storage().setDestination(kbvy);
    MainScreenState.gotoPlate();
    await _mark('destination set, plate tab shown');
    bool plateReady = false;
    for (int i = 0; i < 40; i++) {
      await _mark('wait for plate $i');
      await Future.delayed(const Duration(milliseconds: 300));
      final ui.Image? img = Storage().imagePlate;
      plateReady = img != null &&
          img.width > 200 &&
          Storage().settings.getCurrentPlateAirport() == 'KBVY' &&
          PathUtils.isAirportDiagram(Storage().currentPlate);
      if (plateReady) {
        break;
      }
    }
    await _mark('plate ready=$plateReady airport=${Storage().settings.getCurrentPlateAirport()} image=${Storage().imagePlate?.width}x${Storage().imagePlate?.height} plate=${Storage().currentPlate}');
    // The plate screen reads its airport list from the database, which needs real time.
    for (int i = 0; i < 40; i++) {
      await _mark('wait for plate screen $i');
      await Future.delayed(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 200));
      if (!tester.any(find.text('No plates available')) && tester.any(find.text('KBVY'))) {
        break;
      }
    }
    await _mark('plate screen shows KBVY=${tester.any(find.text('KBVY'))} empty=${tester.any(find.text('No plates available'))}');
    await Future.delayed(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 800));
    await _shot(tester, '31_plate_tab');

    // ===========================================
    // CSUP tab — same airport as the Plate tab, opens on the airport text page
    // ===========================================
    MainScreenState.gotoCsup();
    await tester.pump(const Duration(milliseconds: 400));
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      if (!tester.any(find.byType(CircularProgressIndicator))) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
    await Future.delayed(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 600));
    await _shot(tester, '34_csup_tab');

    Storage().settings.setCurrentPlateAirport(savedPlateAirport);
    Storage().currentPlate = savedPlate;
    Storage().lastPlateAirport = savedLastPlate;

    // Back to MAP for final shot. The nav item sits under the plate, so use the bar callback.
    MainScreenState.gotoMap();
    await tester.pump(const Duration(milliseconds: 700));
    await _shot(tester, '32_map_tab_final');
    } finally {
      Storage().settings.setSyncPlateToActiveWaypoint(savedSync);
      await _restorePlan(savedPlanJson, savedPlanName, savedPlanIndex, savedPlanDest, savedRouteEntry);
    }

  }, timeout: const Timeout(Duration(minutes: 2)));
}
