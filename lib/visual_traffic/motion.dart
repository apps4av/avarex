import 'dart:math';

import 'package:avaremp/visual_traffic/luma_frame.dart';

/// How far the whole scene slid between two frames, in analysis pixels.
///
/// `cur(x, y)` matches `prev(x + dx, y + dy)`. A scene point that sat at
/// `p` in the previous frame is at `p - (dx, dy)` now.
class GlobalMotion {
  const GlobalMotion(this.dx, this.dy, {this.measured = false});

  final double dx;
  final double dy;

  /// False when the picture had too little detail to measure. The slide is
  /// then reported as zero, because a guess would drift.
  final bool measured;

  static const GlobalMotion none = GlobalMotion(0, 0);
}

/// Measures the sliding of the whole picture from one frame to the next, so
/// aircraft motion can be told apart from the aircraft carrying the camera
/// through a turn or bump.
class MotionEstimator {
  MotionEstimator({this.radius = 8, this.maxPoints = 120, this.gridStep = 20});

  /// Largest slide, in analysis pixels, searched each way.
  final int radius;
  final int maxPoints;
  final int gridStep;

  /// Searches for the slide that best lines [current] up with [previous].
  /// Ties and noise settle toward [prior] (the last measured slide), which
  /// stands in for a smooth turn.
  GlobalMotion estimate(
    GrayImage current,
    GrayImage previous, {
    GlobalMotion prior = GlobalMotion.none,
  }) {
    final int w = current.width;
    final int h = current.height;
    if (w != previous.width || h != previous.height) {
      return GlobalMotion.none;
    }
    final int margin = radius + 3;
    if (w < 2 * margin + 8 || h < 2 * margin + 8) {
      return GlobalMotion.none;
    }

    // Pick sample points with real detail: horizon, cloud edges, terrain.
    final List<_Point> points = [];
    for (int y = margin; y < h - margin; y += gridStep) {
      for (int x = margin; x < w - margin; x += gridStep) {
        final int gx = (current.at(x + 1, y) - current.at(x - 1, y)).abs();
        final int gy = (current.at(x, y + 1) - current.at(x, y - 1)).abs();
        final int g = gx + gy;
        if (g >= 24) {
          points.add(_Point(x, y, g));
        }
      }
    }
    if (points.length < 10) {
      return GlobalMotion.none;
    }
    points.sort((_Point a, _Point b) => b.strength.compareTo(a.strength));
    final List<_Point> used =
        points.length > maxPoints ? points.sublist(0, maxPoints) : points;

    // Sum of absolute differences of 3x3 patches for every candidate slide.
    final int centerX = prior.dx.round().clamp(-radius, radius);
    final int centerY = prior.dy.round().clamp(-radius, radius);
    double bestCost = double.infinity;
    int bestDx = 0;
    int bestDy = 0;
    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        int cost = 0;
        for (final _Point p in used) {
          for (int oy = -1; oy <= 1; oy++) {
            final int cy = (p.y + oy) * w;
            final int py = (p.y + oy + dy) * w;
            for (int ox = -1; ox <= 1; ox++) {
              final int diff = current.data[cy + p.x + ox] -
                  previous.data[py + p.x + ox + dx];
              cost += diff < 0 ? -diff : diff;
            }
          }
        }
        // A small pull toward the last slide settles ties and noise.
        final double score =
            cost + 0.5 * (dx - centerX).abs() + 0.5 * (dy - centerY).abs();
        if (score < bestCost) {
          bestCost = score;
          bestDx = dx;
          bestDy = dy;
        }
      }
    }
    // Reject a "best" slide that is no better than standing still, which
    // happens when the detail is just noise.
    int stillCost = 0;
    for (final _Point p in used) {
      for (int oy = -1; oy <= 1; oy++) {
        for (int ox = -1; ox <= 1; ox++) {
          final int diff = current.data[(p.y + oy) * w + p.x + ox] -
              previous.data[(p.y + oy) * w + p.x + ox];
          stillCost += diff < 0 ? -diff : diff;
        }
      }
    }
    if (max(bestDx.abs(), bestDy.abs()) > 0 && stillCost * 0.9 < bestCost) {
      return const GlobalMotion(0, 0, measured: true);
    }
    return GlobalMotion(bestDx.toDouble(), bestDy.toDouble(), measured: true);
  }
}

class _Point {
  const _Point(this.x, this.y, this.strength);
  final int x;
  final int y;
  final int strength;
}
