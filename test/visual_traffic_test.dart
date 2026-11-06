import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:avaremp/visual_traffic/aircraft_detector.dart';
import 'package:avaremp/visual_traffic/analyzer_worker.dart';
import 'package:avaremp/visual_traffic/detection_models.dart';
import 'package:avaremp/visual_traffic/dot_detector.dart';
import 'package:avaremp/visual_traffic/frame_analyzer.dart';
import 'package:avaremp/visual_traffic/horizon.dart';
import 'package:avaremp/visual_traffic/luma_frame.dart';
import 'package:avaremp/visual_traffic/motion.dart';
import 'package:avaremp/visual_traffic/preview_encoder.dart';
import 'package:avaremp/visual_traffic/tracker.dart';
import 'package:flutter_test/flutter_test.dart';

/// A moving thing in the synthetic sky, in scene (world) pixels.
class _Thing {
  _Thing(this.x, this.y, this.size, this.value, {this.vx = 0, this.vy = 0});
  double x;
  double y;
  final int size;
  final int value;
  final double vx;
  final double vy;
}

/// Draws fake cockpit frames: a sky with soft clouds, a textured ground below
/// a horizon, small objects, and a windshield speck. The scene can pan.
class _Scene {
  _Scene({
    this.horizonY = 0.62,
    this.tilt = 0.0,
  });

  final int width = 1280;
  final int height = 720;
  final double horizonY;

  /// Horizon slope in pixels of height per pixel of width.
  final double tilt;

  final List<_Thing> things = [];
  final List<_Thing> glass = [];
  final Random _noise = Random(3);
  double panX = 0;
  double panY = 0;

  static int _hash(int a, int b) {
    int h = a * 374761393 + b * 668265263;
    h = (h ^ (h >> 13)) * 1274126177;
    return (h ^ (h >> 16)) & 0xFFFF;
  }

  double _horizonAt(int x) => horizonY * height + tilt * (x - width / 2);

  GrayImage frame({int noise = 2}) {
    final Uint8List data = Uint8List(width * height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final double line = _horizonAt(x);
        double v;
        if (y < line) {
          // Sky: brighter toward the top, plus two soft clouds fixed in the
          // scene so they slide when the scene pans.
          v = 175 + 25 * (1 - y / line);
          for (final List<double> cloud in const [
            [300.0, 150.0, 90.0],
            [900.0, 260.0, 120.0]
          ]) {
            final double dx = x + panX - cloud[0];
            final double dy = y + panY - cloud[1];
            v += 14 * exp(-(dx * dx + dy * dy) / (2 * cloud[2] * cloud[2] / 4));
          }
        } else {
          // Ground: coarse blocks of changing brightness, fixed in the scene.
          final int wx = (x + panX).floor();
          final int wy = (y + panY).floor();
          v = 70 + (_hash(wx ~/ 6, wy ~/ 6) % 60);
        }
        if (noise > 0) {
          v += _noise.nextInt(2 * noise + 1) - noise;
        }
        data[y * width + x] = v.round().clamp(0, 255);
      }
    }
    for (final _Thing t in things) {
      _paint(data, t.x - panX, t.y - panY, t.size, t.value);
    }
    for (final _Thing t in glass) {
      _paint(data, t.x, t.y, t.size, t.value);
    }
    return GrayImage(width, height, data);
  }

  void _paint(Uint8List data, double cx, double cy, int size, int value) {
    final int x0 = (cx - size / 2).round();
    final int y0 = (cy - size / 2).round();
    for (int y = y0; y < y0 + size; y++) {
      for (int x = x0; x < x0 + size; x++) {
        if (x >= 0 && x < width && y >= 0 && y < height) {
          data[y * width + x] = value;
        }
      }
    }
  }

  void step({double pan = 0}) {
    for (final _Thing t in things) {
      t.x += t.vx;
      t.y += t.vy;
    }
    panX += pan;
  }
}

