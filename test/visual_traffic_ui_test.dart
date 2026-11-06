import 'package:avaremp/visual_traffic/detection_models.dart';
import 'package:avaremp/visual_traffic/detection_painter.dart';
import 'package:avaremp/visual_traffic/visual_traffic_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DetectionBox _box(int id, DetectionTier tier,
    {double x = 0.5, double y = 0.5, double w = 0.02, double h = 0.02}) {
  return DetectionBox(
    id: id,
    x: x,
    y: y,
    w: w,
    h: h,
    confidence: 0.8,
    tier: tier,
  );
}

void main() {
  group("bearingLabel", () {
    test("is zero in the middle of the picture", () {
      final DetectionBox box = _box(1, DetectionTier.airplane, x: 0.49, y: 0.49);
      expect(DetectionPainter.bearingLabel(box, 60, 40), "0° R  0° up");
    });

    test("counts degrees left and up from the middle", () {
      // Center at x 0.25, y 0.25: a quarter of the picture left and up.
      final DetectionBox box =
          _box(1, DetectionTier.airplane, x: 0.24, y: 0.24, w: 0.02, h: 0.02);
      expect(DetectionPainter.bearingLabel(box, 60, 40), "15° L  10° up");
    });

    test("counts right and down", () {
      final DetectionBox box =
          _box(1, DetectionTier.airplane, x: 0.74, y: 0.74, w: 0.02, h: 0.02);
      expect(DetectionPainter.bearingLabel(box, 60, 40), "15° R  10° down");
    });
  });

  group("TrafficAlert", () {
    final DateTime t0 = DateTime(2026, 1, 1, 12);

    test("fires for a new red box and not for a yellow one", () {
      final TrafficAlert alert = TrafficAlert();
      expect(alert.update([_box(1, DetectionTier.possible)], now: t0), isFalse);
      expect(alert.update([_box(1, DetectionTier.airplane)], now: t0), isTrue);
    });

    test("does not repeat for the same red box", () {
      final TrafficAlert alert = TrafficAlert();
      expect(alert.update([_box(1, DetectionTier.airplane)], now: t0), isTrue);
      expect(
          alert.update([_box(1, DetectionTier.airplane)],
              now: t0.add(const Duration(seconds: 30))),
          isFalse);
    });

    test("waits between alerts, but a box seen during the wait stays quiet", () {
      final TrafficAlert alert = TrafficAlert();
      expect(alert.update([_box(1, DetectionTier.airplane)], now: t0), isTrue);
      // A second airplane right away is held back by the gap.
      expect(
          alert.update([_box(1, DetectionTier.airplane), _box(2, DetectionTier.airplane)],
              now: t0.add(const Duration(seconds: 1))),
          isFalse);
      // It is known by now, so it does not alert later either.
      expect(
          alert.update([_box(1, DetectionTier.airplane), _box(2, DetectionTier.airplane)],
              now: t0.add(const Duration(seconds: 10))),
          isFalse);
      // A third one after the gap does.
      expect(
          alert.update([_box(3, DetectionTier.airplane)],
              now: t0.add(const Duration(seconds: 20))),
          isTrue);
    });

    test("a box that went away and came back alerts again after the gap", () {
      final TrafficAlert alert = TrafficAlert();
      expect(alert.update([_box(1, DetectionTier.airplane)], now: t0), isTrue);
      expect(alert.update(const [], now: t0.add(const Duration(seconds: 2))), isFalse);
      expect(
          alert.update([_box(1, DetectionTier.airplane)],
              now: t0.add(const Duration(seconds: 10))),
          isTrue);
    });
  });

  group("DetectionPainter", () {
    test("repaints only when something changed", () {
      final List<DetectionBox> boxes = [_box(1, DetectionTier.airplane)];
      final DetectionPainter a = DetectionPainter(boxes: boxes, fovH: 65, fovV: 37);
      final DetectionPainter same = DetectionPainter(boxes: boxes, fovH: 65, fovV: 37);
      final DetectionPainter other =
          DetectionPainter(boxes: [_box(2, DetectionTier.airplane)], fovH: 65, fovV: 37);
      expect(same.shouldRepaint(a), isFalse);
      expect(other.shouldRepaint(a), isTrue);
    });

    testWidgets("paints red and yellow boxes without error", (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 320,
            height: 180,
            child: CustomPaint(
              painter: DetectionPainter(
                boxes: [
                  _box(1, DetectionTier.airplane, x: 0.95, y: 0.95),
                  _box(2, DetectionTier.possible, x: 0.0, y: 0.0),
                ],
                fovH: 65,
                fovV: 37,
                horizonLeft: 0.6,
                horizonRight: 0.55,
                showHorizon: true,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets("start page offers the camera and the viewer and warns", (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: VisualTrafficScreen()));
    expect(find.text("This phone is the camera"), findsOneWidget);
    expect(find.text("Show another phone's camera"), findsOneWidget);
    expect(find.textContaining("collision avoidance"), findsOneWidget);
  });
}
