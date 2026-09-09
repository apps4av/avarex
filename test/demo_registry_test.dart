import 'package:avaremp/demo/demo_engine.dart';
import 'package:avaremp/demo/demo_host.dart';
import 'package:avaremp/demo/demo_ids.dart';
import 'package:avaremp/demo/demo_overlay.dart';
import 'package:avaremp/demo/demo_registry.dart';
import 'package:avaremp/demo/demo_step.dart';
import 'package:avaremp/demo/demo_target.dart';
import 'package:avaremp/demo/demo_tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registry has the core tours with unique ids', () {
    expect(DemoRegistry.tours.length, 6);
    expect(DemoRegistry.tours.map((t) => t.id).toSet().length, 6);
    expect(DemoRegistry.byId('map_controls'), isNotNull);
    expect(DemoRegistry.byId('build_plan'), isNotNull);
    expect(DemoRegistry.byId('find_destination'), isNotNull);
    expect(DemoRegistry.byId('write_notes'), isNotNull);
    expect(DemoRegistry.byId('takeoff_landing'), isNotNull);
    expect(DemoRegistry.byId('instrument_tiles'), isNotNull);
    expect(DemoRegistry.byId('checklists'), isNull);
    expect(DemoRegistry.byId('missing'), isNull);
  });

  test('every tour has at least one step', () {
    for (final tour in DemoRegistry.tours) {
      expect(tour.steps, isNotEmpty, reason: tour.id);
      expect(tour.title, isNotEmpty);
    }
  });

  testWidgets('DemoTarget exposes a mounted rect', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DemoTarget(
            id: DemoIds.mapMenu,
            child: SizedBox(width: 40, height: 20, child: Text('Menu')),
          ),
        ),
      ),
    );
    expect(DemoTargets.isMounted(DemoIds.mapMenu), isTrue);
    final Rect? rect = DemoTargets.rectOf(DemoIds.mapMenu);
    expect(rect, isNotNull);
    expect(rect!.width, greaterThan(0));
    expect(rect.height, greaterThan(0));
  });

  test('write notes tour hits the notes targets', () {
    final DemoTour notes = DemoRegistry.byId('write_notes')!;
    final List<String> noteTaps =
        notes.steps.whereType<Tap>().map((Tap s) => s.targetId).toList();
    expect(
      noteTaps,
      containsAll(<String>[
        DemoIds.mapMenu,
        DemoIds.drawerNotes,
        DemoIds.notesColorRed,
        DemoIds.notesSheetPicker,
        DemoIds.notesSheetCraft,
        DemoIds.notesKeypad,
      ]),
    );
    expect(
        noteTaps
            .any((String id) => id.contains('clear') || id.contains('save')),
        isFalse);
  });

  test('takeoff and tiles tours hit the new targets', () {
    final DemoTour perf = DemoRegistry.byId('takeoff_landing')!;
    final DemoTour tiles = DemoRegistry.byId('instrument_tiles')!;
    final List<String> perfTaps =
        perf.steps.whereType<Tap>().map((Tap s) => s.targetId).toList();
    expect(
      perfTaps,
      containsAll(<String>[
        DemoIds.drawerPerformance,
        DemoIds.perfAircraftPicker,
        DemoIds.perfC172,
        DemoIds.perfTakeoffTab,
        DemoIds.perfLandingTab,
        DemoIds.perfTakeoffResults,
        DemoIds.perfLandingResults,
      ]),
    );
    final List<String> typed = perf.steps
        .whereType<TypeText>()
        .map((TypeText s) => s.targetId)
        .toList();
    expect(
      typed,
      containsAll(
          <String>[DemoIds.perfTakeoffAltitude, DemoIds.perfLandingAltitude]),
    );

    final List<String> tileTaps =
        tiles.steps.whereType<Tap>().map((Tap s) => s.targetId).toList();
    expect(
      tileTaps,
      containsAll(<String>[
        DemoIds.tilesMenu,
        DemoIds.tilesLock,
        DemoIds.tilesToggleGs,
      ]),
    );
    final List<Drag> drags = tiles.steps.whereType<Drag>().toList();
    expect(drags, isNotEmpty);
    expect(drags.first.targetId, DemoIds.tilesGs);
    expect(tiles.steps.whereType<Tap>().any((Tap s) => s.targetId.contains('reset')),
        isFalse);
  });

  test('GoTab indices match the main shell', () {
    expect(GoTab.map.index, 0);
    expect(GoTab.plate.index, 1);
    expect(GoTab.plan.index, 2);
    expect(GoTab.find.index, 3);
  });

  testWidgets('demo chrome tooltips build above the navigator', (tester) async {
    addTearDown(() {
      DemoEngine.instance.overlay.value = DemoOverlayState.hidden;
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            DemoHost(child: child ?? const SizedBox.shrink()),
        home: const Scaffold(body: Text('home')),
      ),
    );
    DemoEngine.instance.overlay.value = const DemoOverlayState(
      visible: true,
      caption: 'The MAP tab is your moving map.',
      tourTitle: 'Map controls',
      stepIndex: 1,
      stepCount: 3,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('The MAP tab is your moving map.'), findsNothing);
    expect(find.byTooltip('Exit demo'), findsOneWidget);
  });
}
