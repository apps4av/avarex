import 'dart:math';

import 'package:avaremp/visual_traffic/aircraft_detector.dart';
import 'package:avaremp/visual_traffic/detection_models.dart';
import 'package:avaremp/visual_traffic/dot_detector.dart';
import 'package:avaremp/visual_traffic/horizon.dart';
import 'package:avaremp/visual_traffic/luma_frame.dart';
import 'package:avaremp/visual_traffic/motion.dart';
import 'package:avaremp/visual_traffic/tracker.dart';

/// Tuning that the pilot can change.
class AnalyzerSettings {
  const AnalyzerSettings({
    this.fovH = 65,
    this.sensitivity = 1,
    this.analysisWidth = 640,
  });

  /// Horizontal field of view of the camera, in degrees.
  final double fovH;

  /// 0.5 finds only clear targets. 1.5 also finds faint ones and more false
  /// ones.
  final double sensitivity;

  /// Width, in pixels, of the picture the motion and spot search works on.
  final int analysisWidth;

  AnalyzerSettings copyWith({double? fovH, double? sensitivity}) {
    return AnalyzerSettings(
      fovH: fovH ?? this.fovH,
      sensitivity: sensitivity ?? this.sensitivity,
      analysisWidth: analysisWidth,
    );
  }
}

/// Which way is down, in the camera's own axes: x to the right of the
/// upright picture, y toward its bottom, z out through the lens.
class GravityHint {
  const GravityHint(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
}

/// What was found in one frame, and how.
class AnalysisResult {
  const AnalysisResult({
    required this.frame,
    required this.pictureWidth,
    required this.pictureHeight,
    required this.horizon,
    required this.cluttered,
    required this.spots,
    required this.tracks,
    required this.modelRuns,
    required this.modelAvailable,
    required this.milliseconds,
  });

  final DetectionFrame frame;

  /// Size of the upright camera frame this came from, in pixels.
  final int pictureWidth;
  final int pictureHeight;

  final HorizonLine? horizon;

  /// Too many spots in the sky to trust the unconfirmed ones, so yellow boxes
  /// were held back.
  final bool cluttered;

  /// Spots seen this frame and tracks being followed.
  final int spots;
  final int tracks;

  /// Model looks done this frame (0 or 1).
  final int modelRuns;
  final bool modelAvailable;

  final double milliseconds;
}

/// The whole detection pipeline for a stream of camera frames.
///
/// Each frame: shrink it, find the horizon, measure how the scene slid since
/// the last frame, find small spots in the sky, follow them from frame to
/// frame, ask the model about the ones that keep showing up, and turn the
/// survivors into boxes.
///
/// Pure Dart with no plugins, so it runs in a background isolate, in a unit
/// test, or on recorded video.
class FrameAnalyzer {
  FrameAnalyzer({
    AircraftConfirmer? confirmer,
    AnalyzerSettings settings = const AnalyzerSettings(),
  })  : _confirmer = confirmer,
        _settings = settings;

  AircraftConfirmer? _confirmer;
  AnalyzerSettings _settings;

  final HorizonEstimator _horizonEstimator = HorizonEstimator();
  final MotionEstimator _motion = MotionEstimator();
  final DotDetector _dots = DotDetector();
  Tracker _tracker = Tracker();

  GrayImage? _previous;
  GlobalMotion _lastMeasured = GlobalMotion.none;
  double _slideX = 0;
  double _slideY = 0;
  HorizonLine? _horizon;
  int _horizonLost = 0;
  int _seq = 0;
  int _lastModelMs = -100000;
  int _turns = -1;
  double _minSide = 480;

  // Model confidence needed to call something an airplane. Below the horizon
  // is harder because terrain and vehicles look like small objects.
  static const double skyAirplaneScore = 0.30;
  static const double belowAirplaneScore = 0.45;
  static const double birdScore = 0.35;
  // At least this long between model looks, so a phone does not overheat.
  static const int minModelGapMs = 150;
  // Frames to wait before asking the model about the same target again.
  static const int recheckFrames = 8;
  static const int confirmedRecheckFrames = 30;
  static const int maxChecksBeforeGivingUp = 12;

  bool get modelAvailable => _confirmer != null;

  void updateSettings(AnalyzerSettings settings) {
    _settings = settings;
  }

  /// Replaces or removes the model.
  void setConfirmer(AircraftConfirmer? confirmer) {
    _confirmer?.close();
    _confirmer = confirmer;
  }

