import 'package:flutter/material.dart';

/// Shared CIFP overlay colors for the plate route and vertical profile.
/// Colored by how many legs remain until the final fix.
class ProcedureRouteColors {
  static const Color finalLeg = Color(0xFF2E7D32); // green
  static const Color before1 = Color(0xFFF9A825); // yellow
  static const Color before2 = Color(0xFF6D4C41); // brown
  static const Color before3 = Color(0xFF1565C0); // blue
  static const Color before4 = Color(0xFFC62828); // red
  static const Color before5Plus = Color(0xFFEF6C00); // orange

  /// [legsFromFinal] 0 = final leg, 1 = one before final, …
  static Color forLegsFromFinal(int legsFromFinal) {
    switch (legsFromFinal) {
      case 0:
        return finalLeg;
      case 1:
        return before1;
      case 2:
        return before2;
      case 3:
        return before3;
      case 4:
        return before4;
      default:
        return before5Plus;
    }
  }

  /// Color for the segment that ends at [fixIndex] (0-based) in a route of [fixCount] fixes.
  static Color forSegmentEndingAt(int fixIndex, int fixCount) {
    if (fixCount <= 0) {
      return before5Plus;
    }
    final int last = fixCount - 1;
    return forLegsFromFinal(last - fixIndex);
  }
}

/// Paints the CIFP route colored by distance from the final fix.
void paintProcedureRoute({
  required Canvas canvas,
  required List<Offset> offsets,
}) {
  if (offsets.length < 2) {
    return;
  }

  for (int i = 1; i < offsets.length; i++) {
    final Color color = ProcedureRouteColors.forSegmentEndingAt(i, offsets.length);
    final Paint use = Paint()
      ..isAntiAlias = true
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = (i == offsets.length - 1) ? 5.5 : 4.5;
    canvas.drawLine(offsets[i - 1], offsets[i], use);
  }
}
