/// Shared types for Visual Traffic. Pure Dart, so the same code runs on the
/// UI thread, in the analyzer isolate, in unit tests, and over Link.
///
/// All coordinates are normalized to the upright picture: x and y run from 0
/// (left, top) to 1 (right, bottom), after the camera frame has been rotated
/// the way the pilot sees it. Normalized coordinates mean the viewer does not
/// need to know the sender's camera resolution.
library;

/// How sure we are that a box is an aircraft.
enum DetectionTier {
  /// A small sky mover that kept showing up but is too small to classify.
  /// Drawn as a thin yellow box.
  possible,

  /// The on-device model recognized an airplane. Drawn as a red box.
  airplane;

  static DetectionTier fromWire(Object? raw) {
    return raw == "airplane" ? DetectionTier.airplane : DetectionTier.possible;
  }
}

/// One tracked target in one frame.
class DetectionBox {
  const DetectionBox({
    required this.id,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.confidence,
    required this.tier,
  });

  /// Stable while the same target is followed, so a viewer can tell a new
  /// target from the same one moving.
  final int id;

  /// Left, top, width and height, each 0..1 of the upright picture.
  final double x;
  final double y;
  final double w;
  final double h;

  /// 0..1. For [DetectionTier.airplane] this is the model score. For
  /// [DetectionTier.possible] it is how consistently the target was seen.
  final double confidence;
  final DetectionTier tier;

  double get centerX => x + w / 2;
  double get centerY => y + h / 2;

  Map<String, Object?> toJson() {
    return {
      "id": id,
      // Four decimals is far finer than a pixel and keeps datagrams small.
      "x": _round(x),
      "y": _round(y),
      "w": _round(w),
      "h": _round(h),
      "c": _round(confidence),
      "t": tier.name,
    };
  }

  /// Returns null when [raw] is not a usable box.
  static DetectionBox? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final Object? id = raw["id"];
    final Object? x = raw["x"];
    final Object? y = raw["y"];
    final Object? w = raw["w"];
    final Object? h = raw["h"];
    if (id is! num || x is! num || y is! num || w is! num || h is! num) {
      return null;
    }
    final Object? c = raw["c"];
    return DetectionBox(
      id: id.toInt(),
      x: x.toDouble().clamp(0.0, 1.0),
      y: y.toDouble().clamp(0.0, 1.0),
      w: w.toDouble().clamp(0.0, 1.0),
      h: h.toDouble().clamp(0.0, 1.0),
      confidence: c is num ? c.toDouble().clamp(0.0, 1.0) : 0.0,
      tier: DetectionTier.fromWire(raw["t"]),
    );
  }

  static double _round(double value) {
    return (value * 10000).roundToDouble() / 10000;
  }
}

/// Everything found in one analyzed camera frame.
class DetectionFrame {
  const DetectionFrame({
    required this.seq,
    required this.timestampMs,
    required this.fovH,
    required this.fovV,
    required this.boxes,
    this.horizonLeft,
    this.horizonRight,
  });

  /// Increases by one for each analyzed frame. A viewer drops older frames.
  final int seq;

  /// Sender's clock, milliseconds since the epoch.
  final int timestampMs;

  /// Horizontal and vertical field of view of the picture, in degrees.
  /// Lets a viewer turn a box position into degrees off the camera axis.
  final double fovH;
  final double fovV;

  final List<DetectionBox> boxes;

  /// Where the estimated horizon crosses the left and right edges, as a
  /// fraction of the picture height. Null when no horizon is known.
  final double? horizonLeft;
  final double? horizonRight;

  int get airplaneCount =>
      boxes.where((DetectionBox b) => b.tier == DetectionTier.airplane).length;

  Map<String, Object?> toJson() {
    final Map<String, Object?> map = {
      "seq": seq,
      "ts": timestampMs,
      "fovH": fovH,
      "fovV": fovV,
      "boxes": boxes.map((DetectionBox b) => b.toJson()).toList(),
    };
    if (horizonLeft != null && horizonRight != null) {
      map["hl"] = DetectionBox._round(horizonLeft!);
      map["hr"] = DetectionBox._round(horizonRight!);
    }
    return map;
  }

  /// Returns null when [raw] is not a usable frame.
  static DetectionFrame? fromJson(Map<dynamic, dynamic> raw) {
    final Object? seq = raw["seq"];
    final Object? ts = raw["ts"];
    final Object? boxesRaw = raw["boxes"];
    if (seq is! num || ts is! num || boxesRaw is! List) {
      return null;
    }
    final List<DetectionBox> boxes = [];
    for (final Object? entry in boxesRaw) {
      final DetectionBox? box = DetectionBox.fromJson(entry);
      if (box == null) {
        return null;
      }
      boxes.add(box);
    }
    final Object? fovH = raw["fovH"];
    final Object? fovV = raw["fovV"];
    final Object? hl = raw["hl"];
    final Object? hr = raw["hr"];
    return DetectionFrame(
      seq: seq.toInt(),
      timestampMs: ts.toInt(),
      fovH: fovH is num ? fovH.toDouble() : 65,
      fovV: fovV is num ? fovV.toDouble() : 40,
      boxes: boxes,
      horizonLeft: hl is num && hr is num ? hl.toDouble() : null,
      horizonRight: hl is num && hr is num ? hr.toDouble() : null,
    );
  }
}