  void dispose() {
    _confirmer?.close();
    _confirmer = null;
  }

  /// Forgets everything followed so far. Used when the picture changes shape.
  void reset() {
    _tracker = Tracker();
    _previous = null;
    _lastMeasured = GlobalMotion.none;
    _slideX = 0;
    _slideY = 0;
    _horizon = null;
    _horizonLost = 0;
  }

  AnalysisResult process(
    LumaFrame frame, {
    required int timestampMs,
    GravityHint? gravity,
  }) {
    final Stopwatch watch = Stopwatch()..start();
    _minSide = min(frame.width, frame.height).toDouble();
    if (frame.quarterTurns != _turns) {
      _turns = frame.quarterTurns;
      reset();
    }

    final int factor = max(1, (frame.width / _settings.analysisWidth).round());
    final GrayImage small = frame.downscale(factor);
    final GrayImage? previous = _previous;
    if (previous != null &&
        (previous.width != small.width || previous.height != small.height)) {
      reset();
    }

    _updateHorizon(small, gravity);
    final HorizonLine? horizon = _horizon;

    // How far the scene slid since the last frame.
    final GrayImage? before = _previous;
    if (before != null) {
      final GlobalMotion motion =
          _motion.estimate(small, before, prior: _lastMeasured);
      if (motion.measured) {
        _lastMeasured = motion;
      }
      _slideX += motion.dx;
      _slideY += motion.dy;
    }
    _previous = small;

    final DotResult dots = _dots.detect(
      small,
      sensitivity: _settings.sensitivity,
      isSky: horizon == null
          ? null
          : (double u, double v) => horizon.isSky(u, v),
    );
    _tracker.update(dots.candidates, _slideX, _slideY);

    final int modelRuns = _confirm(frame, small, factor, timestampMs);

    final List<DetectionBox> boxes = _boxes(small, factor, dots.cluttered);
    final double aspect = frame.width / frame.height;
    final double fovV = _verticalFov(_settings.fovH, aspect);
    watch.stop();
    return AnalysisResult(
      frame: DetectionFrame(
        seq: _seq++,
        timestampMs: timestampMs,
        fovH: _settings.fovH,
        fovV: fovV,
        boxes: boxes,
        horizonLeft: horizon?.vLeft,
        horizonRight: horizon?.vRight,
      ),
      pictureWidth: frame.width,
      pictureHeight: frame.height,
      horizon: horizon,
      cluttered: dots.cluttered,
      spots: dots.candidates.length,
      tracks: _tracker.tracks.length,
      modelRuns: modelRuns,
      modelAvailable: _confirmer != null,
      milliseconds: watch.elapsedMicroseconds / 1000,
    );
  }

  static double _verticalFov(double fovH, double aspect) {
    final double half = tan(fovH * pi / 360);
    return 2 * atan(half / aspect) * 180 / pi;
  }

  void _updateHorizon(GrayImage small, GravityHint? gravity) {
    // The picture is searched at about 128 pixels wide. That is plenty to
    // find a long straight edge, and cheap.
    final int shrink = max(1, small.width ~/ 128);
    final GrayImage tiny = small.shrink(shrink);
    HorizonLine? found = _horizonEstimator.estimate(tiny);
    if (found == null && gravity != null) {
      found = HorizonLine.fromGravity(
        gx: gravity.x,
        gy: gravity.y,
        gz: gravity.z,
        fovH: _settings.fovH,
        aspect: small.width / small.height,
      );
    }
    if (found != null) {
      final HorizonLine? current = _horizon;
      if (current != null &&
          current.fromImage == found.fromImage &&
          current.distanceTo(found) < 0.15) {
        _horizon = current.blend(found, 0.35);
      } else {
        _horizon = found;
      }
      _horizonLost = 0;
    } else if (++_horizonLost > 15) {
      _horizon = null;
    }
  }

  /// Side, in picture pixels, of the patch shown to the model for a target.
  double _cropSide(Track track, int factor) {
    final double target = max(track.width, track.height) * factor;
    return (target * 8).clamp(96.0, max(96.0, _minSide));
  }

