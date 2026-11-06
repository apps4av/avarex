import 'dart:math';
import 'dart:typed_data';

import 'package:avaremp/visual_traffic/luma_frame.dart';

/// The horizon as a straight line across the upright picture.
///
/// Positions are fractions of the picture: `u` runs 0 (left) to 1 (right) and
/// `v` runs 0 (top) to 1 (bottom). Terrain and cars are below the horizon, so
/// they are ignored for the sky.
class HorizonLine {
  const HorizonLine({
    required this.vLeft,
    required this.vRight,
    this.skyAbove = true,
    this.confidence = 1,
    this.fromImage = true,
  });

  /// Where the line crosses the left and right edges. May be outside 0..1 when
  /// the horizon is off the picture.
  final double vLeft;
  final double vRight;

  /// True when the sky is the part above the line, the normal case.
  final bool skyAbove;

  /// 0..1 how well the picture supports this line.
  final double confidence;

  /// True when found in the picture, false when worked out from the phone's
  /// tilt sensors.
  final bool fromImage;

  double vAt(double u) => vLeft + (vRight - vLeft) * u;

  /// True when the point is sky, at least [margin] (a picture-height
  /// fraction) clear of the line. Anything closer counts as ground, because
  /// the line is only an estimate and hills and haze blur it.
  bool isSky(double u, double v, {double margin = 0.03}) {
    final double line = vAt(u);
    return skyAbove ? v < line - margin : v > line + margin;
  }

  /// How steeply the line runs, in degrees. Positive when it runs down toward
  /// the right edge. [aspect] is picture width divided by height.
  double tiltDegrees(double aspect) {
    return atan2((vRight - vLeft) / aspect, 1) * 180 / pi;
  }

  /// How far above the horizon the camera looks, in degrees. Negative when it
  /// looks below. [fovH] is the horizontal field of view in degrees.
  ///
  /// Null when the picture is upside down (the sky is below the line).
  double? pitchDegrees(double fovH, double aspect) {
    if (!skyAbove || aspect <= 0) {
      return null;
    }
    final double centerV = (vLeft + vRight) / 2;
    // Distance from the picture center to the line, in picture widths,
    // measured square to the line.
    final double offset = (centerV - 0.5) / aspect * cos(tiltDegrees(aspect) * pi / 180);
    final double focal = 0.5 / tan(fovH * pi / 360);
    return atan(offset / focal) * 180 / pi;
  }

  /// Blends a new estimate into this one, so one noisy frame does not move it.
  HorizonLine blend(HorizonLine next, double weight) {
    if (skyAbove != next.skyAbove) {
      return next;
    }
    final double w = weight.clamp(0.0, 1.0);
    return HorizonLine(
      vLeft: vLeft + (next.vLeft - vLeft) * w,
      vRight: vRight + (next.vRight - vRight) * w,
      skyAbove: skyAbove,
      confidence: next.confidence,
      fromImage: next.fromImage,
    );
  }

  /// Largest gap, in picture heights, between this line and [other] at either
  /// edge.
  double distanceTo(HorizonLine other) {
    return max((vLeft - other.vLeft).abs(), (vRight - other.vRight).abs());
  }

  /// Works out the horizon from which way is down, as the phone's
  /// accelerometer sees it.
  ///
  /// [gx], [gy], [gz] are the "down" direction in camera axes: x to the right
  /// of the upright picture, y toward the bottom of it, z out through the
  /// lens. [fovH] is the horizontal field of view in degrees and [aspect] is
  /// picture width divided by height.
  ///
  /// In a banked turn the accelerometer reports the aircraft's own "down",
  /// not the true one, so this only backs up the picture-based estimate.
  /// Returns null when the camera looks nearly straight up or down, or sideways
  /// so far that no horizon line crosses the picture.
  static HorizonLine? fromGravity({
    required double gx,
    required double gy,
    required double gz,
    required double fovH,
    required double aspect,
  }) {
    final double norm = sqrt(gx * gx + gy * gy + gz * gz);
    if (norm < 1e-6 || aspect <= 0) {
      return null;
    }
    final double x = gx / norm;
    final double y = gy / norm;
    final double z = gz / norm;
    if (y.abs() < 0.05) {
      return null;
    }
    // Focal length in units of picture widths.
    final double f = 0.5 / tan(fovH * pi / 360);
    // Points on the horizon satisfy x*du + y*dv + z*f = 0, where du and dv
    // are offsets from the picture center in picture widths. dv in picture
    // widths becomes picture heights by multiplying by the aspect ratio.
    double vAtU(double u) {
      final double du = u - 0.5;
      final double dv = -(z * f + x * du) / y;
      return 0.5 + dv * aspect;
    }

    return HorizonLine(
      vLeft: vAtU(0),
      vRight: vAtU(1),
      skyAbove: y > 0,
      confidence: 0.5,
      fromImage: false,
    );
  }
}

