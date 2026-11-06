import 'dart:math';
import 'dart:typed_data';

import 'package:avaremp/utils/app_log.dart';
import 'package:avaremp/visual_traffic/luma_frame.dart';
import 'package:flutter_litert/flutter_litert.dart';

/// COCO class numbers the model reports.
const int cocoAirplane = 4;
const int cocoBird = 14;

/// One object the model found, in pixels of the upright camera frame.
class ObjectHit {
  const ObjectHit({
    required this.classId,
    required this.score,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  final int classId;
  final double score;
  final double x1;
  final double y1;
  final double x2;
  final double y2;

  bool contains(double x, double y, {double pad = 0}) {
    return x >= x1 - pad && x <= x2 + pad && y >= y1 - pad && y <= y2 + pad;
  }
}

/// Looks at a square patch of a camera frame and says which objects are in it.
///
/// This is the swappable part of the pipeline: any implementation that reports
/// COCO class numbers can stand in for the bundled YOLOX-Nano model.
abstract class AircraftConfirmer {
  /// Looks at the square of [side] pixels centered at ([cx], [cy]) in the
  /// upright [frame]. The square is moved to stay inside the frame.
  List<ObjectHit> detect(LumaFrame frame, double cx, double cy, double side);

  void close();
}

/// A box in the model's own 416-pixel input space.
class RawDetection {
  const RawDetection(this.classId, this.score, this.x1, this.y1, this.x2, this.y2);

  final int classId;
  final double score;
  final double x1;
  final double y1;
  final double x2;
  final double y2;
}

/// Turns YOLOX's raw output into boxes.
///
/// The bundled model returns `[3549, 85]` numbers: for each grid cell of three
/// scales (strides 8, 16, 32), four box numbers, one objectness and 80 class
/// scores. Objectness and class scores are already between 0 and 1. Boxes are
/// not decoded: centers are offsets in grid cells and sizes are logs.
class YoloxDecoder {
  static const int inputSize = 416;
  static const int classCount = 80;
  static const int valuesPerAnchor = 5 + classCount;
  static const List<int> strides = [8, 16, 32];

  static int get anchorCount {
    int total = 0;
    for (final int stride in strides) {
      final int n = inputSize ~/ stride;
      total += n * n;
    }
    return total;
  }

  /// [raw] holds [anchorCount] by [valuesPerAnchor] numbers. Only classes in
  /// [classes] are kept when it is given. Overlapping boxes of one class are
  /// merged, keeping the best.
  static List<RawDetection> decode(
    Float32List raw, {
    double scoreThreshold = 0.2,
    double nmsIou = 0.45,
    Set<int>? classes,
  }) {
    if (raw.length < anchorCount * valuesPerAnchor) {
      return const [];
    }
    final List<RawDetection> found = [];
    int anchor = 0;
    for (final int stride in strides) {
      final int n = inputSize ~/ stride;
      for (int gy = 0; gy < n; gy++) {
        for (int gx = 0; gx < n; gx++) {
          final int base = anchor * valuesPerAnchor;
          anchor++;
          final double objectness = raw[base + 4];
          if (objectness < scoreThreshold) {
            continue;
          }
          int bestClass = -1;
          double bestScore = 0;
          for (int c = 0; c < classCount; c++) {
            if (classes != null && !classes.contains(c)) {
              continue;
            }
            final double s = raw[base + 5 + c];
            if (s > bestScore) {
              bestScore = s;
              bestClass = c;
            }
          }
          if (bestClass < 0) {
            continue;
          }
          final double score = objectness * bestScore;
          if (score < scoreThreshold) {
            continue;
          }
          final double cx = (raw[base] + gx) * stride;
          final double cy = (raw[base + 1] + gy) * stride;
          final double w = exp(raw[base + 2].clamp(-10.0, 10.0)) * stride;
          final double h = exp(raw[base + 3].clamp(-10.0, 10.0)) * stride;
          found.add(RawDetection(
              bestClass, score, cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2));
        }
      }
    }
    return _nms(found, nmsIou);
  }

  static List<RawDetection> _nms(List<RawDetection> boxes, double iou) {
    boxes.sort((RawDetection a, RawDetection b) => b.score.compareTo(a.score));
    final List<RawDetection> kept = [];
    for (final RawDetection box in boxes) {
      bool suppressed = false;
      for (final RawDetection other in kept) {
        if (other.classId == box.classId && _iou(box, other) > iou) {
          suppressed = true;
          break;
        }
      }
      if (!suppressed) {
        kept.add(box);
      }
    }
    return kept;
  }

  static double _iou(RawDetection a, RawDetection b) {
    final double ix = max(0.0, min(a.x2, b.x2) - max(a.x1, b.x1));
    final double iy = max(0.0, min(a.y2, b.y2) - max(a.y1, b.y1));
    final double inter = ix * iy;
    final double union =
        (a.x2 - a.x1) * (a.y2 - a.y1) + (b.x2 - b.x1) * (b.y2 - b.y1) - inter;
    return union <= 0 ? 0 : inter / union;
  }
}

/// Runs the bundled YOLOX-Nano model with LiteRT.
///
/// The model wants a 416 by 416 BGR picture, values 0 to 255, no
/// normalization. The camera gives brightness only, so the same value fills
/// all three channels.
class TfliteAircraftConfirmer implements AircraftConfirmer {
  TfliteAircraftConfirmer._(this._interpreter);

  final Interpreter _interpreter;
  final Float32List _input =
      Float32List(YoloxDecoder.inputSize * YoloxDecoder.inputSize * 3);
  final Float32List _output =
      Float32List(YoloxDecoder.anchorCount * YoloxDecoder.valuesPerAnchor);
  bool _closed = false;

  /// Only these are worth decoding. Everything else is ignored.
  static const Set<int> _classes = {cocoAirplane, cocoBird};

  /// Loads the model from [modelBytes]. Returns null when it cannot be loaded
  /// or does not have the shape this class expects, so the app can carry on
  /// with motion-only detection.
  static TfliteAircraftConfirmer? create(Uint8List modelBytes) {
    Interpreter? interpreter;
    try {
      final InterpreterOptions options = InterpreterOptions()..threads = 2;
      interpreter = Interpreter.fromBuffer(modelBytes, options: options);
      final List<int> inShape = interpreter.getInputTensor(0).shape;
      final List<int> outShape = interpreter.getOutputTensor(0).shape;
      final bool inputOk = inShape.length == 4 &&
          inShape[1] == YoloxDecoder.inputSize &&
          inShape[2] == YoloxDecoder.inputSize &&
          inShape[3] == 3;
      final bool outputOk = outShape.length == 3 &&
          outShape[1] == YoloxDecoder.anchorCount &&
          outShape[2] == YoloxDecoder.valuesPerAnchor;
      if (!inputOk || !outputOk) {
        AppLog.logMessage(
            "Visual Traffic model has unexpected shape in=$inShape out=$outShape");
        interpreter.close();
        return null;
      }
      return TfliteAircraftConfirmer._(interpreter);
    } catch (e) {
      AppLog.logMessage("Visual Traffic model failed to load: $e");
      interpreter?.close();
      return null;
    }
  }

  @override
  List<ObjectHit> detect(LumaFrame frame, double cx, double cy, double side) {
    if (_closed) {
      return const [];
    }
    final double size = min(side, min(frame.width, frame.height).toDouble());
    final double x0 = (cx - size / 2).clamp(0.0, frame.width - size);
    final double y0 = (cy - size / 2).clamp(0.0, frame.height - size);
    final double scale = size / YoloxDecoder.inputSize;
    int index = 0;
    for (int oy = 0; oy < YoloxDecoder.inputSize; oy++) {
      final double sy = y0 + (oy + 0.5) * scale - 0.5;
      for (int ox = 0; ox < YoloxDecoder.inputSize; ox++) {
        final double v = frame.sample(x0 + (ox + 0.5) * scale - 0.5, sy);
        _input[index++] = v;
        _input[index++] = v;
        _input[index++] = v;
      }
    }
    try {
      _interpreter.run(_input.buffer.asUint8List(), _output);
    } catch (e) {
      AppLog.logMessage("Visual Traffic model run failed: $e");
      return const [];
    }
    final List<RawDetection> raw =
        YoloxDecoder.decode(_output, scoreThreshold: 0.12, classes: _classes);
    return raw
        .map((RawDetection d) => ObjectHit(
              classId: d.classId,
              score: d.score,
              x1: x0 + d.x1 * scale,
              y1: y0 + d.y1 * scale,
              x2: x0 + d.x2 * scale,
              y2: y0 + d.y2 * scale,
            ))
        .toList();
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _interpreter.close();
  }
}
