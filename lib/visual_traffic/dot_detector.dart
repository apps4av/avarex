import 'dart:math';
import 'dart:typed_data';

import 'package:avaremp/visual_traffic/luma_frame.dart';

/// A small spot that stands out from its surroundings: a possible aircraft.
/// Positions are pixels of the analysis picture.
class DotCandidate {
  DotCandidate({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.area,
    required this.contrast,
  });

  /// Center of the spot.
  final double x;
  final double y;

  /// Bounding box size and pixel count.
  final int width;
  final int height;
  final int area;

  /// Mean brightness difference from the surroundings. Negative is darker.
  final double contrast;

  /// True when the spot is below the horizon, or the horizon is unknown and
  /// the caller marks it so.
  bool below = false;
}

class DotResult {
  const DotResult({
    required this.candidates,
    required this.skyCount,
    required this.cluttered,
    required this.threshold,
  });

  final List<DotCandidate> candidates;

  /// Spots seen in the sky part of the picture, before any were dropped.
  final int skyCount;

  /// Too many spots in the sky to trust any of them: terrain, heavy cloud
  /// texture, rain or a dirty windshield.
  final bool cluttered;

  /// Brightness difference a spot needed to count.
  final double threshold;
}

/// Finds small compact spots that differ from their local surroundings.
///
/// A distant aircraft is a few pixels of dark or bright against smooth sky.
/// Each pixel is compared with the average of a box around it. Pixels that
/// differ by more than a noise-based threshold are grouped, and groups that
/// are small and compact are kept. Long thin things such as the horizon and
/// cloud edges, and large things such as clouds, are dropped.
class DotDetector {
  DotDetector({
    this.radius = 5,
    this.minContrast = 12,
    this.sigmas = 6,
    this.maxArea = 80,
    this.maxSide = 12,
    this.maxSkyCandidates = 30,
    this.belowFactor = 1.8,
    this.maxBelow = 12,
  });

  /// Half width of the surrounding box.
  final int radius;

  /// Never use a threshold smaller than this many gray levels.
  final double minContrast;

  /// Threshold is at least this many noise standard deviations.
  final double sigmas;

  final int maxArea;
  final int maxSide;
  final int maxSkyCandidates;

  /// Spots below the horizon need this many times the sky threshold.
  final double belowFactor;
  final int maxBelow;

  Int32List _integral = Int32List(0);
  Int16List _diff = Int16List(0);
  Int8List _cls = Int8List(0);
  Uint8List _seen = Uint8List(0);
  Int32List _stack = Int32List(0);

  /// [sensitivity] above 1 finds fainter spots (and more false ones), below 1
  /// finds fewer. [isSky] says whether a point, as fractions of the picture,
  /// is sky. Without it every point is treated as sky.
  DotResult detect(
    GrayImage image, {
    double sensitivity = 1,
    bool Function(double u, double v)? isSky,
  }) {
    final int w = image.width;
    final int h = image.height;
    final int r = radius;
    if (w < 2 * r + 3 || h < 2 * r + 3) {
      return const DotResult(
          candidates: [], skyCount: 0, cluttered: false, threshold: 0);
    }
    _ensureBuffers(w, h);
    _buildIntegral(image);

    // Brightness minus the average of the box around each pixel.
    final Int16List diff = _diff;
    final int side = 2 * r + 1;
    final int boxArea = side * side;
    final int stride = w + 1;
    for (int y = 0; y < h; y++) {
      final bool yInside = y >= r && y < h - r;
      for (int x = 0; x < w; x++) {
        final int index = y * w + x;
        if (!yInside || x < r || x >= w - r) {
          diff[index] = 0;
          continue;
        }
        final int x0 = x - r;
        final int y0 = y - r;
        final int sum = _integral[(y0 + side) * stride + x0 + side] -
            _integral[y0 * stride + x0 + side] -
            _integral[(y0 + side) * stride + x0] +
            _integral[y0 * stride + x0];
        diff[index] = image.data[index] - sum ~/ boxArea;
      }
    }

    final double threshold = max(minContrast, sigmas * _noise(w, h, isSky)) /
        (sensitivity <= 0 ? 1 : sensitivity);

    final Int8List cls = _cls;
    final int t = threshold.ceil();
    for (int i = 0; i < diff.length; i++) {
      final int d = diff[i];
      cls[i] = d > t ? 1 : (d < -t ? -1 : 0);
    }

    final List<DotCandidate> sky = [];
    final List<DotCandidate> below = [];
    int skyCount = 0;
    _seen.fillRange(0, w * h, 0);
    for (int start = 0; start < w * h; start++) {
      final int sign = cls[start];
      if (sign == 0 || _seen[start] != 0) {
        continue;
      }
      final DotCandidate? dot = _flood(start, sign, w, h);
      if (dot == null) {
        continue;
      }
      final bool inSky = isSky == null || isSky(dot.x / w, dot.y / h);
      if (inSky) {
        skyCount++;
        sky.add(dot);
      } else {
        dot.below = true;
        if (dot.contrast.abs() >= threshold * belowFactor) {
          below.add(dot);
        }
      }
    }

    final bool cluttered = skyCount > maxSkyCandidates;
    int byStrength(DotCandidate a, DotCandidate b) =>
        b.contrast.abs().compareTo(a.contrast.abs());
    sky.sort(byStrength);
    below.sort(byStrength);
    final List<DotCandidate> kept = [
      ...sky.take(maxSkyCandidates),
      ...below.take(maxBelow),
    ];
    return DotResult(
      candidates: kept,
      skyCount: skyCount,
      cluttered: cluttered,
      threshold: threshold,
    );
  }

