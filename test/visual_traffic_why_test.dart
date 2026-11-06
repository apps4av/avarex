import 'dart:math';

import 'package:avaremp/visual_traffic/adsb_matcher.dart';
import 'package:avaremp/visual_traffic/decision_board.dart';
import 'package:avaremp/visual_traffic/decisions.dart';
import 'package:avaremp/visual_traffic/detection_models.dart';
import 'package:avaremp/visual_traffic/frame_analyzer.dart';
import 'package:avaremp/visual_traffic/why_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const double _lat = 37;
const double _lon = -122;

/// A target [north] and [east] of the ownship, in nautical miles.
AdsbTarget _target(String label, double north, double east, double altFt,
    {bool airborne = true}) {
  return AdsbTarget(
    label: label,
    latitude: _lat + north / 60,
    longitude: _lon + east / (60 * cos(_lat * pi / 180)),
    altitudeFt: altFt,
    airborne: airborne,
  );
}

OwnshipFix _ownship({double speed = 100, double? track = 90}) => OwnshipFix(
      latitude: _lat,
      longitude: _lon,
      altitudeFt: 5000,
      speedKnots: speed,
      trackDegrees: track,
    );

DetectionBox _box(int id, double cx, double cy,
    {DetectionTier tier = DetectionTier.airplane}) {
  return DetectionBox(
    id: id,
    x: cx - 0.01,
    y: cy - 0.01,
    w: 0.02,
    h: 0.02,
    confidence: 0.8,
    tier: tier,
  );
}

const HorizonReport _level = HorizonReport(
  source: HorizonSource.picture,
  tiltDegrees: 0,
  pitchDegrees: 0,
  sensorsAvailable: true,
);

AdsbPicture _match(
  List<AdsbTarget> traffic,
  List<DetectionBox> boxes, {
  OwnshipFix? ownship,
  HorizonReport horizon = _level,
  double yaw = 0,
  AdsbMatcher matcher = const AdsbMatcher(),
  bool noOwnship = false,
}) {
  return matcher.match(
    ownship: noOwnship ? null : (ownship ?? _ownship()),
    traffic: traffic,
    boxes: boxes,
    fovH: 65,
    fovV: 39.6,
    pictureWidth: 1280,
    pictureHeight: 720,
    horizon: horizon,
    yawOffsetDegrees: yaw,
  );
}

AdsbNote _only(AdsbPicture picture) {
  expect(picture.notes.length, 1);
  return picture.notes.single;
}

AnalysisResult _result({
  List<TargetNote> notes = const [],
  HorizonReport horizon = _level,
  bool modelAvailable = true,
  bool cluttered = false,
}) {
  return AnalysisResult(
    frame: const DetectionFrame(
      seq: 1,
      timestampMs: 0,
      fovH: 65,
      fovV: 39.6,
      boxes: [],
    ),
    pictureWidth: 1280,
    pictureHeight: 720,
    horizon: null,
    cluttered: cluttered,
    spots: 0,
    tracks: notes.length,
    modelRuns: 0,
    modelAvailable: modelAvailable,
    milliseconds: 5,
    notes: notes,
    horizonReport: horizon,
  );
}

TargetNote _note(int id, Verdict verdict, String code, [String reason = "because"]) {
  return TargetNote(id: id, x: 0.5, y: 0.5, verdict: verdict, code: code, reason: reason);
}

BoardLine _horizonLine(DecisionBoard board) =>
    board.sensors.firstWhere((BoardLine l) => l.text.startsWith("Horizon") || l.text.startsWith("No clear horizon") || l.text.startsWith("No horizon"));

