import 'dart:math';

/// How far the camera turned since the previous frame, from the gyroscope.
///
/// Radians about the camera's axes: x to the right of the upright picture, y
/// toward its bottom, z out through the lens.
class MotionHint {
  const MotionHint(this.rx, this.ry, this.rz);

  final double rx;
  final double ry;
  final double rz;
}

/// What the gyroscope's turn amounts to in the picture, in analysis pixels.
class GyroPrediction {
  const GyroPrediction(this.dx, this.dy);

  /// The scene's slide, in the same sense as the picture-measured slide.
  final double dx;
  final double dy;
}

enum GyroState {
  /// No gyroscope readings reached the analyzer.
  none,

  /// Not enough turning yet to tell whether the gyroscope and the picture
  /// agree.
  learning,

  /// The gyroscope's turn matches how the picture slid.
  agrees,

  /// There was turning, but the picture did not slide to match it.
  mismatch,
}

class GyroReport {
  const GyroReport({
    required this.state,
    this.correlation,
    this.scaleX,
    this.scaleY,
    this.filledIn = false,
    this.predictedX = 0,
    this.predictedY = 0,
  });

  static const GyroReport none = GyroReport(state: GyroState.none);

  final GyroState state;

  /// 1 when the gyroscope and the picture move together perfectly. Null while
  /// learning.
  final double? correlation;

  /// How many picture pixels of slide each gyroscope pixel is worth, for
  /// each axis. Near 1 is right. Negative means the axis is reversed.
  final double? scaleX;
  final double? scaleY;

  /// True when the picture had nothing to measure and the gyroscope's slide
  /// was used instead.
  final bool filledIn;

  /// The slide the gyroscope calls for this frame, in analysis pixels.
  final double predictedX;
  final double predictedY;
}

/// Compares the gyroscope's turn with how the picture slid, and learns how
/// much to trust it.
///
/// The picture measures the slide directly when it has detail. In empty sky
/// it cannot. The gyroscope can always say how far the camera turned. So the
/// two are compared whenever both exist, and once they have been seen to agree
/// the gyroscope fills in when the picture cannot be measured.
///
/// The sign and size of each axis are learned from the data, so a
/// reversed or mis-scaled axis cannot do harm. A gyroscope that does not agree
/// with the picture is never used.
class GyroMotion {
  GyroMotion({
    this.forget = 0.97,
    this.minEnergy = 4,
    this.minCorrelation = 0.8,
    this.maxClamp = 7.5,
  });

  /// Weight kept from earlier frames each time a new pair is added.
  final double forget;

  /// Sum of squared predicted slide, in square pixels, needed before an axis
  /// can be judged.
  final double minEnergy;

  /// An axis is trusted when its correlation is at least this.
  final double minCorrelation;

  /// Measured slides this close to the search limit are not used for
  /// learning, because the search may have been cut off.
  final double maxClamp;

  final _Axis _x = _Axis();
  final _Axis _y = _Axis();

  void reset() {
    _x.clear();
    _y.clear();
  }

  /// The slide the gyroscope calls for, before it is scaled, in the same
  /// sense as the picture-measured slide (turning right gives a positive
  /// `dx`). The learned scale corrects it if a sensor says otherwise.
  GyroPrediction predict(MotionHint hint, double fovH, int pictureWidth) {
    final double focal = (pictureWidth / 2) / tan(fovH * pi / 360);
    return GyroPrediction(hint.ry * focal, -hint.rx * focal);
  }

  /// Slide to use for a frame, scaled by what has been learned. Null when
  /// neither axis is trusted yet. An axis that is not trusted counts as zero.
  GyroPrediction? expected(GyroPrediction predicted) {
    final double? kx = _x.trusted(minEnergy, minCorrelation);
    final double? ky = _y.trusted(minEnergy, minCorrelation);
    if (kx == null && ky == null) {
      return null;
    }
    return GyroPrediction(
      kx == null ? 0 : predicted.dx * kx,
      ky == null ? 0 : predicted.dy * ky,
    );
  }

  /// Adds a frame where both the gyroscope and the picture gave a slide.
  void learn(GyroPrediction predicted, double measuredDx, double measuredDy) {
    if (measuredDx.abs() < maxClamp) {
      _x.add(predicted.dx, measuredDx, forget);
    }
    if (measuredDy.abs() < maxClamp) {
      _y.add(predicted.dy, measuredDy, forget);
    }
  }

  GyroReport report(GyroPrediction? predicted, {required bool filledIn}) {
    final double? kx = _x.trusted(minEnergy, minCorrelation);
    final double? ky = _y.trusted(minEnergy, minCorrelation);
    final bool xJudged = _x.energy >= minEnergy;
    final bool yJudged = _y.energy >= minEnergy;
    final GyroState state;
    if (kx != null || ky != null) {
      state = GyroState.agrees;
    } else if (xJudged || yJudged) {
      state = GyroState.mismatch;
    } else {
      state = GyroState.learning;
    }
    // Report the axis that has the most turning in it.
    final _Axis main = _x.energy >= _y.energy ? _x : _y;
    return GyroReport(
      state: state,
      correlation: (xJudged || yJudged) ? main.correlation : null,
      scaleX: xJudged ? _x.scale : null,
      scaleY: yJudged ? _y.scale : null,
      filledIn: filledIn,
      predictedX: predicted?.dx ?? 0,
      predictedY: predicted?.dy ?? 0,
    );
  }
}

class _Axis {
  double _pp = 0;
  double _mm = 0;
  double _pm = 0;

  void clear() {
    _pp = _mm = _pm = 0;
  }

  void add(double predicted, double measured, double forget) {
    _pp = _pp * forget + predicted * predicted;
    _mm = _mm * forget + measured * measured;
    _pm = _pm * forget + predicted * measured;
  }

  double get energy => _pp;

  double get scale => _pp < 1e-9 ? 0 : _pm / _pp;

  double get correlation {
    final double d = sqrt(_pp * _mm);
    return d < 1e-9 ? 0 : _pm / d;
  }

  /// The scale to use, or null when this axis cannot be trusted.
  double? trusted(double minEnergy, double minCorrelation) {
    if (_pp < minEnergy) {
      return null;
    }
    final double k = scale;
    if (correlation.abs() < minCorrelation || k.abs() < 0.4 || k.abs() > 2.5) {
      return null;
    }
    return k;
  }
}
