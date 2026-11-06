import 'package:avaremp/visual_traffic/detection_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Draws boxes over a picture. Red for a target the model called an airplane,
/// a thin yellow box for a small mover it could not classify.
///
/// Boxes are fractions of the picture, so this paints into whatever size it
/// is given, which must be the size the picture is shown at.
class DetectionPainter extends CustomPainter {
  DetectionPainter({
    required this.boxes,
    required this.fovH,
    required this.fovV,
    this.horizonLeft,
    this.horizonRight,
    this.showHorizon = false,
    this.dimmed = false,
  });

  final List<DetectionBox> boxes;
  final double fovH;
  final double fovV;
  final double? horizonLeft;
  final double? horizonRight;
  final bool showHorizon;

  /// Draws everything faintly, for data that has gone stale.
  final bool dimmed;

  /// Smallest box edge, in screen pixels, so a distant target is still seen.
  static const double minEdge = 18;

  static const Color airplaneColor = Color(0xFFFF1E1E);
  static const Color possibleColor = Color(0xFFFFD60A);

  /// Degrees off the camera axis to the middle of a box, as "12L 3U" style
  /// text. Right and up are positive. Small-angle, which is fine for a phone
  /// camera's field of view.
  static String bearingLabel(DetectionBox box, double fovH, double fovV) {
    final double azimuth = (box.centerX - 0.5) * fovH;
    final double elevation = (0.5 - box.centerY) * fovV;
    final String side = azimuth >= 0 ? "R" : "L";
    final String vertical = elevation >= 0 ? "up" : "down";
    return "${azimuth.abs().round()}° $side  ${elevation.abs().round()}° $vertical";
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (showHorizon && horizonLeft != null && horizonRight != null) {
      final Paint line = Paint()
        ..color = Colors.lightBlueAccent.withValues(alpha: dimmed ? 0.2 : 0.6)
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(0, horizonLeft! * size.height),
        Offset(size.width, horizonRight! * size.height),
        line,
      );
    }
    // Yellow first so a red box is never hidden under one.
    final List<DetectionBox> ordered = [
      ...boxes.where((DetectionBox b) => b.tier == DetectionTier.possible),
      ...boxes.where((DetectionBox b) => b.tier == DetectionTier.airplane),
    ];
    for (final DetectionBox box in ordered) {
      final bool airplane = box.tier == DetectionTier.airplane;
      final double alpha = dimmed ? 0.3 : 1;
      final Paint stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = airplane ? 3 : 1.5
        ..color = (airplane ? airplaneColor : possibleColor).withValues(alpha: alpha);
      final double w = (box.w * size.width).clamp(minEdge, size.width);
      final double h = (box.h * size.height).clamp(minEdge, size.height);
      final double cx = box.centerX * size.width;
      final double cy = box.centerY * size.height;
      final Rect rect = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
      canvas.drawRect(rect, stroke);
      if (airplane) {
        final TextPainter label = TextPainter(
          text: TextSpan(
            text: bearingLabel(box, fovH, fovV),
            style: TextStyle(
              color: airplaneColor.withValues(alpha: alpha),
              fontSize: 13,
              fontWeight: FontWeight.bold,
              shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        // Under the box, or above it when there is no room below.
        double ly = rect.bottom + 2;
        if (ly + label.height > size.height) {
          ly = rect.top - label.height - 2;
        }
        double lx = rect.left;
        if (lx + label.width > size.width) {
          lx = size.width - label.width;
        }
        label.paint(canvas, Offset(lx < 0 ? 0 : lx, ly));
      }
    }
  }

  @override
  bool shouldRepaint(DetectionPainter old) {
    return old.boxes != boxes ||
        old.dimmed != dimmed ||
        old.showHorizon != showHorizon ||
        old.horizonLeft != horizonLeft ||
        old.horizonRight != horizonRight ||
        old.fovH != fovH ||
        old.fovV != fovV;
  }
}

/// Beeps and vibrates when an airplane gets a red box that was not there
/// before. Not more than once every few seconds, and only for red boxes.
class TrafficAlert {
  TrafficAlert({this.minGap = const Duration(seconds: 5)});

  final Duration minGap;
  final Set<int> _known = {};
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// Returns true when this frame has a red box that was not in an earlier
  /// frame and the alert was due.
  bool update(List<DetectionBox> boxes, {DateTime? now}) {
    final DateTime at = now ?? DateTime.now();
    final Set<int> current = boxes
        .where((DetectionBox b) => b.tier == DetectionTier.airplane)
        .map((DetectionBox b) => b.id)
        .toSet();
    final bool fresh = current.any((int id) => !_known.contains(id));
    _known
      ..clear()
      ..addAll(current);
    if (fresh && at.difference(_last) >= minGap) {
      _last = at;
      return true;
    }
    return false;
  }

  void reset() {
    _known.clear();
  }

  /// Plays the alert sound and a heavy buzz.
  static void sound() {
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();
  }
}
