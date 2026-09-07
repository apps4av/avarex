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
    expect(DemoRegistry.tours.length, 5);
    expect(DemoRegistry.tours.map((t) => t.id).toSet().length, 5);
    expect(DemoRegistry.byId('map_controls'), isNotNull);
    expect(DemoRegistry.byId('build_plan'), isNotNull);
    expect(DemoRegistry.byId('find_destination'), isNotNull);
    expect(DemoRegistry.byId('write_notes'), isNotNull);
    expect(DemoRegistry.byId('checklists'), isNotNull);
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

  test('write notes and checklists tours hit the new targets', () {
    final DemoTour notes = DemoRegistry.byId('write_notes')!;
    final DemoTour checks = DemoRegistry.byId('checklists')!;
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

    final List<String> checkTaps =
        checks.steps.whereType<Tap>().map((Tap s) => s.targetId).toList();
    expect(
      checkTaps,
      containsAll(<String>[
        DemoIds.drawerChecklists,
        DemoIds.checklistNew,
        DemoIds.checklistCreate,
        DemoIds.checklistFirstItem,
        DemoIds.checklistReset,
      ]),
    );
    final List<String> typed = checks.steps
        .whereType<TypeText>()
        .map((TypeText s) => s.targetId)
        .toList();
    expect(
        typed,
        containsAll(
            <String>[DemoIds.checklistNameField, DemoIds.checklistStepsField]));
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
