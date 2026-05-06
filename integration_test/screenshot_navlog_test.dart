// Captures the Navigation Log dialog only.
// Run with:
//   flutter test integration_test/screenshot_navlog_test.dart -d macos

import 'dart:io';
import 'dart:ui' as ui;

import 'package:avaremp/main.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

late Directory _outDir;
final GlobalKey _rootKey = GlobalKey();

Future<Directory> _resolveOutputDir() async {
  final docs = await getApplicationDocumentsDirectory();
  final d = Directory('${docs.path}/avarex_screenshots');
  if (!d.existsSync()) d.createSync(recursive: true);
  return d;
}

Future<void> _shot(WidgetTester tester, String name) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
  } catch (_) {}
  final ctx = _rootKey.currentContext;
  if (ctx == null) {
    debugPrint('Screenshot $name: no root context');
    return;
  }
  final ro = ctx.findRenderObject();
  if (ro is! RenderRepaintBoundary) {
    debugPrint('Screenshot $name: not a RepaintBoundary');
    return;
  }
  try {
    final image = await ro.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return;
    final bytes = byteData.buffer.asUint8List();
    final file = File('${_outDir.path}/$name.png');
    await file.writeAsBytes(bytes);
    debugPrint('Screenshot saved: ${file.path} (${bytes.length} bytes)');
  } catch (e) {
    debugPrint('Screenshot $name failed: $e');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Capture navigation log', (tester) async {
    _outDir = await _resolveOutputDir();
    debugPrint('Output dir: ${_outDir.path}');

    await Storage().init();
    Storage().settings.setIntro(false);

    await tester.pumpWidget(RepaintBoundary(
      key: _rootKey,
      child: const MainApp(),
    ));

    await Future.delayed(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    Finder fab;

    // Go straight to PLAN tab
    fab = find.byTooltip('Create a flight plan');
    expect(fab, findsOneWidget);
    await tester.tap(fab);
    await tester.pumpAndSettle(const Duration(milliseconds: 800));
    await Future.delayed(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // Build a route (idempotent — if existing route is present we still get a valid navlog)
    fab = find.widgetWithText(TextButton, 'Actions');
    if (tester.any(fab)) {
      await tester.tap(fab);
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      fab = find.widgetWithText(TextButton, 'Create');
      if (tester.any(fab)) {
        await tester.tap(fab);
        await tester.pumpAndSettle(const Duration(milliseconds: 600));

        fab = find.ancestor(
            of: find.text('Route'), matching: find.byType(TextFormField));
        if (tester.any(fab)) {
          await tester.enterText(fab, 'KBOS BOS CMK KHPN');
          await tester.pump(const Duration(milliseconds: 400));
          fab = find.widgetWithText(ListTile, 'Create As Entered');
          if (tester.any(fab)) {
            await tester.tap(fab);
            await tester.pumpAndSettle(const Duration(milliseconds: 600));
            await Future.delayed(const Duration(seconds: 2));
            await tester.pumpAndSettle();
          }
        }
        // back to plan
        fab = find.byTooltip('Back');
        if (tester.any(fab)) {
          await tester.tap(fab);
          await tester.pumpAndSettle(const Duration(milliseconds: 600));
        }
      }
    }

    // Open the Navigation Log dialog (analytics_outlined icon, tooltip "Navigation log and terrain")
    fab = find.byTooltip('Navigation log and terrain');
    if (!tester.any(fab)) {
      fab = find.byIcon(Icons.analytics_outlined);
    }
    expect(fab, findsWidgets);
    await tester.tap(fab.first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    // Give time for winds-aloft fetch and elevation lookups
    await Future.delayed(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await _shot(tester, '23_plan_navlog');

    debugPrint('Navlog test complete');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