  /// Asks the model about at most one target. Returns 1 when it did.
  int _confirm(LumaFrame frame, GrayImage small, int factor, int timestampMs) {
    final AircraftConfirmer? confirmer = _confirmer;
    if (confirmer == null || timestampMs - _lastModelMs < minModelGapMs) {
      return 0;
    }
    final int now = _tracker.frame;
    Track? pick;
    for (final Track track in _tracker.tracks) {
      if (track.glass || track.bird) {
        continue;
      }
      // Terrain slides with the scene and never moves on its own, so a
      // below-horizon spot is only worth the model's time when it moves.
      final bool worthChecking = track.below
          ? track.windowHits >= 8 && track.moving
          : track.persistent;
      if (!worthChecking) {
        continue;
      }
      final int wait = track.airplane ? confirmedRecheckFrames : recheckFrames;
      if (now - track.lastCheckFrame < wait) {
        continue;
      }
      if (!track.airplane && track.checks >= maxChecksBeforeGivingUp) {
        continue;
      }
      if (pick == null || _priority(track) > _priority(pick)) {
        pick = track;
      }
    }
    if (pick == null) {
      return 0;
    }
    _lastModelMs = timestampMs;
    final double cx = pick.imageX * factor;
    final double cy = pick.imageY * factor;
    final double side = _cropSide(pick, factor);
    final List<ObjectHit> hits = confirmer.detect(frame, cx, cy, side);
    pick.checks++;
    pick.lastCheckFrame = now;

    final double pad = max(8.0, side * 0.1);
    final double needed = pick.below ? belowAirplaneScore : skyAirplaneScore;
    ObjectHit? airplane;
    ObjectHit? bird;
    for (final ObjectHit hit in hits) {
      if (!hit.contains(cx, cy, pad: pad)) {
        continue;
      }
      if (hit.classId == cocoAirplane &&
          hit.score >= needed &&
          (airplane == null || hit.score > airplane.score)) {
        airplane = hit;
      } else if (hit.classId == cocoBird &&
          hit.score >= birdScore &&
          (bird == null || hit.score > bird.score)) {
        bird = hit;
      }
    }

    if (airplane != null && (bird == null || airplane.score >= bird.score)) {
      pick.airplane = true;
      pick.airplaneScore = airplane.score;
      pick.airplaneMisses = 0;
      pick.birdChecks = 0;
    } else if (bird != null) {
      pick.birdChecks++;
      if (pick.birdChecks >= 2) {
        pick.bird = true;
        pick.airplane = false;
      }
    } else {
      pick.birdChecks = 0;
      if (pick.airplane) {
        pick.airplaneMisses++;
        if (pick.airplaneMisses >= 4) {
          pick.airplane = false;
        }
      }
    }
    return 1;
  }

  double _priority(Track track) {
    double p = track.contrast.abs();
    if (track.checks == 0) {
      p += 1000;
    }
    if (!track.below) {
      p += 100;
    }
    return p;
  }

  List<DetectionBox> _boxes(GrayImage small, int factor, bool cluttered) {
    final List<DetectionBox> boxes = [];
    final double aw = small.width.toDouble();
    final double ah = small.height.toDouble();
    for (final Track track in _tracker.tracks) {
      if (track.glass || track.bird) {
        continue;
      }
      final bool airplane = track.airplane;
      if (!airplane) {
        if (!track.persistent || track.below || cluttered) {
          continue;
        }
        if (_modelRulesOut(track, factor)) {
          continue;
        }
      }
      // A little room around the spot so the box does not sit on it.
      final double bw = max((track.width + 6) / aw, 0.012);
      final double bh = max((track.height + 6) / ah, 0.012);
      final double cx = (track.imageX / aw).clamp(0.0, 1.0);
      final double cy = (track.imageY / ah).clamp(0.0, 1.0);
      boxes.add(DetectionBox(
        id: track.id,
        x: (cx - bw / 2).clamp(0.0, 1.0),
        y: (cy - bh / 2).clamp(0.0, 1.0),
        w: bw,
        h: bh,
        confidence: airplane ? track.airplaneScore : track.consistency * 0.9,
        tier: airplane ? DetectionTier.airplane : DetectionTier.possible,
      ));
    }
    return boxes;
  }

  /// A target large enough for the model to see, looked at several times,
  /// that the model never called an airplane, is probably not one.
  bool _modelRulesOut(Track track, int factor) {
    if (_confirmer == null || track.checks < 3) {
      return false;
    }
    final double target = max(track.width, track.height) * factor;
    final double side = _cropSide(track, factor);
    final double inModelPixels = target * YoloxDecoder.inputSize / side;
    return inModelPixels >= 30;
  }
}
