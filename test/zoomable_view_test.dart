import 'package:avaremp/utils/zoomable_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(PageController c, ValueNotifier<bool> locked) {
  return MaterialApp(
    home: ValueListenableBuilder<bool>(
      valueListenable: locked,
      builder: (context, isLocked, _) => PageView.builder(
        controller: c,
        itemCount: 3,
        physics: isLocked ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
        itemBuilder: (ctx, i) => ZoomableView(
          onLockChanged: (v) => locked.value = v,
          child: Center(child: Text('p$i', key: ValueKey('t$i'))),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('one finger swipes pages when not zoomed', (tester) async {
    final c = PageController();
    final locked = ValueNotifier<bool>(false);
    await tester.pumpWidget(_app(c, locked));
    await tester.drag(find.text('p0'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(c.page, 1.0);
    await tester.drag(find.text('p1'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(c.page, 0.0);
  });

  testWidgets('pinch zooms and locks paging, double tap resets', (tester) async {
    final c = PageController();
    final locked = ValueNotifier<bool>(false);
    await tester.pumpWidget(_app(c, locked));
    final Offset center = tester.getCenter(find.byType(ZoomableView).first);

    final g1 = await tester.startGesture(center - const Offset(20, 0));
    final g2 = await tester.startGesture(center + const Offset(20, 0));
    await tester.pump();
    expect(locked.value, isTrue); // pinching locks paging
    await g1.moveBy(const Offset(-60, 0));
    await g2.moveBy(const Offset(60, 0));
    await tester.pump();
    final Transform t = tester.widget<Transform>(find.descendant(
        of: find.byType(ZoomableView).first, matching: find.byType(Transform)));
    expect(t.transform.getMaxScaleOnAxis(), greaterThan(2));
    await g1.up();
    await g2.up();
    await tester.pump();
    expect(locked.value, isTrue); // still zoomed
    expect(c.page, 0.0);

    // dragging while zoomed pans, does not page
    await tester.drag(find.byType(ZoomableView).first, const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(c.page, 0.0);

    // double tap zooms back out
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
    expect(locked.value, isFalse);

    await tester.drag(find.text('p0'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(c.page, 1.0);
  });
}
