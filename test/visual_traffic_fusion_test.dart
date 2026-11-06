import 'dart:math';

import 'package:avaremp/visual_traffic/adsb_matcher.dart';
import 'package:avaremp/visual_traffic/attitude_filter.dart';
import 'package:avaremp/visual_traffic/decision_board.dart';
import 'package:avaremp/visual_traffic/decisions.dart';
import 'package:avaremp/visual_traffic/detection_models.dart';
import 'package:avaremp/visual_traffic/frame_analyzer.dart';
import 'package:avaremp/visual_traffic/gyro_motion.dart';
import 'package:avaremp/visual_traffic/horizon.dart';
import 'package:flutter_test/flutter_test.dart';

const double _g = 9.80665;

void main() {
  group("deviceToCamera", () {
    test("upright phone: the camera's down is the phone's down", () {
      // At rest the accelerometer reads +g up the phone's y axis.
      final Vec3 a = deviceToCamera(0, 0, _g, 0);
      expect(a.x, closeTo(0, 1e-9));
      expect(a.y, closeTo(-_g, 1e-9));
      expect(a.z, closeTo(0, 1e-9));
    });

    test("every orientation is a pure rotation of the axes", () {
      for (final int degrees in [0, 90, 180, 270]) {
        final Vec3 x = deviceToCamera(degrees, 1, 0, 0);
        final Vec3 y = deviceToCamera(degrees, 0, 1, 0);
        final Vec3 z = deviceToCamera(degrees, 0, 0, 1);
        // Unit length, at right angles, and not mirrored.
        double dot(Vec3 a, Vec3 b) => a.x * b.x + a.y * b.y + a.z * b.z;
        expect(dot(x, x), closeTo(1, 1e-9));
        expect(dot(x, y), closeTo(0, 1e-9));
        expect(dot(y, z), closeTo(0, 1e-9));
        final double det = x.x * (y.y * z.z - y.z * z.y) -
            x.y * (y.x * z.z - y.z * z.x) +
            x.z * (y.x * z.y - y.y * z.x);
        expect(det, closeTo(1, 1e-9));
      }
    });

    test("a phone on its side still sees down as down", () {
      // Top of the phone to the left: the phone's x axis points up, so the
      // floor pushes along +x. Top to the right: along -x.
      expect(deviceToCamera(90, _g, 0, 0).y, closeTo(-_g, 1e-9));
      expect(deviceToCamera(270, -_g, 0, 0).y, closeTo(-_g, 1e-9));
      // Upside down: the floor pushes along -y.
      expect(deviceToCamera(180, 0, -_g, 0).y, closeTo(-_g, 1e-9));
    });
  });

  group("AttitudeFilter", () {
    test("starts from the accelerometer", () {
      final AttitudeFilter f = AttitudeFilter();
      expect(f.gravity, isNull);
      f.onAccel(const Vec3(0, -_g, 0), 0);
      expect(f.hasAttitude, isTrue);
      final h = f.horizon!;
      expect(h.tilt, closeTo(0, 1e-6));
      expect(h.pitch, closeTo(0, 1e-6));
    });

    test("a gyroscope turn about the right axis tips the camera up", () {
      final AttitudeFilter f = AttitudeFilter();
      f.onAccel(const Vec3(0, -_g, 0), 0);
      // 10 degrees a second for a second, in 20 ms steps.
      for (int i = 0; i <= 50; i++) {
        f.onGyro(Vec3(10 * pi / 180, 0, 0), i * 20);
      }
      expect(f.horizon!.pitch, closeTo(10, 0.5));
      expect(f.horizon!.tilt, closeTo(0, 0.5));
    });

    test("a gyroscope turn about the lens axis rolls the horizon", () {
      final AttitudeFilter f = AttitudeFilter();
      f.onAccel(const Vec3(0, -_g, 0), 0);
      for (int i = 0; i <= 50; i++) {
        f.onGyro(Vec3(0, 0, 10 * pi / 180), i * 20);
      }
      // Right wing down: the horizon climbs toward the right.
      expect(f.horizon!.tilt, closeTo(-10, 0.5));
      expect(f.horizon!.pitch, closeTo(0, 0.5));
    });

    test("the horizon in the picture pulls the estimate to it", () {
      final AttitudeFilter f = AttitudeFilter();
      f.onAccel(const Vec3(0, -_g, 0), 0);
      for (int i = 0; i < 40; i++) {
        f.onPicture(12, -5);
      }
      expect(f.horizon!.tilt, closeTo(12, 0.5));
      expect(f.horizon!.pitch, closeTo(-5, 0.5));
    });

    test("the picture can set the first estimate with no accelerometer", () {
      final AttitudeFilter f = AttitudeFilter();
      f.onPicture(8, 3);
      expect(f.horizon!.tilt, closeTo(8, 1e-6));
      expect(f.horizon!.pitch, closeTo(3, 1e-6));
    });

    test("agrees with the sensor horizon built from the same direction", () {
      final AttitudeFilter f = AttitudeFilter();
      f.onPicture(10, 4);
      final gravity = f.gravity!;
      final HorizonLine line = HorizonLine.fromGravity(
          gx: gravity.x, gy: gravity.y, gz: gravity.z, fovH: 65, aspect: 16 / 9)!;
      expect(line.tiltDegrees(16 / 9), closeTo(10, 2));
      expect(line.pitchDegrees(65, 16 / 9)!, closeTo(4, 1.5));
    });

    test("an accelerometer pushed around by a turn is ignored", () {
      final AttitudeFilter f = AttitudeFilter(accelTimeConstant: 1);
      f.onAccel(const Vec3(0, -_g, 0), 0);
      // A 40 degree bank: the reading is bigger than gravity and tilted.
      final double bank = 40 * pi / 180;
      for (int i = 1; i <= 100; i++) {
        f.onAccel(Vec3(_g / cos(bank) * sin(bank), -_g / cos(bank) * cos(bank), 0), i * 100);
      }
      expect(f.horizon!.tilt.abs(), lessThan(0.5));
    });

    test("a steady accelerometer slowly pulls the estimate", () {
      final AttitudeFilter f = AttitudeFilter(accelTimeConstant: 1);
      f.onAccel(const Vec3(0, -_g, 0), 0);
      for (int i = 0; i <= 50; i++) {
        f.onGyro(Vec3(10 * pi / 180, 0, 0), i * 20);
      }
      expect(f.horizon!.pitch, greaterThan(5));
      // The accelerometer says level, and enough time passes.
      for (int i = 1; i <= 100; i++) {
        f.onAccel(const Vec3(0, -_g, 0), 1000 + i * 100);
      }
      expect(f.horizon!.pitch.abs(), lessThan(0.5));
    });

    test("counts rotation between frames and starts over", () {
      final AttitudeFilter f = AttitudeFilter();
      for (int i = 0; i <= 25; i++) {
        f.onGyro(Vec3(0, 0.2, 0), i * 20);
      }
      final MotionHint first = f.takeRotation();
      expect(first.ry, closeTo(0.2 * 0.5, 0.01));
      expect(first.rx, 0);
      expect(f.takeRotation().ry, 0);
    });

    test("ignores a long gap between gyroscope readings", () {
      final AttitudeFilter f = AttitudeFilter();
      f.onAccel(const Vec3(0, -_g, 0), 0);
      f.onGyro(const Vec3(1, 0, 0), 0);
      f.onGyro(const Vec3(1, 0, 0), 5000);
      expect(f.horizon!.pitch, closeTo(0, 1e-6));
      expect(f.rotation.rx, 0);
    });

    test("the gyroscope carries the GPS heading between fixes", () {
      final AttitudeFilter f = AttitudeFilter();
      f.onAccel(const Vec3(0, -_g, 0), 0);
      f.onGps(90, "fix1");
      expect(f.heading, closeTo(90, 1e-9));
      // Turning right 3 degrees a second about the down axis for 2 seconds.
      for (int i = 0; i <= 100; i++) {
        f.onGyro(Vec3(0, 3 * pi / 180, 0), i * 20);
      }
      expect(f.heading, closeTo(96, 0.3));
      expect(f.yawSinceFix, closeTo(6, 0.3));
      // The same fix again changes nothing.
      f.onGps(90, "fix1");
      expect(f.heading, closeTo(96, 0.3));
      // A new fix takes over.
      f.onGps(95, "fix2");
      expect(f.heading, closeTo(95, 1e-9));
      expect(f.yawSinceFix, 0);
    });

    test("heading wraps around north and is null with no GPS track", () {
      final AttitudeFilter f = AttitudeFilter();
      f.onAccel(const Vec3(0, -_g, 0), 0);
      expect(f.heading, isNull);
      f.onGps(359, "a");
      for (int i = 0; i <= 100; i++) {
        f.onGyro(Vec3(0, 3 * pi / 180, 0), i * 20);
      }
      expect(f.heading, closeTo(5, 0.3));
      f.onGps(null, "b");
      expect(f.heading, isNull);
    });

    test("turning about the down axis does not change down", () {
      final AttitudeFilter f = AttitudeFilter();
      f.onAccel(const Vec3(0, -_g, 0), 0);
      for (int i = 0; i <= 100; i++) {
        f.onGyro(Vec3(0, 0.5, 0), i * 20);
      }
      expect(f.horizon!.tilt.abs(), lessThan(0.1));
      expect(f.horizon!.pitch.abs(), lessThan(0.1));
    });

    test("reset forgets everything", () {
      final AttitudeFilter f = AttitudeFilter();
      f.onAccel(const Vec3(0, -_g, 0), 0);
      f.onGps(10, "a");
      f.reset();
      expect(f.gravity, isNull);
      expect(f.heading, isNull);
    });
  });

  group("GyroMotion", () {
    GyroPrediction p(double dx, [double dy = 0]) => GyroPrediction(dx, dy);

    test("predicts a turn to the right as a positive slide", () {
      final GyroMotion g = GyroMotion();
      final GyroPrediction slide = g.predict(const MotionHint(0, 0.01, 0), 65, 640);
      // 0.01 rad at a focal length of about 502 pixels.
      expect(slide.dx, closeTo(5.02, 0.05));
      expect(slide.dy, closeTo(0, 1e-9));
    });

    test("is not trusted until it has been compared", () {
      final GyroMotion g = GyroMotion();
      expect(g.expected(p(3)), isNull);
      expect(g.report(p(3), filledIn: false).state, GyroState.learning);
    });

    test("is trusted after it matches the picture", () {
      final GyroMotion g = GyroMotion();
      for (int i = 0; i < 20; i++) {
        final double v = [2.0, 4.0, 3.0, 5.0][i % 4];
        g.learn(p(v), v, 0);
      }
      final GyroPrediction? e = g.expected(p(3));
      expect(e, isNotNull);
      expect(e!.dx, closeTo(3, 0.1));
      // No turning about the other axis was seen, so it counts as none.
      expect(e.dy, 0);
      final GyroReport r = g.report(p(3), filledIn: true);
      expect(r.state, GyroState.agrees);
      expect(r.correlation!, closeTo(1, 0.01));
      expect(r.scaleX!, closeTo(1, 0.05));
      expect(r.filledIn, isTrue);
    });

    test("a sensor that reads backwards is corrected", () {
      final GyroMotion g = GyroMotion();
      for (int i = 0; i < 20; i++) {
        final double v = [2.0, 4.0, 3.0, 5.0][i % 4];
        g.learn(p(v), -v, 0);
      }
      expect(g.expected(p(3))!.dx, closeTo(-3, 0.1));
    });

    test("a sensor of the wrong size is scaled", () {
      final GyroMotion g = GyroMotion();
      for (int i = 0; i < 20; i++) {
        final double v = [2.0, 4.0, 3.0, 5.0][i % 4];
        g.learn(p(v), v * 1.5, 0);
      }
      expect(g.expected(p(2))!.dx, closeTo(3, 0.15));
    });

    test("a sensor that is far off in size is not used", () {
      final GyroMotion g = GyroMotion();
      for (int i = 0; i < 20; i++) {
        final double v = [2.0, 4.0, 3.0, 5.0][i % 4];
        g.learn(p(v), v * 0.1, 0);
      }
      expect(g.expected(p(3)), isNull);
      expect(g.report(p(3), filledIn: false).state, GyroState.mismatch);
    });

    test("noise that does not follow the picture is not used", () {
      final GyroMotion g = GyroMotion();
      for (int i = 0; i < 30; i++) {
        g.learn(p(i.isEven ? 3 : -3), 2, 0);
      }
      expect(g.expected(p(3)), isNull);
      expect(g.report(p(3), filledIn: false).state, GyroState.mismatch);
    });

    test("a slide that hit the search limit is not learned from", () {
      final GyroMotion g = GyroMotion();
      for (int i = 0; i < 30; i++) {
        g.learn(p(6), 8, 0);
      }
      expect(g.report(p(6), filledIn: false).state, GyroState.learning);
    });

    test("each axis is judged on its own", () {
      final GyroMotion g = GyroMotion();
      for (int i = 0; i < 20; i++) {
        final double v = [2.0, 4.0, 3.0, 5.0][i % 4];
        g.learn(p(v, v), v, v);
      }
      final GyroPrediction e = g.expected(p(3, 2))!;
      expect(e.dx, closeTo(3, 0.1));
      expect(e.dy, closeTo(2, 0.1));
    });

    test("reset forgets what was learned", () {
      final GyroMotion g = GyroMotion();
      for (int i = 0; i < 20; i++) {
        g.learn(p(3), 3, 0);
      }
      g.reset();
      expect(g.expected(p(3)), isNull);
    });
  });

  group("AdsbMatcher fusion", () {
    const double lat = 37;
    const double lon = -122;
    const HorizonReport level = HorizonReport(
      source: HorizonSource.picture,
      tiltDegrees: 0,
      pitchDegrees: 0,
    );
    const OwnshipFix own = OwnshipFix(
      latitude: lat,
      longitude: lon,
      altitudeFt: 5000,
      speedKnots: 100,
      trackDegrees: 90,
    );

    AdsbTarget ahead(String label, double nm, {double altFt = 5000, double northNm = 0}) {
      return AdsbTarget(
        label: label,
        latitude: lat + northNm / 60,
        longitude: lon + nm / (60 * cos(lat * pi / 180)),
        altitudeFt: altFt,
      );
    }

    DetectionBox box(int id, double cx, double cy,
        {DetectionTier tier = DetectionTier.possible}) {
      return DetectionBox(
        id: id,
        x: cx - 0.01,
        y: cy - 0.01,
        w: 0.02,
        h: 0.02,
        confidence: 0.5,
        tier: tier,
      );
    }

    AdsbPicture run(List<AdsbTarget> traffic, List<DetectionBox> boxes,
        {AdsbMatcher matcher = const AdsbMatcher()}) {
      return matcher.match(
        ownship: own,
        traffic: traffic,
        boxes: boxes,
        fovH: 65,
        fovV: 39.6,
        pictureWidth: 1280,
        pictureHeight: 720,
        horizon: level,
      );
    }

    test("a yellow box right on an ADS-B aircraft is promoted", () {
      final AdsbPicture p = run([ahead("N1", 1)], [box(7, 0.5, 0.5)]);
      expect(p.promoted, {7: "N1"});
      expect(p.notes.single.errorDegrees, closeTo(0, 0.1));
    });

    test("a yellow box a little farther off is matched but not promoted", () {
      // 4.5 degrees to the right is about 0.069 of the picture width.
      final AdsbPicture p = run([ahead("N1", 1)], [box(7, 0.57, 0.5)]);
      expect(p.notes.single.status, AdsbStatus.matched);
      expect(p.promoted, isEmpty);
    });

    test("a red box is already red and is not listed as promoted", () {
      final AdsbPicture p = run(
        [ahead("N1", 1)],
        [box(7, 0.5, 0.5, tier: DetectionTier.airplane)],
      );
      expect(p.promoted, isEmpty);
      expect(p.labels[7], isNotNull);
    });

    test("promotion can be switched off", () {
      final AdsbPicture p = run(
        [ahead("N1", 1)],
        [box(7, 0.5, 0.5)],
        matcher: const AdsbMatcher(promoteDegrees: -1),
      );
      expect(p.promoted, isEmpty);
      expect(p.notes.single.status, AdsbStatus.matched);
    });

    test("an aircraft in the picture with no box becomes a cue", () {
      final AdsbPicture p = run([ahead("N1", 0.8)], []);
      expect(p.cues.single.key, "N1");
      expect(p.cues.single.u, closeTo(0.5, 0.01));
      expect(p.cues.single.v, closeTo(0.5, 0.01));
      expect(p.cues.single.distanceNm, closeTo(0.8, 0.05));
      expect(p.cues.single.expectedPixels, greaterThan(5));
    });

    test("an aircraft that has a tracked box needs no cue", () {
      final AdsbPicture p = run([ahead("N1", 1)], [box(7, 0.5, 0.5)]);
      expect(p.cues, isEmpty);
    });

    test("an aircraft matched to a box made only by a cue stays a cue", () {
      final AdsbPicture p = run(
        [ahead("N1", 1)],
        [box(-1, 0.5, 0.5, tier: DetectionTier.airplane)],
      );
      expect(p.cues.single.key, "N1");
      expect(p.notes.single.reason, contains("A1"));
    });

    test("aircraft outside the picture, behind, or too far are not cues", () {
      final AdsbPicture p = run([
        ahead("FAR", 10),
        ahead("BEHIND", -1),
        ahead("SIDE", 0.7, northNm: -0.7),
      ], []);
      expect(p.cues, isEmpty);
    });

    test("only the nearest few become cues", () {
      final AdsbPicture p = run([
        ahead("A", 2.5),
        ahead("B", 0.5),
        ahead("C", 1.0),
        ahead("D", 2.0),
        ahead("E", 1.5),
      ], []);
      expect(p.cues.map((Cue c) => c.key), ["B", "C", "E"]);
    });

    test("cues can be switched off", () {
      final AdsbPicture p =
          run([ahead("N1", 1)], [], matcher: const AdsbMatcher(maxCues: 0));
      expect(p.cues, isEmpty);
    });
  });

  group("DecisionBoard fusion", () {
    AnalysisResult result({
      List<TargetNote> notes = const [],
      GyroReport gyro = GyroReport.none,
      List<CueResult> cues = const [],
    }) {
      return AnalysisResult(
        frame: const DetectionFrame(
            seq: 1, timestampMs: 0, fovH: 65, fovV: 39.6, boxes: []),
        pictureWidth: 1280,
        pictureHeight: 720,
        horizon: null,
        cluttered: false,
        spots: 0,
        tracks: notes.length,
        modelRuns: 0,
        modelAvailable: true,
        milliseconds: 5,
        notes: notes,
        gyroReport: gyro,
        cueResults: cues,
      );
    }

    String sensors(DecisionBoard b) => b.sensors.map((BoardLine l) => l.text).join("\n");

    test("shows what position and heading came to", () {
      final DecisionBoard b = DecisionBoard();
      b.update(
        result: result(),
        adsbPicture: AdsbPicture.empty,
        ownship: const OwnshipFix(
            latitude: 37, longitude: -122, altitudeFt: 5000, speedKnots: 112, trackDegrees: 92),
        heading: 92,
        gpsTrack: 90,
      );
      expect(sensors(b), contains("112 kt, 5000 ft"));
      expect(sensors(b), contains("Heading 92°"));
      expect(sensors(b), contains("+2° from the gyroscope"));
    });

    test("says when there is no GPS or the speed is too low", () {
      final DecisionBoard none = DecisionBoard();
      none.update(result: result(), adsbPicture: AdsbPicture.empty);
      expect(sensors(none), contains("no GPS fix"));
      final DecisionBoard slow = DecisionBoard();
      slow.update(
        result: result(),
        adsbPicture: AdsbPicture.empty,
        ownship: const OwnshipFix(
            latitude: 37, longitude: -122, altitudeFt: 100, speedKnots: 8),
      );
      expect(sensors(slow), contains("not trusted at this speed"));
    });

    test("describes each gyroscope state", () {
      String line(GyroReport g) {
        final DecisionBoard b = DecisionBoard();
        b.update(result: result(gyro: g), adsbPicture: AdsbPicture.empty);
        return b.sensors.firstWhere((BoardLine l) => l.text.startsWith("Gyroscope")).text;
      }

      expect(line(GyroReport.none), contains("no readings"));
      expect(line(const GyroReport(state: GyroState.learning)), contains("waiting"));
      expect(
          line(const GyroReport(state: GyroState.agrees, correlation: 0.93)),
          allOf(contains("agrees"), contains("0.93")));
      expect(
          line(const GyroReport(state: GyroState.agrees, filledIn: true)),
          contains("supplied the slide"));
      expect(
          line(const GyroReport(state: GyroState.mismatch, correlation: 0.2)),
          contains("does not match"));
    });

    test("a promoted yellow target is reported red with the ADS-B reason", () {
      final DecisionBoard b = DecisionBoard();
      b.update(
        result: result(notes: [
          const TargetNote(
              id: 5,
              x: 0.5,
              y: 0.5,
              verdict: Verdict.yellow,
              code: "unconfirmed",
              reason: "Moves steadily."),
        ]),
        adsbPicture: const AdsbPicture(
          notes: [
            AdsbNote(
              label: "N1",
              status: AdsbStatus.matched,
              reason: "r",
              distanceNm: 2.1,
              boxId: 5,
              errorDegrees: 1.3,
            ),
          ],
          labels: {5: "N1 2.1nm"},
          promoted: {5: "N1"},
          trafficCount: 1,
        ),
      );
      final String text = b.targets.single.text;
      expect(text, startsWith("T5 RED"));
      expect(text, contains("lines up with ADS-B N1"));
      expect(text, contains("2.1 nm"));
      expect(text, contains("1.3° off"));
      expect(text, contains("model has not confirmed"));
      expect(b.targets.single.tone, Tone.alert);
    });

    test("a box made by a cue is named A1", () {
      final DecisionBoard b = DecisionBoard();
      b.update(
        result: result(notes: [
          const TargetNote(
              id: -1,
              x: 0.5,
              y: 0.5,
              verdict: Verdict.red,
              code: "adsb-cue",
              reason: "ADS-B says N1 is about here."),
        ]),
        adsbPicture: AdsbPicture.empty,
      );
      expect(b.targets.single.text, startsWith("A1 RED"));
    });

    test("an in-view aircraft shows what the model saw when it looked", () {
      AdsbPicture picture() => const AdsbPicture(
            notes: [
              AdsbNote(
                  label: "N1",
                  status: AdsbStatus.inView,
                  reason: "1.0 nm away and in the picture, but no box.",
                  distanceNm: 1),
            ],
            labels: {},
            trafficCount: 1,
          );
      String line(List<CueResult> cues) {
        final DecisionBoard b = DecisionBoard();
        b.update(result: result(cues: cues), adsbPicture: picture());
        return b.adsb.single.text;
      }

      expect(line(const []), isNot(contains("model")));
      expect(line(const [CueResult(key: "N1", checks: 0, bestScore: 0, airplane: false)]),
          contains("Waiting for the model"));
      expect(line(const [CueResult(key: "N1", checks: 2, bestScore: 0.12, airplane: false)]),
          allOf(contains("looked there 2 times"), contains("0.12")));
      expect(line(const [CueResult(key: "N1", checks: 1, bestScore: 0.6, airplane: true)]),
          contains("model sees an airplane there"));
    });

    test("logs the gyroscope starting and stopping agreeing", () {
      final DecisionBoard b = DecisionBoard(minEventGap: Duration.zero);
      final DateTime t = DateTime(2026, 1, 1, 12);
      b.update(
          result: result(gyro: const GyroReport(state: GyroState.learning)),
          adsbPicture: AdsbPicture.empty,
          now: t);
      b.update(
          result: result(gyro: const GyroReport(state: GyroState.agrees)),
          adsbPicture: AdsbPicture.empty,
          now: t.add(const Duration(seconds: 1)));
      b.update(
          result: result(gyro: const GyroReport(state: GyroState.mismatch)),
          adsbPicture: AdsbPicture.empty,
          now: t.add(const Duration(seconds: 2)));
      expect(b.events.map((BoardEvent e) => e.text), [
        "Gyroscope now agrees with the picture.",
        "Gyroscope no longer matches the picture. Not used.",
      ]);
    });
  });
}