  void _ensureBuffers(int w, int h) {
    if (_diff.length != w * h) {
      _diff = Int16List(w * h);
      _cls = Int8List(w * h);
      _seen = Uint8List(w * h);
      _stack = Int32List(w * h);
      _integral = Int32List((w + 1) * (h + 1));
    }
  }

  void _buildIntegral(GrayImage image) {
    final int w = image.width;
    final int h = image.height;
    final int stride = w + 1;
    for (int x = 0; x <= w; x++) {
      _integral[x] = 0;
    }
    for (int y = 0; y < h; y++) {
      int rowSum = 0;
      _integral[(y + 1) * stride] = 0;
      for (int x = 0; x < w; x++) {
        rowSum += image.data[y * w + x];
        _integral[(y + 1) * stride + x + 1] = _integral[y * stride + x + 1] + rowSum;
      }
    }
  }

  /// Standard deviation of the picture noise, from the median absolute
  /// difference of sampled sky pixels. Robust to a few real objects.
  double _noise(int w, int h, bool Function(double u, double v)? isSky) {
    final List<int> histogram = List<int>.filled(256, 0);
    int count = 0;
    for (int y = radius; y < h - radius; y += 5) {
      for (int x = radius; x < w - radius; x += 5) {
        if (isSky != null && !isSky(x / w, y / h)) {
          continue;
        }
        int d = _diff[y * w + x];
        d = d < 0 ? -d : d;
        histogram[d > 255 ? 255 : d]++;
        count++;
      }
    }
    if (count < 50) {
      return 2;
    }
    int seen = 0;
    int median = 0;
    for (int i = 0; i < 256; i++) {
      seen += histogram[i];
      if (seen * 2 >= count) {
        median = i;
        break;
      }
    }
    final double sigma = 1.4826 * median;
    return sigma < 1 ? 1 : sigma;
  }

  /// Groups connected pixels of the same sign starting at [start], returning
  /// null when the group is the wrong shape or size.
  DotCandidate? _flood(int start, int sign, int w, int h) {
    int top = 0;
    _stack[top++] = start;
    _seen[start] = 1;
    int area = 0;
    int minX = w, maxX = 0, minY = h, maxY = 0;
    double sumX = 0, sumY = 0, sumDiff = 0;
    while (top > 0) {
      final int index = _stack[--top];
      final int y = index ~/ w;
      final int x = index - y * w;
      area++;
      sumX += x;
      sumY += y;
      sumDiff += _diff[index];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      for (int dy = -1; dy <= 1; dy++) {
        final int ny = y + dy;
        if (ny < 0 || ny >= h) {
          continue;
        }
        for (int dx = -1; dx <= 1; dx++) {
          final int nx = x + dx;
          if (nx < 0 || nx >= w || (dx == 0 && dy == 0)) {
            continue;
          }
          final int n = ny * w + nx;
          if (_seen[n] == 0 && _cls[n] == sign) {
            _seen[n] = 1;
            _stack[top++] = n;
          }
        }
      }
    }
    final int bw = maxX - minX + 1;
    final int bh = maxY - minY + 1;
    if (area > maxArea || bw > maxSide || bh > maxSide) {
      return null;
    }
    // A thin streak is an edge, not an aircraft.
    if (area / (bw * bh) < 0.3 && area > 3) {
      return null;
    }
    final double meanDiff = sumDiff / area;
    // A one-pixel flicker must be very strong to count.
    if (area < 2 && meanDiff.abs() < 40) {
      return null;
    }
    return DotCandidate(
      x: sumX / area + 0.5,
      y: sumY / area + 0.5,
      width: bw,
      height: bh,
      area: area,
      contrast: meanDiff,
    );
  }
}