/// Finds the horizon in a small grayscale picture.
///
/// Clear sky is smooth and bright, ground is darker and busier, so the horizon
/// is the strongest steady brightness step down each column. A line is fitted
/// through those steps and kept only when most columns agree. Cloud edges and
/// hills are outliers and do not move the line.
class HorizonEstimator {
  HorizonEstimator({int seed = 7}) : _random = Random(seed);

  final Random _random;

  // Compare this many rows above and below each row.
  static const int _band = 3;
  // Smallest brightness step that counts as an edge.
  static const double _minStep = 10;
  static const int _columnSpacing = 4;

  /// Returns null when the picture shows no clear horizon, for example when
  /// looking straight up or into haze.
  HorizonLine? estimate(GrayImage image, {double minInlierFraction = 0.55}) {
    final int w = image.width;
    final int h = image.height;
    if (w < 32 || h < 4 * _band + 4) {
      return null;
    }
    final List<double> xs = [];
    final List<double> ys = [];
    final List<double> steps = [];
    for (int x = _columnSpacing; x < w - _columnSpacing; x += _columnSpacing) {
      final _Edge? edge = _columnEdge(image, x);
      if (edge != null) {
        xs.add(x.toDouble());
        ys.add(edge.y);
        steps.add(edge.step);
      }
    }
    final int columns = (w - 2 * _columnSpacing) ~/ _columnSpacing;
    if (xs.length < 12 || xs.length < columns * 0.4) {
      return null;
    }

    // RANSAC: line y = a + b*x through two edge points, most inliers wins.
    const double inlierDistance = 2.5;
    double bestA = 0;
    double bestB = 0;
    int bestCount = 0;
    for (int i = 0; i < 80; i++) {
      final int p = _random.nextInt(xs.length);
      final int q = _random.nextInt(xs.length);
      if ((xs[p] - xs[q]).abs() < w * 0.2) {
        continue;
      }
      final double b = (ys[q] - ys[p]) / (xs[q] - xs[p]);
      // A horizon tilted more than 45 degrees is not a horizon here.
      if (b.abs() > 1) {
        continue;
      }
      final double a = ys[p] - b * xs[p];
      int count = 0;
      for (int k = 0; k < xs.length; k++) {
        if ((ys[k] - (a + b * xs[k])).abs() <= inlierDistance) {
          count++;
        }
      }
      if (count > bestCount) {
        bestCount = count;
        bestA = a;
        bestB = b;
      }
    }
    if (bestCount < 8 || bestCount < xs.length * minInlierFraction) {
      return null;
    }

    // Least-squares refit on the inliers.
    double sx = 0, sy = 0, sxx = 0, sxy = 0;
    int n = 0;
    for (int k = 0; k < xs.length; k++) {
      if ((ys[k] - (bestA + bestB * xs[k])).abs() <= inlierDistance) {
        sx += xs[k];
        sy += ys[k];
        sxx += xs[k] * xs[k];
        sxy += xs[k] * ys[k];
        n++;
      }
    }
    final double denom = n * sxx - sx * sx;
    if (denom.abs() > 1e-9) {
      bestB = (n * sxy - sx * sy) / denom;
      bestA = (sy - bestB * sx) / n;
    }

    final double yLeft = bestA / h;
    final double yRight = (bestA + bestB * (w - 1)) / h;
    // A line hugging the very top or bottom is the edge of the picture, not
    // a horizon in it.
    if ((yLeft < 0.04 && yRight < 0.04) || (yLeft > 0.96 && yRight > 0.96)) {
      return null;
    }
    steps.sort();
    final double medianStep = steps[steps.length ~/ 2];
    if (medianStep < _minStep) {
      return null;
    }
    return HorizonLine(
      vLeft: yLeft,
      vRight: yRight,
      confidence: (bestCount / xs.length).clamp(0.0, 1.0),
    );
  }

  /// The topmost strong brightness step in one column.
  _Edge? _columnEdge(GrayImage image, int x) {
    final int w = image.width;
    final int h = image.height;
    final Uint8List data = image.data;
    final int lastRow = h - _band;
    final List<double> stepAt = List<double>.filled(h, 0);
    double strongest = 0;
    for (int y = _band; y <= lastRow - 1; y++) {
      int above = 0;
      int below = 0;
      for (int k = 1; k <= _band; k++) {
        above += data[(y - k) * w + x];
        below += data[(y + k - 1) * w + x];
      }
      final double step = (below - above) / _band;
      stepAt[y] = step;
      if (step.abs() > strongest) {
        strongest = step.abs();
      }
    }
    if (strongest < _minStep) {
      return null;
    }
    final double need = strongest * 0.6;
    for (int y = _band; y <= lastRow - 1; y++) {
      if (stepAt[y].abs() >= need) {
        // Walk to the local peak so the edge sits on the sharpest row.
        int peak = y;
        while (peak + 1 <= lastRow - 1 &&
            stepAt[peak + 1].abs() >= stepAt[peak].abs()) {
          peak++;
        }
        return _Edge(peak.toDouble(), stepAt[peak].abs());
      }
    }
    return null;
  }
}

class _Edge {
  const _Edge(this.y, this.step);
  final double y;
  final double step;
}