class _FakeConfirmer implements AircraftConfirmer {
  _FakeConfirmer(this.classId, this.score);
  final int classId;
  final double score;
  int calls = 0;

  @override
  List<ObjectHit> detect(LumaFrame frame, double cx, double cy, double side) {
    calls++;
    return [
      ObjectHit(
        classId: classId,
        score: score,
        x1: cx - 20,
        y1: cy - 20,
        x2: cx + 20,
        y2: cy + 20,
      ),
    ];
  }

  @override
  void close() {}
}

List<DetectionBox> _run(
  FrameAnalyzer analyzer,
  _Scene scene,
  int frames, {
  double pan = 0,
  GravityHint? gravity,
}) {
  List<DetectionBox> boxes = const [];
  for (int i = 0; i < frames; i++) {
    final AnalysisResult result = analyzer.process(
      LumaFrame.fromGray(scene.frame()),
      timestampMs: 1000 + i * 100,
      gravity: gravity,
    );
    boxes = result.frame.boxes;
    scene.step(pan: pan);
  }
  return boxes;
}

void main() {
  group("LumaFrame", () {
    // A 4 wide by 2 tall source whose pixel value is its own index.
    final Uint8List bytes = Uint8List.fromList(<int>[0, 1, 2, 3, 4, 5, 6, 7]);

    LumaFrame turned(int turns) => LumaFrame(
          bytes: bytes,
          sourceWidth: 4,
          sourceHeight: 2,
          rowStride: 4,
          quarterTurns: turns,
        );

    test("no turn", () {
      final LumaFrame f = turned(0);
      expect(f.width, 4);
      expect(f.height, 2);
      expect(f.at(0, 0), 0);
      expect(f.at(3, 1), 7);
    });

    test("one clockwise turn puts the bottom left corner at the top left", () {
      final LumaFrame f = turned(1);
      expect(f.width, 2);
      expect(f.height, 4);
      // Source bottom-left (4) goes top-left. Source top-left (0) goes
      // top-right.
      expect(f.at(0, 0), 4);
      expect(f.at(1, 0), 0);
      expect(f.at(0, 3), 7);
      expect(f.at(1, 3), 3);
    });

    test("two turns flip the picture", () {
      final LumaFrame f = turned(2);
      expect(f.at(0, 0), 7);
      expect(f.at(3, 1), 0);
    });

    test("three turns are one counter-clockwise turn", () {
      final LumaFrame f = turned(3);
      expect(f.width, 2);
      expect(f.height, 4);
      // Source top-right (3) goes top-left. Source top-left (0) goes
      // bottom-left.
      expect(f.at(0, 0), 3);
      expect(f.at(0, 3), 0);
      expect(f.at(1, 0), 7);
    });

    test("row padding is skipped", () {
      final Uint8List padded = Uint8List.fromList(
          <int>[1, 2, 3, 99, 99, 4, 5, 6, 99, 99]);
      final LumaFrame f = LumaFrame(
        bytes: padded,
        sourceWidth: 3,
        sourceHeight: 2,
        rowStride: 5,
        quarterTurns: 0,
      );
      expect(f.at(2, 0), 3);
      expect(f.at(0, 1), 4);
      final GrayImage down = f.downscale(1);
      expect(down.data, <int>[1, 2, 3, 4, 5, 6]);
    });

    test("downscale averages blocks and bilinear sampling blends", () {
      final LumaFrame f = LumaFrame.fromGray(
          GrayImage(2, 2, Uint8List.fromList(<int>[0, 100, 100, 200])));
      expect(f.downscale(2).data, <int>[100]);
      expect(f.sample(0.5, 0.5), 100);
    });
  });

  group("HorizonLine", () {
    test("a level camera has the horizon in the middle", () {
      final HorizonLine? line = HorizonLine.fromGravity(
          gx: 0, gy: 1, gz: 0, fovH: 65, aspect: 16 / 9);
      expect(line, isNotNull);
      expect(line!.vLeft, closeTo(0.5, 1e-9));
      expect(line.vRight, closeTo(0.5, 1e-9));
      expect(line.skyAbove, isTrue);
    });

    test("looking up pushes the horizon down, looking down pushes it up", () {
      final double up = 10 * pi / 180;
      // Camera pitched up: forward has an upward part, so down has a part
      // along the lens axis, pointing backward.
      final HorizonLine lookingUp = HorizonLine.fromGravity(
          gx: 0, gy: cos(up), gz: -sin(up), fovH: 65, aspect: 16 / 9)!;
      expect(lookingUp.vLeft, greaterThan(0.5));
      final HorizonLine lookingDown = HorizonLine.fromGravity(
          gx: 0, gy: cos(up), gz: sin(up), fovH: 65, aspect: 16 / 9)!;
      expect(lookingDown.vLeft, lessThan(0.5));
    });

    test("a rolled camera tilts the line", () {
      final double roll = 10 * pi / 180;
      final HorizonLine line = HorizonLine.fromGravity(
          gx: sin(roll), gy: cos(roll), gz: 0, fovH: 65, aspect: 16 / 9)!;
      expect((line.vLeft - line.vRight).abs(), greaterThan(0.1));
    });

    test("sky test uses a margin so the line itself counts as ground", () {
      const HorizonLine line = HorizonLine(vLeft: 0.5, vRight: 0.5);
      expect(line.isSky(0.5, 0.2), isTrue);
      expect(line.isSky(0.5, 0.49), isFalse);
      expect(line.isSky(0.5, 0.8), isFalse);
    });

    test("an upside down camera has the sky below the line", () {
      final HorizonLine? line = HorizonLine.fromGravity(
          gx: 0, gy: -1, gz: 0, fovH: 65, aspect: 16 / 9);
      expect(line!.skyAbove, isFalse);
      expect(line.isSky(0.5, 0.9), isTrue);
    });
  });

  group("HorizonEstimator", () {
    test("finds a level horizon", () {
      final _Scene scene = _Scene(horizonY: 0.6);
      final GrayImage small = LumaFrame.fromGray(scene.frame()).downscale(10);
      final HorizonLine? line = HorizonEstimator().estimate(small);
      expect(line, isNotNull);
      expect(line!.vLeft, closeTo(0.6, 0.03));
      expect(line.vRight, closeTo(0.6, 0.03));
      expect(line.fromImage, isTrue);
    });

    test("finds a tilted horizon", () {
      final _Scene scene = _Scene(horizonY: 0.55, tilt: 0.12);
      final GrayImage small = LumaFrame.fromGray(scene.frame()).downscale(10);
      final HorizonLine? line = HorizonEstimator().estimate(small);
      expect(line, isNotNull);
      // Slope 0.12 px per px across 1280 wide, 720 tall.
      final double expectedLeft = 0.55 - 0.12 * 640 / 720;
      final double expectedRight = 0.55 + 0.12 * 640 / 720;
      expect(line!.vLeft, closeTo(expectedLeft, 0.04));
      expect(line.vRight, closeTo(expectedRight, 0.04));
    });

    test("finds nothing in empty sky", () {
      final Uint8List data = Uint8List(128 * 72)..fillRange(0, 128 * 72, 180);
      expect(HorizonEstimator().estimate(GrayImage(128, 72, data)), isNull);
    });
  });

  group("DotDetector", () {
    test("finds a small dark dot in smooth sky and nothing else", () {
      final _Scene scene = _Scene(horizonY: 0.9);
      scene.things.add(_Thing(400, 150, 4, 60));
      final GrayImage small = LumaFrame.fromGray(scene.frame()).downscale(2);
      final DotResult result = DotDetector()
          .detect(small, isSky: (double u, double v) => v < 0.85);
      expect(result.cluttered, isFalse);
      expect(result.candidates, isNotEmpty);
      final DotCandidate top = result.candidates.first;
      expect(top.x, closeTo(200, 2));
      expect(top.y, closeTo(75, 2));
      expect(top.contrast, lessThan(0));
    });

    test("drops big blobs and long streaks", () {
      final Uint8List data = Uint8List(200 * 100)..fillRange(0, 200 * 100, 180);
      // A 30 by 30 dark square and a 60 by 2 dark streak.
      for (int y = 20; y < 50; y++) {
        for (int x = 20; x < 50; x++) {
          data[y * 200 + x] = 60;
        }
      }
      for (int y = 70; y < 72; y++) {
        for (int x = 100; x < 160; x++) {
          data[y * 200 + x] = 60;
        }
      }
      final DotResult result =
          DotDetector().detect(GrayImage(200, 100, data));
      expect(result.candidates, isEmpty);
    });

    test("sensitivity changes how faint a dot can be", () {
      final Uint8List data = Uint8List(200 * 100)..fillRange(0, 200 * 100, 180);
      for (int y = 40; y < 43; y++) {
        for (int x = 80; x < 83; x++) {
          data[y * 200 + x] = 168;
        }
      }
      final GrayImage image = GrayImage(200, 100, data);
      expect(DotDetector().detect(image, sensitivity: 0.8).candidates, isEmpty);
      expect(DotDetector().detect(image, sensitivity: 1.5).candidates,
          isNotEmpty);
    });

    test("many spots in the sky count as clutter", () {
      final Uint8List data = Uint8List(300 * 150)..fillRange(0, 300 * 150, 180);
      for (int i = 0; i < 40; i++) {
        final int x = 12 + (i % 10) * 28;
        final int y = 12 + (i ~/ 10) * 30;
        for (int dy = 0; dy < 3; dy++) {
          for (int dx = 0; dx < 3; dx++) {
            data[(y + dy) * 300 + x + dx] = 60;
          }
        }
      }
      final DotResult result =
          DotDetector().detect(GrayImage(300, 150, data));
      expect(result.cluttered, isTrue);
      expect(result.skyCount, 40);
      expect(result.candidates.length, lessThanOrEqualTo(30));
    });

    test("spots below the horizon need to be much stronger", () {
      final Uint8List data = Uint8List(200 * 100)..fillRange(0, 200 * 100, 180);
      // Weak dot (diff 15) low in the picture, strong one (diff 130) too.
      for (int y = 80; y < 83; y++) {
        for (int x = 40; x < 43; x++) {
          data[y * 200 + x] = 165;
        }
        for (int x = 140; x < 143; x++) {
          data[y * 200 + x] = 50;
        }
      }
      final DotResult result = DotDetector().detect(
        GrayImage(200, 100, data),
        isSky: (double u, double v) => v < 0.5,
      );
      expect(result.candidates.length, 1);
      expect(result.candidates.first.below, isTrue);
      expect(result.candidates.first.x, closeTo(141.5, 1));
    });
  });

  group("MotionEstimator", () {
    test("measures a slide of the whole scene", () {
      final _Scene scene = _Scene(horizonY: 0.5);
      final GrayImage before = LumaFrame.fromGray(scene.frame(noise: 0)).downscale(2);
      scene.step(pan: 6); // scene content moves 6 px left in full resolution
      final GrayImage now = LumaFrame.fromGray(scene.frame(noise: 0)).downscale(2);
      final GlobalMotion motion = MotionEstimator().estimate(now, before);
      expect(motion.measured, isTrue);
      // Content moved left by 3 analysis px, so cur(x) = prev(x + 3).
      expect(motion.dx, closeTo(3, 1));
      expect(motion.dy, closeTo(0, 1));
    });

    test("an empty sky reports no measurement and no slide", () {
      final Uint8List data = Uint8List(320 * 180)..fillRange(0, 320 * 180, 180);
      final GrayImage image = GrayImage(320, 180, data);
      final GlobalMotion motion = MotionEstimator().estimate(
          image, image, prior: const GlobalMotion(5, 5, measured: true));
      expect(motion.measured, isFalse);
      expect(motion.dx, 0);
      expect(motion.dy, 0);
    });
  });

  group("Tracker", () {
    DotCandidate spot(double x, double y) => DotCandidate(
        x: x, y: y, width: 3, height: 3, area: 9, contrast: -100);

    test("a spot seen again and again becomes persistent", () {
      final Tracker tracker = Tracker();
      for (int i = 0; i < 12; i++) {
        tracker.update([spot(100, 50)], 0, 0);
      }
      expect(tracker.tracks.length, 1);
      expect(tracker.tracks.first.persistent, isTrue);
      expect(tracker.tracks.first.id, 1);
    });

    test("one that appears once and vanishes is dropped", () {
      final Tracker tracker = Tracker();
      tracker.update([spot(100, 50)], 0, 0);
      for (int i = 0; i < 10; i++) {
        tracker.update(const [], 0, 0);
      }
      expect(tracker.tracks, isEmpty);
    });

    test("a mover is followed with a stable id", () {
      final Tracker tracker = Tracker();
      for (int i = 0; i < 10; i++) {
        tracker.update([spot(100 + i * 1.5, 50)], 0, 0);
      }
      expect(tracker.tracks.length, 1);
      expect(tracker.tracks.first.id, 1);
      expect(tracker.tracks.first.moving, isTrue);
      expect(tracker.tracks.first.persistent, isTrue);
    });

    test("something that follows the scene is not a windshield speck", () {
      final Tracker tracker = Tracker();
      for (int i = 0; i < 12; i++) {
        // The scene slides 2 px a frame and the spot moves with it.
        final double slide = i * 2.0;
        tracker.update([spot(200 - slide, 50)], slide, 0);
      }
      expect(tracker.tracks.length, 1);
      expect(tracker.tracks.first.glass, isFalse);
    });

    test("a spot fixed in the picture while the scene slides is glass", () {
      final Tracker tracker = Tracker();
      for (int i = 0; i < 12; i++) {
        tracker.update([spot(100, 50)], i * 2.0, 0);
      }
      expect(tracker.tracks.first.glass, isTrue);
      expect(tracker.tracks.first.persistent, isFalse);
    });
  });

  group("YoloxDecoder", () {
    test("matches the reference decode of a real model output", () {
      final Map<String, dynamic> fixture = jsonDecode(
              File("test/data/yolox_airplane_sparse.json").readAsStringSync())
          as Map<String, dynamic>;
      final Float32List raw = Float32List(
          YoloxDecoder.anchorCount * YoloxDecoder.valuesPerAnchor);
      for (final dynamic entry in fixture["anchors"] as List<dynamic>) {
        final int index = entry["i"] as int;
        final List<dynamic> values = entry["v"] as List<dynamic>;
        for (int k = 0; k < values.length; k++) {
          raw[index * YoloxDecoder.valuesPerAnchor + k] =
              (values[k] as num).toDouble();
        }
      }
      final List<RawDetection> found = YoloxDecoder.decode(raw,
          scoreThreshold: 0.3, classes: {cocoAirplane, cocoBird});
      final Map<String, dynamic> expected =
          fixture["expected"] as Map<String, dynamic>;
      expect(found, isNotEmpty);
      // Overlapping boxes of the same class are merged into one.
      expect(found.length, 1);
      final RawDetection best = found.first;
      expect(best.classId, expected["classId"]);
      expect(best.score, closeTo((expected["score"] as num).toDouble(), 0.01));
      final List<dynamic> box = expected["box"] as List<dynamic>;
      expect(best.x1, closeTo((box[0] as num).toDouble(), 1.5));
      expect(best.y1, closeTo((box[1] as num).toDouble(), 1.5));
      expect(best.x2, closeTo((box[2] as num).toDouble(), 1.5));
      expect(best.y2, closeTo((box[3] as num).toDouble(), 1.5));
    });

    test("anchor count and an empty output", () {
      expect(YoloxDecoder.anchorCount, 3549);
      expect(
          YoloxDecoder.decode(Float32List(
              YoloxDecoder.anchorCount * YoloxDecoder.valuesPerAnchor)),
          isEmpty);
      expect(YoloxDecoder.decode(Float32List(10)), isEmpty);
    });
  });

  group("FrameAnalyzer", () {
    test("shows a yellow box on a small steady sky mover", () {
      final _Scene scene = _Scene();
      scene.things.add(_Thing(400, 150, 4, 60, vx: 1.2, vy: 0.2));
      final FrameAnalyzer analyzer = FrameAnalyzer();
      final List<DetectionBox> boxes = _run(analyzer, scene, 30);
      expect(boxes.length, 1);
      expect(boxes.first.tier, DetectionTier.possible);
      // The dot is at about (400 + 29*1.2, 150 + 29*0.2) of 1280 by 720.
      expect(boxes.first.centerX, closeTo((400 + 29 * 1.2) / 1280, 0.01));
      expect(boxes.first.centerY, closeTo((150 + 29 * 0.2) / 720, 0.015));
    });

    test("keeps one id for the same target", () {
      final _Scene scene = _Scene();
      scene.things.add(_Thing(400, 150, 4, 60, vx: 1.2));
      final FrameAnalyzer analyzer = FrameAnalyzer();
      _run(analyzer, scene, 20);
      final int first =
          _run(analyzer, scene, 1).firstWhere((_) => true).id;
      final int later =
          _run(analyzer, scene, 8).firstWhere((_) => true).id;
      expect(later, first);
    });

    test("a moving dot below the horizon is ignored without the model", () {
      final _Scene scene = _Scene(horizonY: 0.5);
      scene.things.add(_Thing(400, 520, 6, 250, vx: 1.5));
      final FrameAnalyzer analyzer = FrameAnalyzer();
      final List<DetectionBox> boxes = _run(analyzer, scene, 30);
      expect(boxes, isEmpty);
    });

    test("a speck stuck on the windshield is ignored while the scene pans", () {
      final _Scene scene = _Scene();
      scene.glass.add(_Thing(600, 120, 4, 40));
      final FrameAnalyzer analyzer = FrameAnalyzer();
      final List<DetectionBox> boxes = _run(analyzer, scene, 30, pan: 4);
      expect(boxes, isEmpty);
    });

    test("a model that calls it an airplane makes the box red", () {
      final _Scene scene = _Scene();
      scene.things.add(_Thing(400, 150, 4, 60, vx: 1.2));
      final _FakeConfirmer confirmer = _FakeConfirmer(cocoAirplane, 0.7);
      final FrameAnalyzer analyzer = FrameAnalyzer(confirmer: confirmer);
      final List<DetectionBox> boxes = _run(analyzer, scene, 30);
      expect(confirmer.calls, greaterThan(0));
      expect(boxes.length, 1);
      expect(boxes.first.tier, DetectionTier.airplane);
      expect(boxes.first.confidence, closeTo(0.7, 1e-9));
    });

    test("a model that calls it a bird removes the box", () {
      final _Scene scene = _Scene();
      scene.things.add(_Thing(400, 150, 4, 60, vx: 1.2));
      final FrameAnalyzer analyzer =
          FrameAnalyzer(confirmer: _FakeConfirmer(cocoBird, 0.8));
      final List<DetectionBox> boxes = _run(analyzer, scene, 40);
      expect(boxes, isEmpty);
    });

    test("a model that finds nothing keeps a small target yellow", () {
      final _Scene scene = _Scene();
      scene.things.add(_Thing(400, 150, 4, 60, vx: 1.2));
      final FrameAnalyzer analyzer =
          FrameAnalyzer(confirmer: _FakeConfirmer(0, 0.9));
      final List<DetectionBox> boxes = _run(analyzer, scene, 40);
      expect(boxes.length, 1);
      expect(boxes.first.tier, DetectionTier.possible);
    });

    test("an airplane call below the horizon needs a higher score", () {
      final _Scene scene = _Scene(horizonY: 0.5);
      scene.things.add(_Thing(400, 520, 6, 250, vx: 1.5));
      final FrameAnalyzer weak =
          FrameAnalyzer(confirmer: _FakeConfirmer(cocoAirplane, 0.35));
      expect(_run(weak, scene, 30), isEmpty);

      final _Scene again = _Scene(horizonY: 0.5);
      again.things.add(_Thing(400, 520, 6, 250, vx: 1.5));
      final FrameAnalyzer strong =
          FrameAnalyzer(confirmer: _FakeConfirmer(cocoAirplane, 0.8));
      final List<DetectionBox> boxes = _run(strong, again, 30);
      expect(boxes.length, 1);
      expect(boxes.first.tier, DetectionTier.airplane);
    });

    test("heavy clutter holds back yellow boxes", () {
      final _Scene scene = _Scene(horizonY: 0.95);
      for (int i = 0; i < 40; i++) {
        scene.things.add(_Thing(60 + (i % 10) * 120.0, 40 + (i ~/ 10) * 70.0,
            4, 60, vx: 1.0));
      }
      final FrameAnalyzer analyzer = FrameAnalyzer();
      final List<DetectionBox> boxes = _run(analyzer, scene, 30);
      expect(boxes, isEmpty);
    });

    test("reports the horizon and field of view", () {
      final _Scene scene = _Scene(horizonY: 0.6);
      final FrameAnalyzer analyzer = FrameAnalyzer();
      final AnalysisResult result = analyzer.process(
          LumaFrame.fromGray(scene.frame()),
          timestampMs: 1000);
      expect(result.horizon, isNotNull);
      expect(result.frame.horizonLeft, closeTo(0.6, 0.04));
      expect(result.frame.fovH, 65);
      expect(result.frame.fovV, closeTo(39.6, 0.5));
      expect(result.pictureWidth, 1280);
      expect(result.milliseconds, greaterThan(0));
    });

    test("falls back to the phone's tilt when the picture has no horizon", () {
      final Uint8List data = Uint8List(1280 * 720)..fillRange(0, 1280 * 720, 180);
      final FrameAnalyzer analyzer = FrameAnalyzer();
      final AnalysisResult result = analyzer.process(
        LumaFrame.fromGray(GrayImage(1280, 720, data)),
        timestampMs: 1000,
        gravity: const GravityHint(0, 1, 0),
      );
      expect(result.horizon, isNotNull);
      expect(result.horizon!.fromImage, isFalse);
      expect(result.horizon!.vLeft, closeTo(0.5, 1e-6));
    });

    test("turning the phone starts a fresh picture instead of mixing frames", () {
      final _Scene scene = _Scene();
      final FrameAnalyzer analyzer = FrameAnalyzer();
      analyzer.process(LumaFrame.fromGray(scene.frame()), timestampMs: 1000);
      final GrayImage g = scene.frame();
      final AnalysisResult turned = analyzer.process(
        LumaFrame(
          bytes: g.data,
          sourceWidth: g.width,
          sourceHeight: g.height,
          rowStride: g.width,
          quarterTurns: 1,
        ),
        timestampMs: 1100,
      );
      expect(turned.pictureWidth, 720);
      expect(turned.pictureHeight, 1280);
    });
  });

  group("PreviewEncoder", () {
    test("makes a small jpeg that fits in one datagram", () {
      final _Scene scene = _Scene();
      scene.things.add(_Thing(400, 150, 4, 60));
      final LumaFrame frame = LumaFrame.fromGray(scene.frame());
      final PreviewPicture? picture = PreviewEncoder.encode(frame);
      expect(picture, isNotNull);
      expect(picture!.width, 240);
      expect(picture.height, 135);
      expect(picture.jpeg.length, lessThanOrEqualTo(PreviewEncoder.maxBytes));
      // JPEG start of image marker.
      expect(picture.jpeg[0], 0xFF);
      expect(picture.jpeg[1], 0xD8);
    });

    test("a turned frame is encoded upright", () {
      final GrayImage g = _Scene().frame();
      final LumaFrame turned = LumaFrame(
        bytes: g.data,
        sourceWidth: g.width,
        sourceHeight: g.height,
        rowStride: g.width,
        quarterTurns: 1,
      );
      final PreviewPicture? picture = PreviewEncoder.encode(turned);
      expect(picture!.width, 240);
      expect(picture.height, 427);
    });
  });

  group("AnalyzerWorker", () {
    test("analyzes frames on another isolate and answers with boxes", () async {
      final AnalyzerWorker worker = await AnalyzerWorker.start(
        settings: const AnalyzerSettings(),
      );
      expect(worker.modelAvailable, isFalse);
      final _Scene scene = _Scene();
      scene.things.add(_Thing(400, 150, 4, 60, vx: 1.2));
      final List<WorkerOutput> outputs = [];
      final StreamSubscription<WorkerOutput> sub =
          worker.outputs.listen(outputs.add);
      for (int i = 0; i < 25; i++) {
        final GrayImage g = scene.frame();
        scene.step();
        final int before = outputs.length;
        expect(
          worker.submit(
            bytes: g.data,
            width: g.width,
            height: g.height,
            rowStride: g.width,
            quarterTurns: 0,
            timestampMs: 1000 + i * 100,
            wantPreview: i == 24,
          ),
          isTrue,
        );
        // A second frame is refused while the first is being analyzed.
        expect(
          worker.submit(
            bytes: g.data,
            width: g.width,
            height: g.height,
            rowStride: g.width,
            quarterTurns: 0,
            timestampMs: 0,
          ),
          isFalse,
        );
        while (outputs.length == before) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }
      expect(outputs.length, 25);
      expect(outputs.last.result.frame.seq, 24);
      expect(outputs.last.result.frame.boxes.length, 1);
      expect(outputs.last.preview, isNotNull);
      expect(outputs[0].preview, isNull);
      await sub.cancel();
      await worker.stop();
    });

    test("a model that cannot load leaves the worker running without one",
        () async {
      final AnalyzerWorker worker = await AnalyzerWorker.start(
        settings: const AnalyzerSettings(),
        modelBytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
      );
      expect(worker.modelAvailable, isFalse);
      await worker.stop();
    });
  });

  group("Bundled model", () {
    test("loads and does not see an airplane in a blank sky", () {
      final Uint8List bytes =
          File("assets/models/yolox_nano.tflite").readAsBytesSync();
      final TfliteAircraftConfirmer? confirmer =
          TfliteAircraftConfirmer.create(bytes);
      if (confirmer == null) {
        // The LiteRT runtime is not available on this test machine.
        markTestSkipped("LiteRT runtime not available on this machine");
        return;
      }
      final Uint8List sky = Uint8List(640 * 360)..fillRange(0, 640 * 360, 190);
      final LumaFrame frame = LumaFrame.fromGray(GrayImage(640, 360, sky));
      for (int i = 0; i < 2; i++) {
        final List<ObjectHit> hits = confirmer.detect(frame, 320, 180, 160);
        expect(hits.where((ObjectHit h) => h.classId == cocoAirplane && h.score > 0.3),
            isEmpty);
      }
      confirmer.close();
      // Closed is quiet, not a crash.
      expect(confirmer.detect(frame, 320, 180, 160), isEmpty);
    });
  });
}
