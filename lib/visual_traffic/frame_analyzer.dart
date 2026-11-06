import 'dart:math';

import 'package:avaremp/visual_traffic/aircraft_detector.dart';
import 'package:avaremp/visual_traffic/decisions.dart';
import 'package:avaremp/visual_traffic/detection_models.dart';
import 'package:avaremp/visual_traffic/dot_detector.dart';
import 'package:avaremp/visual_traffic/gyro_motion.dart';
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
    this.notes = const [],
    this.horizonReport = HorizonReport.unknown,
    this.gyroReport = GyroReport.none,
    this.cueResults = const [],
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

  /// What was decided about each target worth talking about, and why.
  final List<TargetNote> notes;

  /// Which horizon was used and how it compares with the phone's sensors.
  final HorizonReport horizonReport;

  /// How the gyroscope's turn compared with the picture's slide.
  final GyroReport gyroReport;

  /// What the model saw at each place ADS-B pointed it to.
  final List<CueResult> cueResults;
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
  final Map<String, _CueState> _cueStates = {};
  final Map<String, int> _cueIds = {};
  int _nextCueId = 0;
  List<Cue> _cues = const [];
  final GyroMotion _gyro = GyroMotion();
  GyroReport _gyroReport = GyroReport.none;
  double _slideX = 0;
  double _slideY = 0;
  HorizonLine? _horizon;
  HorizonLine? _sensorHorizon;
  bool _hadGravity = false;
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
  // A place ADS-B points to is looked at again after this long, and the
  // model's find is dropped after this many looks that miss it.
  static const int cueRecheckMs = 1500;
  static const int cueMissesToDrop = 3;

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
    _gyro.reset();
    _gyroReport = GyroReport.none;
    _cueStates.clear();
  }

  AnalysisResult process(
    LumaFrame frame, {
    required int timestampMs,
    GravityHint? gravity,
    MotionHint? motion,
    List<Cue> cues = const [],
  }) {
    final Stopwatch watch = Stopwatch()..start();
    _minSide = min(frame.width, frame.height).toDouble();
    if (frame.quarterTurns != _turns) {
      _turns = frame.quarterTurns;
      reset();
    }

    _syncCues(cues);
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
      final GyroPrediction? predicted = motion == null
          ? null
          : _gyro.predict(motion, _settings.fovH, small.width);
      final GyroPrediction? expected =
          predicted == null ? null : _gyro.expected(predicted);
      // Once the gyroscope has been seen to agree with the picture, it tells
      // the search where to look, so a fast turn is still measured.
      final GlobalMotion prior = expected == null
          ? _lastMeasured
          : GlobalMotion(expected.dx, expected.dy);
      final GlobalMotion slide = _motion.estimate(small, before, prior: prior);
      double dx = slide.dx;
      double dy = slide.dy;
      bool filledIn = false;
      if (slide.measured) {
        _lastMeasured = slide;
        if (predicted != null) {
          _gyro.learn(predicted, slide.dx, slide.dy);
        }
      } else if (expected != null) {
        // The picture has too little detail to measure. The gyroscope can
        // still say how far the scene slid.
        dx = expected.dx;
        dy = expected.dy;
        filledIn = dx != 0 || dy != 0;
      }
      _slideX += dx;
      _slideY += dy;
      _gyroReport = motion == null
          ? GyroReport.none
          : _gyro.report(predicted, filledIn: filledIn);
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

    final _Decisions decided = _decide(small, factor, dots.cluttered);
    final List<DetectionBox> boxes = decided.boxes;
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
      notes: decided.notes,
      horizonReport: _horizonReport(aspect),
      gyroReport: _gyroReport,
      cueResults: _cueResults(),
    );
  }

  HorizonReport _horizonReport(double aspect) {
    final HorizonLine? line = _horizon;
    if (line == null) {
      return HorizonReport(
        source: HorizonSource.none,
        sensorsAvailable: _hadGravity,
      );
    }
    final double tilt = line.tiltDegrees(aspect);
    final double? pitch = line.pitchDegrees(_settings.fovH, aspect);
    double? tiltDiff;
    double? pitchDiff;
    final HorizonLine? sensors = _sensorHorizon;
    if (line.fromImage && sensors != null) {
      tiltDiff = (tilt - sensors.tiltDegrees(aspect)).abs();
      final double? sensorPitch = sensors.pitchDegrees(_settings.fovH, aspect);
      if (pitch != null && sensorPitch != null) {
        pitchDiff = (pitch - sensorPitch).abs();
      }
    }
    return HorizonReport(
      source: line.fromImage ? HorizonSource.picture : HorizonSource.sensors,
      tiltDegrees: tilt,
      pitchDegrees: pitch,
      sensorsAvailable: _hadGravity,
      sensorTiltDiff: tiltDiff,
      sensorPitchDiff: pitchDiff,
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
    _hadGravity = gravity != null;
    _sensorHorizon = gravity == null
        ? null
        : HorizonLine.fromGravity(
            gx: gravity.x,
            gy: gravity.y,
            gz: gravity.z,
            fovH: _settings.fovH,
            aspect: small.width / small.height,
          );
    found ??= _sensorHorizon;
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
    if (_confirmCue(frame, timestampMs, factor)) {
      return 1;
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
      if (hit.classId == cocoAirplane && hit.score > pick.bestAirplaneScore) {
        pick.bestAirplaneScore = hit.score;
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
      pick.birdScoreSeen = bird.score;
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

  void _syncCues(List<Cue> cues) {
    _cues = cues;
    final Set<String> keys = cues.map((Cue c) => c.key).toSet();
    _cueStates.removeWhere((String key, _CueState _) => !keys.contains(key));
    for (final Cue cue in cues) {
      _cueStates.putIfAbsent(cue.key, () => _CueState());
    }
  }

  int _cueId(String key) => _cueIds.putIfAbsent(key, () => ++_nextCueId);

  List<CueResult> _cueResults() {
    final List<CueResult> out = [];
    for (final Cue cue in _cues) {
      final _CueState? state = _cueStates[cue.key];
      if (state == null) {
        continue;
      }
      out.add(CueResult(
        key: cue.key,
        checks: state.checks,
        bestScore: state.best,
        airplane: state.airplane,
        boxId: state.airplane ? -_cueId(cue.key) : null,
      ));
    }
    return out;
  }

  /// Asks the model to look where ADS-B says an aircraft should be. Returns
  /// true when it did.
  bool _confirmCue(LumaFrame frame, int timestampMs, int factor) {
    final AircraftConfirmer? confirmer = _confirmer;
    if (confirmer == null) {
      return false;
    }
    Cue? pick;
    _CueState? pickState;
    for (final Cue cue in _cues) {
      final _CueState? state = _cueStates[cue.key];
      if (state == null || timestampMs - state.lastCheckMs < cueRecheckMs) {
        continue;
      }
      if (pickState == null || state.checks < pickState.checks) {
        pick = cue;
        pickState = state;
      }
    }
    if (pick == null || pickState == null) {
      return false;
    }
    _lastModelMs = timestampMs;
    pickState.lastCheckMs = timestampMs;
    pickState.checks++;
    final double cx = pick.u * frame.width;
    final double cy = pick.v * frame.height;
    // The spot is only roughly known, so the patch is wider than for a
    // tracked target.
    final double side =
        (pick.expectedPixels * 8).clamp(160.0, max(160.0, _minSide));
    final List<ObjectHit> hits = confirmer.detect(frame, cx, cy, side);
    final HorizonLine? horizon = _horizon;
    final bool sky = horizon == null || horizon.isSky(pick.u, pick.v);
    final double needed = sky ? skyAirplaneScore : belowAirplaneScore;
    ObjectHit? best;
    for (final ObjectHit hit in hits) {
      if (hit.classId != cocoAirplane) {
        continue;
      }
      if (hit.score > pickState.best) {
        pickState.best = hit.score;
      }
      if (hit.score >= needed && (best == null || hit.score > best.score)) {
        best = hit;
      }
    }
    if (best != null) {
      pickState.airplane = true;
      pickState.misses = 0;
      pickState.score = best.score;
      pickState.du = (best.x1 + best.x2) / 2 / frame.width - pick.u;
      pickState.dv = (best.y1 + best.y2) / 2 / frame.height - pick.v;
      pickState.w = max((best.x2 - best.x1) / frame.width, 0.012);
      pickState.h = max((best.y2 - best.y1) / frame.height, 0.012);
      // A tracked spot inside the airplane the model found is that airplane,
      // so it is confirmed like any other target the model checked.
      final double pad = max(8.0, side * 0.05);
      for (final Track track in _tracker.tracks) {
        if (track.glass || track.bird) {
          continue;
        }
        if (best.contains(track.imageX * factor, track.imageY * factor, pad: pad)) {
          track.airplane = true;
          track.airplaneScore = best.score;
          track.airplaneMisses = 0;
          track.birdChecks = 0;
        }
      }
    } else if (++pickState.misses >= cueMissesToDrop) {
      pickState.airplane = false;
    }
    return true;
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

  /// Judges every target worth talking about. Targets that pass become
  /// boxes. All of them become notes, so the Why window can say why a target
  /// was boxed or thrown out.
  _Decisions _decide(GrayImage small, int factor, bool cluttered) {
    final List<DetectionBox> boxes = [];
    final List<TargetNote> notes = [];
    final double aw = small.width.toDouble();
    final double ah = small.height.toDouble();
    for (final Track track in _tracker.tracks) {
      final double cx = (track.imageX / aw).clamp(0.0, 1.0);
      final double cy = (track.imageY / ah).clamp(0.0, 1.0);
      final _Judgement? judgement = _judge(track, factor, cluttered);
      if (judgement == null) {
        continue;
      }
      notes.add(TargetNote(
        id: track.id,
        x: cx,
        y: cy,
        verdict: judgement.verdict,
        code: judgement.code,
        reason: judgement.reason,
      ));
      if (judgement.verdict != Verdict.red &&
          judgement.verdict != Verdict.yellow) {
        continue;
      }
      final bool airplane = judgement.verdict == Verdict.red;
      // A little room around the spot so the box does not sit on it.
      final double bw = max((track.width + 6) / aw, 0.012);
      final double bh = max((track.height + 6) / ah, 0.012);
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
    _addCueBoxes(boxes, notes);
    // Most interesting first, and not so many that the window is a wall of
    // text.
    notes.sort((TargetNote a, TargetNote b) {
      final int byVerdict = a.verdict.index.compareTo(b.verdict.index);
      return byVerdict != 0 ? byVerdict : a.id.compareTo(b.id);
    });
    if (notes.length > maxNotes) {
      notes.removeRange(maxNotes, notes.length);
    }
    return _Decisions(boxes, notes);
  }

  /// Boxes for airplanes the model found where ADS-B pointed it. When a
  /// tracked target is already there, that target is the one made red.
  void _addCueBoxes(List<DetectionBox> boxes, List<TargetNote> notes) {
    for (final Cue cue in _cues) {
      final _CueState? state = _cueStates[cue.key];
      if (state == null || !state.airplane) {
        continue;
      }
      final double cx = (cue.u + state.du).clamp(0.0, 1.0);
      final double cy = (cue.v + state.dv).clamp(0.0, 1.0);
      final String why = 'ADS-B says ${cue.key} is about here '
          '(${cue.distanceNm.toStringAsFixed(1)} nm), and the model sees an '
          'airplane there (${state.score.toStringAsFixed(2)}).';
      int covering = -1;
      for (int i = 0; i < boxes.length; i++) {
        final DetectionBox b = boxes[i];
        if ((cx - b.centerX).abs() <= max(b.w, state.w) &&
            (cy - b.centerY).abs() <= max(b.h, state.h)) {
          covering = i;
          break;
        }
      }
      if (covering >= 0) {
        // A tracked target is already boxed there.
        continue;
      }
      final int id = -_cueId(cue.key);
      boxes.add(DetectionBox(
        id: id,
        x: (cx - state.w / 2).clamp(0.0, 1.0),
        y: (cy - state.h / 2).clamp(0.0, 1.0),
        w: state.w,
        h: state.h,
        confidence: state.score,
        tier: DetectionTier.airplane,
      ));
      notes.add(TargetNote(
        id: id,
        x: cx,
        y: cy,
        verdict: Verdict.red,
        code: 'adsb-cue',
        reason: '$why Nothing was seen moving there.',
      ));
    }
  }

  static const int maxNotes = 14;

  /// The verdict for one target, or null when it is just noise that is not
  /// worth a line.
  _Judgement? _judge(Track track, int factor, bool cluttered) {
    if (track.glass) {
      return const _Judgement(
        Verdict.rejected,
        'glass',
        'Windshield speck: it stayed put in the picture while the scene moved.',
      );
    }
    if (track.bird) {
      return _Judgement(
        Verdict.rejected,
        'bird',
        'Model says bird (${track.birdScoreSeen.toStringAsFixed(2)}), not an airplane.',
      );
    }
    if (track.airplane) {
      return _Judgement(
        Verdict.red,
        'airplane',
        'Model says airplane (${track.airplaneScore.toStringAsFixed(2)}, '
            '${track.below ? belowAirplaneScore : skyAirplaneScore} needed). '
            '${track.moving ? "Moving against the scene." : "Steady in the scene."}',
      );
    }
    final int seen = track.windowHits;
    if (!track.persistent) {
      if (seen < 4) {
        return null;
      }
      return _Judgement(
        Verdict.watching,
        'steady',
        'Not steady enough yet: seen in $seen of the last 12 frames. '
            'Needs ${track.moving ? 5 : 9}.',
      );
    }
    if (track.below) {
      if (!track.moving) {
        return null;
      }
      return const _Judgement(
        Verdict.rejected,
        'below',
        'Below the horizon: ground and cars look the same, so it is shown '
            'only if the model confirms an airplane.',
      );
    }
    if (cluttered) {
      return const _Judgement(
        Verdict.rejected,
        'busy',
        'Too many spots in the sky (clouds or haze): unconfirmed spots are held back.',
      );
    }
    if (_modelRulesOut(track, factor)) {
      return _Judgement(
        Verdict.rejected,
        'model-no',
        'Model looked ${track.checks} times and never saw an airplane '
            '(best ${track.bestAirplaneScore.toStringAsFixed(2)}, '
            '$skyAirplaneScore needed).',
      );
    }
    final String moves = track.moving ? 'Moves steadily.' : 'Holds steady.';
    if (_confirmer == null) {
      return _Judgement(
        Verdict.yellow,
        'no-model',
        '$moves No model on this phone, so it cannot be confirmed.',
      );
    }
    if (track.checks == 0) {
      return _Judgement(Verdict.yellow, 'unchecked', '$moves Waiting for the model to look.');
    }
    return _Judgement(
      Verdict.yellow,
      'unconfirmed',
      '$moves Model looked ${track.checks} times: best airplane score '
          '${track.bestAirplaneScore.toStringAsFixed(2)}, $skyAirplaneScore needed.',
    );
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

class _Judgement {
  const _Judgement(this.verdict, this.code, this.reason);
  final Verdict verdict;
  final String code;
  final String reason;
}

class _Decisions {
  const _Decisions(this.boxes, this.notes);
  final List<DetectionBox> boxes;
  final List<TargetNote> notes;
}

class _CueState {
  int checks = 0;
  double best = 0;
  bool airplane = false;
  double score = 0;
  int misses = 0;
  int lastCheckMs = -100000;

  // Where the model found the airplane, relative to where ADS-B said, so the
  // box follows the cue as the camera moves.
  double du = 0;
  double dv = 0;
  double w = 0.02;
  double h = 0.02;
}
