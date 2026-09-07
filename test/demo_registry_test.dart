import 'package:avaremp/demo/demo_ids.dart';
import 'package:avaremp/demo/demo_registry.dart';
import 'package:avaremp/demo/demo_step.dart';
import 'package:avaremp/demo/demo_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registry has the three core tours with unique ids', () {
    expect(DemoRegistry.tours.length, 3);
    expect(DemoRegistry.tours.map((t) => t.id).toSet().length, 3);
    expect(DemoRegistry.byId('map_controls'), isNotNull);
    expect(DemoRegistry.byId('build_plan'), isNotNull);
    expect(DemoRegistry.byId('find_destination'), isNotNull);
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

  test('GoTab indices match the main shell', () {
    expect(GoTab.map.index, 0);
    expect(GoTab.plate.index, 1);
    expect(GoTab.plan.index, 2);
    expect(GoTab.find.index, 3);
  });
}