void main() {
  group("AdsbMatcher", () {
    test("an aircraft dead ahead matches a box in the middle", () {
      final AdsbPicture p = _match(
        [_target("N123AB", 0, 1, 5000)],
        [_box(4, 0.5, 0.5)],
      );
      final AdsbNote note = _only(p);
      expect(note.status, AdsbStatus.matched);
      expect(note.boxId, 4);
      expect(p.labels[4], "N123AB 1.0nm");
      expect(p.problem, isNull);
    });

    test("an aircraft above the camera shows higher in the picture", () {
      final AdsbTarget above = _target("N1", 0, 1, 5500);
      // About 4.7 degrees up puts it near v = 0.385.
      expect(_only(_match([above], [_box(1, 0.5, 0.385)])).status, AdsbStatus.matched);
      // 500 feet up is inside the 6 degree tolerance of a box in the middle.
      expect(_only(_match([above], [_box(1, 0.5, 0.5)])).status, AdsbStatus.matched);
      // 1500 feet up is about 14 degrees, well away from it.
      expect(
          _only(_match([_target("N1", 0, 1, 6500)], [_box(1, 0.5, 0.5)])).status,
          AdsbStatus.inView);
    });

    test("camera pitch moves where an aircraft shows", () {
      final AdsbTarget level = _target("N1", 0, 1, 5000);
      const HorizonReport up = HorizonReport(
        source: HorizonSource.picture,
        tiltDegrees: 0,
        pitchDegrees: 10,
      );
      // Looking 10 degrees up, a level aircraft is 10 degrees below center.
      expect(_only(_match([level], [_box(1, 0.5, 0.5)], horizon: up)).status,
          AdsbStatus.inView);
      expect(_only(_match([level], [_box(1, 0.5, 0.62)], horizon: up)).status,
          AdsbStatus.matched);
    });

    test("a tilted horizon turns the prediction with it", () {
      // 10 degrees right of the nose, with the horizon running down to the
      // right 20 degrees.
      final AdsbTarget right = _target("N1", 1 * cos(100 * pi / 180), 1 * sin(100 * pi / 180), 5000);
      const HorizonReport tilted = HorizonReport(
        source: HorizonSource.picture,
        tiltDegrees: 20,
        pitchDegrees: 0,
      );
      const AdsbMatcher tight = AdsbMatcher(toleranceDegrees: 2);
      expect(
          _only(_match([right], [_box(1, 0.630, 0.584)],
                  horizon: tilted, matcher: tight))
              .status,
          AdsbStatus.matched);
      // Where it would be without the tilt.
      expect(
          _only(_match([right], [_box(1, 0.638, 0.5)],
                  horizon: tilted, matcher: tight))
              .status,
          AdsbStatus.inView);
    });

    test("an aircraft in view with no box says how small it would look", () {
      final AdsbNote note = _only(_match([_target("N1", 0, 1, 5000)], []));
      expect(note.status, AdsbStatus.inView);
      expect(note.reason, contains("no box"));
      expect(note.reason, contains("7 px"));
    });

    test("one box is claimed by one aircraft", () {
      final AdsbPicture p = _match(
        [_target("N1", 0, 1, 5000), _target("N2", 0, 2, 5000)],
        [_box(1, 0.5, 0.5)],
      );
      expect(p.notes.where((AdsbNote n) => n.status == AdsbStatus.matched).length, 1);
      expect(p.notes.where((AdsbNote n) => n.status == AdsbStatus.inView).length, 1);
      // The nearer aircraft comes first and the closer prediction wins.
      expect(p.notes.first.label, "N1");
    });

    test("an aircraft too far away is called too far", () {
      final AdsbNote note = _only(_match([_target("N1", 0, 10, 5000)], []));
      expect(note.status, AdsbStatus.tooFar);
      expect(note.reason, contains("too far"));
      expect(note.distanceNm, closeTo(10, 0.2));
    });

    test("an aircraft behind is called behind", () {
      final AdsbNote note = _only(_match([_target("N1", 0, -1, 5000)], []));
      expect(note.status, AdsbStatus.behind);
      expect(note.reason, contains("behind"));
    });

    test("an aircraft beside the field of view says which side", () {
      // 45 degrees right of the nose, in front of the wing line.
      final AdsbNote note = _only(_match([_target("N1", -0.707, 0.707, 5000)], []));
      expect(note.status, AdsbStatus.outOfView);
      expect(note.reason, contains("right"));
      expect(note.reason, contains("33°"));
    });

    test("an aircraft far above the camera says it is above", () {
      final AdsbNote note = _only(_match([_target("N1", 0, 0.5, 8000)], []));
      expect(note.status, AdsbStatus.outOfView);
      expect(note.reason, contains("above"));
    });

    test("an aircraft on the ground is called that", () {
      final AdsbNote note =
          _only(_match([_target("N1", 0, 1, 5000, airborne: false)], []));
      expect(note.status, AdsbStatus.ground);
    });

    test("the aim offset moves everything sideways", () {
      final AdsbTarget ahead = _target("N1", 0, 1, 5000);
      // Aimed 30 degrees right, so the aircraft ahead is 30 left of center.
      expect(_only(_match([ahead], [_box(1, 0.5, 0.5)], yaw: 30)).status,
          AdsbStatus.inView);
      expect(_only(_match([ahead], [_box(1, 0.047, 0.5)], yaw: 30)).status,
          AdsbStatus.matched);
    });

    test("at low speed the heading is not trusted", () {
      final AdsbPicture p = _match(
        [_target("N1", 0, 1, 5000), _target("N2", 0, 10, 5000)],
        [_box(1, 0.5, 0.5)],
        ownship: _ownship(speed: 12),
      );
      expect(p.problem, contains("12 kt"));
      expect(p.notes.firstWhere((AdsbNote n) => n.label == "N1").status,
          AdsbStatus.unplaced);
      // Distance alone still decides what is too far.
      expect(p.notes.firstWhere((AdsbNote n) => n.label == "N2").status,
          AdsbStatus.tooFar);
      expect(p.labels, isEmpty);
    });

    test("with no GPS there is a problem and no notes", () {
      final AdsbPicture p = _match([_target("N1", 0, 1, 5000)], [], noOwnship: true);
      expect(p.problem, contains("No GPS"));
      expect(p.notes, isEmpty);
      expect(p.trafficCount, 1);
    });

    test("with no horizon the camera tilt is unknown", () {
      final AdsbPicture p = _match(
        [_target("N1", 0, 1, 5000)],
        [],
        horizon: HorizonReport.unknown,
      );
      expect(p.problem, contains("horizon"));
      expect(_only(p).status, AdsbStatus.unplaced);
    });
  });

  group("DecisionBoard", () {
    test("says the sensors disagree and are ignored", () {
      final DecisionBoard board = DecisionBoard();
      board.update(
        result: _result(
          horizon: const HorizonReport(
            source: HorizonSource.picture,
            tiltDegrees: 1,
            pitchDegrees: 0,
            sensorsAvailable: true,
            sensorTiltDiff: 12,
            sensorPitchDiff: 2,
          ),
        ),
        adsbPicture: AdsbPicture.empty,
      );
      final String text = board.sensors.map((BoardLine l) => l.text).join("\n");
      expect(text, contains("disagree"));
      expect(text, contains("12°"));
      expect(_horizonLine(board).tone, Tone.warn);
    });

    test("says the sensors agree", () {
      final DecisionBoard board = DecisionBoard();
      board.update(
        result: _result(
          horizon: const HorizonReport(
            source: HorizonSource.picture,
            tiltDegrees: 1,
            pitchDegrees: 0,
            sensorsAvailable: true,
            sensorTiltDiff: 1,
            sensorPitchDiff: 1,
          ),
        ),
        adsbPicture: AdsbPicture.empty,
      );
      expect(_horizonLine(board).text, contains("agree"));
      expect(_horizonLine(board).tone, Tone.good);
    });

    test("says when the model is off or the sky is busy", () {
      final DecisionBoard board = DecisionBoard();
      board.update(
        result: _result(modelAvailable: false, cluttered: true),
        adsbPicture: AdsbPicture.empty,
      );
      final String text = board.sensors.map((BoardLine l) => l.text).join("\n");
      expect(text, contains("Model: off"));
      expect(text, contains("Busy sky"));
    });

    test("a red target shows its ADS-B match", () {
      final DecisionBoard board = DecisionBoard();
      board.update(
        result: _result(notes: [_note(4, Verdict.red, "airplane", "Model says airplane (0.80).")]),
        adsbPicture: const AdsbPicture(
          notes: [],
          labels: {4: "N123AB 2.1nm"},
          trafficCount: 1,
        ),
      );
      expect(board.targets.single.text, contains("T4 RED"));
      expect(board.targets.single.text, contains("ADS-B: N123AB 2.1nm"));
      expect(board.targets.single.tone, Tone.alert);
    });

    test("a red target with no match says no ADS-B aircraft is there", () {
      final DecisionBoard board = DecisionBoard();
      board.update(
        result: _result(notes: [_note(4, Verdict.red, "airplane")]),
        adsbPicture: const AdsbPicture(notes: [], labels: {}, trafficCount: 2),
      );
      expect(board.targets.single.text, contains("No ADS-B aircraft is at that spot"));
    });

    test("when ADS-B cannot be placed a red target does not blame ADS-B", () {
      final DecisionBoard board = DecisionBoard();
      board.update(
        result: _result(notes: [_note(4, Verdict.red, "airplane")]),
        adsbPicture: const AdsbPicture(
          notes: [],
          labels: {},
          problem: "Speed 5 kt",
          trafficCount: 2,
        ),
      );
      expect(board.targets.single.text, isNot(contains("ADS-B")));
      expect(board.adsb.first.text, "Speed 5 kt");
    });

    test("no targets and no traffic have plain messages", () {
      final DecisionBoard board = DecisionBoard();
      board.update(result: _result(), adsbPicture: AdsbPicture.empty);
      expect(board.targets.single.text, contains("No targets"));
      expect(board.adsb.single.text, contains("No ADS-B traffic"));
    });

    test("ADS-B lines carry the reason for each aircraft", () {
      final DecisionBoard board = DecisionBoard();
      board.update(
        result: _result(),
        adsbPicture: const AdsbPicture(
          notes: [
            AdsbNote(
              label: "N9",
              status: AdsbStatus.tooFar,
              reason: "10.0 nm away: too far for the camera (limit about 3 nm).",
              distanceNm: 10,
            ),
          ],
          labels: {},
          trafficCount: 1,
        ),
      );
      expect(board.adsb.single.text, startsWith("N9: 10.0 nm away: too far"));
      expect(board.adsb.single.tone, Tone.muted);
    });

    group("history", () {
      final DateTime t0 = DateTime(2026, 1, 1, 12);

      DecisionBoard board() => DecisionBoard(minEventGap: Duration.zero);

      test("logs a target going from yellow to red", () {
        final DecisionBoard b = board();
        b.update(
            result: _result(notes: [_note(1, Verdict.yellow, "unchecked", "Waiting.")]),
            adsbPicture: AdsbPicture.empty,
            now: t0);
        b.update(
            result: _result(notes: [_note(1, Verdict.red, "airplane", "Model says airplane (0.7).")]),
            adsbPicture: AdsbPicture.empty,
            now: t0.add(const Duration(seconds: 1)));
        expect(b.events.length, 2);
        expect(b.events.last.text, startsWith("T1 yellow to RED"));
        expect(b.events.last.tone, Tone.alert);
      });

      test("does not log a number changing inside the same decision", () {
        final DecisionBoard b = board();
        for (int i = 0; i < 5; i++) {
          b.update(
              result: _result(notes: [_note(1, Verdict.yellow, "unconfirmed", "Looked $i times.")]),
              adsbPicture: AdsbPicture.empty,
              now: t0.add(Duration(seconds: i)));
        }
        expect(b.events.length, 1);
      });

      test("a target that is only being watched is not news", () {
        final DecisionBoard b = board();
        b.update(
            result: _result(notes: [_note(1, Verdict.watching, "steady")]),
            adsbPicture: AdsbPicture.empty,
            now: t0);
        expect(b.events, isEmpty);
      });

      test("logs a rejection", () {
        final DecisionBoard b = board();
        b.update(
            result: _result(notes: [_note(2, Verdict.rejected, "glass", "Windshield speck.")]),
            adsbPicture: AdsbPicture.empty,
            now: t0);
        expect(b.events.single.text, "T2 rejected: Windshield speck.");
        expect(b.events.single.tone, Tone.muted);
      });

      test("logs a box that disappears", () {
        final DecisionBoard b = board();
        b.update(
            result: _result(notes: [_note(3, Verdict.red, "airplane")]),
            adsbPicture: AdsbPicture.empty,
            now: t0);
        b.update(
            result: _result(),
            adsbPicture: AdsbPicture.empty,
            now: t0.add(const Duration(seconds: 1)));
        expect(b.events.last.text, "T3 lost: no longer seen (was RED).");
      });

      test("a rejected target that goes away is not mentioned again", () {
        final DecisionBoard b = board();
        b.update(
            result: _result(notes: [_note(3, Verdict.rejected, "glass")]),
            adsbPicture: AdsbPicture.empty,
            now: t0);
        b.update(
            result: _result(),
            adsbPicture: AdsbPicture.empty,
            now: t0.add(const Duration(seconds: 1)));
        expect(b.events.length, 1);
      });

      test("logs when the sensors stop agreeing with the picture", () {
        final DecisionBoard b = board();
        b.update(
            result: _result(),
            adsbPicture: AdsbPicture.empty,
            now: t0);
        b.update(
            result: _result(
              horizon: const HorizonReport(
                source: HorizonSource.picture,
                tiltDegrees: 0,
                pitchDegrees: 0,
                sensorsAvailable: true,
                sensorTiltDiff: 15,
              ),
            ),
            adsbPicture: AdsbPicture.empty,
            now: t0.add(const Duration(seconds: 3)));
        expect(b.events.single.text, contains("sensors disagree"));
      });

      test("logs ADS-B matches, but not an aircraft that was always too far", () {
        final DecisionBoard b = board();
        AdsbPicture picture(AdsbStatus status) => AdsbPicture(
              notes: [
                AdsbNote(label: "N5", status: status, reason: "r", distanceNm: 2),
                const AdsbNote(
                    label: "N6", status: AdsbStatus.tooFar, reason: "far", distanceNm: 9),
              ],
              labels: const {},
              trafficCount: 2,
            );
        b.update(result: _result(), adsbPicture: picture(AdsbStatus.inView), now: t0);
        b.update(
            result: _result(),
            adsbPicture: picture(AdsbStatus.matched),
            now: t0.add(const Duration(seconds: 1)));
        expect(b.events.map((BoardEvent e) => e.text),
            ["ADS-B N5: r", "ADS-B N5: r"]);
        expect(b.events.any((BoardEvent e) => e.text.contains("N6")), isFalse);
      });

      test("the same thing is not logged again inside the gap", () {
        final DecisionBoard b = DecisionBoard(minEventGap: const Duration(seconds: 5));
        b.update(
            result: _result(notes: [_note(1, Verdict.yellow, "a")]),
            adsbPicture: AdsbPicture.empty,
            now: t0);
        b.update(
            result: _result(notes: [_note(1, Verdict.rejected, "b")]),
            adsbPicture: AdsbPicture.empty,
            now: t0.add(const Duration(seconds: 1)));
        expect(b.events.length, 1);
      });

      test("the log is capped", () {
        final DecisionBoard b = DecisionBoard(maxEvents: 5, minEventGap: Duration.zero);
        for (int i = 1; i <= 12; i++) {
          b.update(
              result: _result(notes: [_note(i, Verdict.rejected, "glass")]),
              adsbPicture: AdsbPicture.empty,
              now: t0.add(Duration(seconds: i)));
        }
        expect(b.events.length, 5);
        expect(b.events.last.text, startsWith("T12"));
      });

      test("clear forgets everything", () {
        final DecisionBoard b = board();
        b.update(
            result: _result(notes: [_note(1, Verdict.red, "airplane")]),
            adsbPicture: AdsbPicture.empty,
            now: t0);
        b.clear();
        expect(b.events, isEmpty);
        expect(b.targets, isEmpty);
      });
    });
  });

  group("WhyPanel", () {
    Widget host(DecisionBoard board, VoidCallback onClose) {
      return MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: WhyPanel(board: board, onClose: onClose),
          ),
        ),
      );
    }

    testWidgets("shows each tab and closes", (WidgetTester tester) async {
      final DecisionBoard board = DecisionBoard(minEventGap: Duration.zero);
      board.update(
        result: _result(notes: [_note(7, Verdict.red, "airplane", "Model says airplane (0.80).")]),
        adsbPicture: const AdsbPicture(
          notes: [
            AdsbNote(
                label: "N77",
                status: AdsbStatus.tooFar,
                reason: "9.0 nm away: too far for the camera.",
                distanceNm: 9),
          ],
          labels: {},
          trafficCount: 1,
        ),
      );
      bool closed = false;
      await tester.pumpWidget(host(board, () => closed = true));
      expect(find.textContaining("T7 RED"), findsOneWidget);

      await tester.tap(find.text("Sensors"));
      await tester.pump();
      expect(find.textContaining("Horizon from the picture"), findsOneWidget);

      await tester.tap(find.text("ADS-B"));
      await tester.pump();
      expect(find.textContaining("N77: 9.0 nm away"), findsOneWidget);

      await tester.tap(find.text("History"));
      await tester.pump();
      expect(find.textContaining("T7 RED"), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      expect(closed, isTrue);
    });

    testWidgets("says so when there is nothing to show", (WidgetTester tester) async {
      await tester.pumpWidget(host(DecisionBoard(), () {}));
      await tester.tap(find.text("History"));
      await tester.pump();
      expect(find.text("No decisions yet."), findsOneWidget);
    });
  });
}
