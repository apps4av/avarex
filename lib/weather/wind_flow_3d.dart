import 'dart:math' as math;

import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/winds_aloft.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// East and north parts of the wind, in knots, in the direction the air moves.
class WindVector {
  final double eastKt;
  final double northKt;

  const WindVector(this.eastKt, this.northKt);

  static const zero = WindVector(0, 0);

  double get speedKt {
    final squared = eastKt * eastKt + northKt * northKt;
    if (squared <= 0 || !squared.isFinite) {
      return 0;
    }
    return math.sqrt(squared);
  }
}

/// [fromDegrees] is the direction the wind comes from. The vector points downwind.
WindVector windVectorFrom(double fromDegrees, double speedKt) {
  if (!fromDegrees.isFinite || !speedKt.isFinite || speedKt <= 0) {
    return WindVector.zero;
  }
  final toward = (fromDegrees + 180.0) * math.pi / 180.0;
  return WindVector(speedKt * math.sin(toward), speedKt * math.cos(toward));
}

/// Inverse-distance blend in vector space, so a wind from 350° and one from 10°
/// meet in between instead of averaging to south.
WindVector blendWindVectors(
    List<({WindVector wind, double distanceNm})> samples) {
  if (samples.isEmpty) {
    return WindVector.zero;
  }
  if (samples.length == 1) {
    return samples.first.wind;
  }
  var east = 0.0;
  var north = 0.0;
  var weightSum = 0.0;
  for (final sample in samples) {
    final distance = sample.distanceNm < 1 ? 1.0 : sample.distanceNm;
    final weight = 1.0 / (distance * distance);
    east += sample.wind.eastKt * weight;
    north += sample.wind.northKt * weight;
    weightSum += weight;
  }
  if (weightSum <= 0) {
    return WindVector.zero;
  }
  return WindVector(east / weightSum, north / weightSum);
}

/// Blue is light, green is moderate, yellow and orange are fresh, red is strong.
const List<WindSpeedColor> windSpeedColors = [
  WindSpeedColor(0, Color(0xFF1E88E5)),
  WindSpeedColor(12, Color(0xFF00ACC1)),
  WindSpeedColor(24, Color(0xFF43A047)),
  WindSpeedColor(36, Color(0xFFFDD835)),
  WindSpeedColor(48, Color(0xFFFB8C00)),
  WindSpeedColor(60, Color(0xFFE53935)),
];

class WindSpeedColor {
  final double knots;
  final Color color;

  const WindSpeedColor(this.knots, this.color);
}

Color windSpeedColor(double knots) {
  final speed = knots.isFinite && knots > 0 ? knots : 0.0;
  if (speed <= windSpeedColors.first.knots) {
    return windSpeedColors.first.color;
  }
  if (speed >= windSpeedColors.last.knots) {
    return windSpeedColors.last.color;
  }
  for (var i = 0; i < windSpeedColors.length - 1; i++) {
    final lower = windSpeedColors[i];
    final upper = windSpeedColors[i + 1];
    if (speed <= upper.knots) {
      final span = upper.knots - lower.knots;
      final t = span <= 0 ? 0.0 : (speed - lower.knots) / span;
      return Color.lerp(lower.color, upper.color, t) ?? upper.color;
    }
  }
  return windSpeedColors.last.color;
}

/// Altitudes that fill the visible 3D box. The forecast is sampled on these levels.
List<double> windFlowAltitudes(double maxAltitudeFt) {
  final top =
      maxAltitudeFt.isFinite ? maxAltitudeFt.clamp(2000.0, 18000.0) : 2000.0;
  final ceiling = top * 0.92;
  final floor = math.min(1500.0, ceiling * 0.4);
  final count = top <= 4500 ? 2 : (top <= 8000 ? 3 : 4);
  return [
    for (var i = 0; i < count; i++) floor + (ceiling - floor) * i / (count - 1),
  ];
}

/// 30 kt crosses the 50 NM view in about 10 seconds.
const double windFlowVisualNmPerKnotSecond = 50 / 10 / 30;

double windFlowStepNm(double knots, double dtSeconds) {
  final dt = dtSeconds.isFinite ? dtSeconds.clamp(0.0, 0.05) : 0.0;
  final speed = knots.isFinite && knots > 0 ? knots : 0.0;
  return speed * windFlowVisualNmPerKnotSecond * dt;
}

double windFlowLengthNm(double knots) {
  final length = (knots.isFinite && knots > 0 ? knots : 0.0) *
      windFlowVisualNmPerKnotSecond *
      0.4;
  if (length < 0.22) {
    return 0.22;
  }
  if (length > 1.4) {
    return 1.4;
  }
  return length;
}

/// Nautical miles between two points. Independent of the distance unit setting.
double windFlowNm(LatLng a, LatLng b) {
  final cosLat = math
      .cos(((a.latitude + b.latitude) / 2) * math.pi / 180)
      .abs()
      .clamp(0.2, 1.0);
  final east = (b.longitude - a.longitude) * 60.0 * cosLat;
  final north = (b.latitude - a.latitude) * 60.0;
  return math.sqrt(east * east + north * north);
}

LatLng windFlowLatLng(LatLng center, double eastNm, double northNm) {
  final cosLat =
      math.cos(center.latitude * math.pi / 180).abs().clamp(0.2, 1.0);
  return LatLng(
    center.latitude + northNm / 60.0,
    center.longitude + eastNm / (60.0 * cosLat),
  );
}

/// Wind samples on a volume covering the 3D square.
class WindFlowField {
  final int cols;
  final int rows;
  final double radiusNm;
  final List<double> altitudesFt;
  final List<double> eastKt;
  final List<double> northKt;

  WindFlowField({
    required this.cols,
    required this.rows,
    required this.radiusNm,
    required this.altitudesFt,
    required this.eastKt,
    required this.northKt,
  });

  bool get hasWind {
    for (var i = 0; i < eastKt.length && i < northKt.length; i++) {
      if (eastKt[i] * eastKt[i] + northKt[i] * northKt[i] > 0.25) {
        return true;
      }
    }
    return false;
  }

  WindVector sample(double eastNm, double northNm, double altitudeFt) {
    if (radiusNm <= 0 || cols < 2 || rows < 2 || altitudesFt.isEmpty) {
      return WindVector.zero;
    }
    final east = eastNm.clamp(-radiusNm, radiusNm);
    final north = northNm.clamp(-radiusNm, radiusNm);
    final u = (east + radiusNm) / (2 * radiusNm) * (cols - 1);
    final v = (north + radiusNm) / (2 * radiusNm) * (rows - 1);
    if (altitudesFt.length == 1 || altitudeFt <= altitudesFt.first) {
      return _bilinear(0, u, v);
    }
    if (altitudeFt >= altitudesFt.last) {
      return _bilinear(altitudesFt.length - 1, u, v);
    }
    var upper = 1;
    while (upper < altitudesFt.length - 1 && altitudesFt[upper] < altitudeFt) {
      upper++;
    }
    final lower = upper - 1;
    final span = altitudesFt[upper] - altitudesFt[lower];
    final t = span <= 0 ? 0.0 : (altitudeFt - altitudesFt[lower]) / span;
    return _lerp(_bilinear(lower, u, v), _bilinear(upper, u, v), t);
  }

  WindVector _bilinear(int level, double u, double v) {
    final x = u.clamp(0.0, cols - 1.000001);
    final y = v.clamp(0.0, rows - 1.000001);
    final x0 = x.floor();
    final y0 = y.floor();
    final tx = x - x0;
    final ty = y - y0;
    final a = _at(level, x0, y0);
    final b = _at(level, x0 + 1, y0);
    final c = _at(level, x0, y0 + 1);
    final d = _at(level, x0 + 1, y0 + 1);
    return _lerp(_lerp(a, b, tx), _lerp(c, d, tx), ty);
  }

  WindVector _at(int level, int col, int row) {
    final index = (level * rows + row) * cols + col;
    if (index < 0 || index >= eastKt.length || index >= northKt.length) {
      return WindVector.zero;
    }
    return WindVector(eastKt[index], northKt[index]);
  }

  WindVector _lerp(WindVector a, WindVector b, double t) {
    return WindVector(
      a.eastKt + (b.eastKt - a.eastKt) * t,
      a.northKt + (b.northKt - a.northKt) * t,
    );
  }
}

WindFlowField prepareWindFlowField({
  required double radiusNm,
  required double maxAltitudeFt,
  required WindVector Function(double eastNm, double northNm, double altitudeFt)
      sample,
  int cols = 5,
  int rows = 5,
}) {
  final altitudes = windFlowAltitudes(maxAltitudeFt);
  final eastKt = <double>[];
  final northKt = <double>[];
  for (final altitude in altitudes) {
    for (var row = 0; row < rows; row++) {
      final north =
          rows == 1 ? 0.0 : -radiusNm + 2 * radiusNm * row / (rows - 1);
      for (var col = 0; col < cols; col++) {
        final east =
            cols == 1 ? 0.0 : -radiusNm + 2 * radiusNm * col / (cols - 1);
        final wind = sample(east, north, altitude);
        eastKt.add(wind.eastKt);
        northKt.add(wind.northKt);
      }
    }
  }
  return WindFlowField(
    cols: cols,
    rows: rows,
    radiusNm: radiusNm,
    altitudesFt: altitudes,
    eastKt: eastKt,
    northKt: northKt,
  );
}

/// 6-hour winds aloft, blended from the nearest stations into the 3D volume.
WindFlowField loadCachedWindFlowField({
  required LatLng center,
  required double radiusNm,
  required double maxAltitudeFt,
  int forecastHours = 6,
}) {
  final knotsTo = Storage().units.knotsTo == 0 ? 1.0 : Storage().units.knotsTo;
  final fore = '${forecastHours.toString().padLeft(2, '0')}H';
  final stations = WindsCache.stationsNear(center);
  final cache = <String, WindVector?>{};

  WindVector? read(String id, double altitudeFt) {
    final key = '$id@$fore@${altitudeFt.toStringAsFixed(0)}';
    return cache.putIfAbsent(key, () {
      final report = Storage().winds.get('$id$fore');
      if (report is! WindsAloft) {
        return null;
      }
      final (dir, speed) = report.getWindAtAltitude(altitudeFt);
      if (dir == null || speed == null) {
        return null;
      }
      return windVectorFrom(dir, speed / knotsTo);
    });
  }

  return prepareWindFlowField(
    radiusNm: radiusNm,
    maxAltitudeFt: maxAltitudeFt,
    sample: (east, north, altitude) {
      final at = windFlowLatLng(center, east, north);
      final samples = <({WindVector wind, double distanceNm})>[];
      for (final station in stations) {
        final wind = read(station.id, altitude);
        if (wind == null) {
          continue;
        }
        samples.add((wind: wind, distanceNm: windFlowNm(at, station.at)));
      }
      return blendWindVectors(samples);
    },
  );
}

const int windFlowParticleCount = 320;

class WindFlowParticle {
  double eastNm;
  double northNm;
  double altitudeFt;
  double ageSeconds;
  double maxAgeSeconds;

  WindFlowParticle({
    required this.eastNm,
    required this.northNm,
    required this.altitudeFt,
    required this.ageSeconds,
    required this.maxAgeSeconds,
  });

  factory WindFlowParticle.fresh(
    math.Random random,
    double radiusNm,
    double maxAltitudeFt, {
    int band = 0,
    int bands = 1,
  }) {
    final particle = WindFlowParticle(
      eastNm: 0,
      northNm: 0,
      altitudeFt: 0,
      ageSeconds: 0,
      maxAgeSeconds: 1,
    );
    resetWindParticle(particle, random, radiusNm, maxAltitudeFt,
        band: band, bands: bands);
    particle.ageSeconds = random.nextDouble() * particle.maxAgeSeconds;
    return particle;
  }
}

class WindFlowStreak {
  final double headEast;
  final double headNorth;
  final double tailEast;
  final double tailNorth;
  final double altitudeFt;
  final double speedKt;
  final double alpha;

  const WindFlowStreak({
    required this.headEast,
    required this.headNorth,
    required this.tailEast,
    required this.tailNorth,
    required this.altitudeFt,
    required this.speedKt,
    required this.alpha,
  });
}

void resetWindParticle(
  WindFlowParticle particle,
  math.Random random,
  double radiusNm,
  double maxAltitudeFt, {
  int band = -1,
  int bands = 1,
}) {
  final levels = windFlowAltitudes(maxAltitudeFt);
  final low = levels.first;
  final high = levels.last;
  final slice = band < 0 || bands <= 1
      ? random.nextDouble()
      : ((band + random.nextDouble()) / bands).clamp(0.0, 0.999);
  final span = radiusNm * 0.92;
  particle
    ..eastNm = _lerp(-span, span, random.nextDouble())
    ..northNm = _lerp(-span, span, random.nextDouble())
    ..altitudeFt = _lerp(low, high, slice)
    ..ageSeconds = 0
    ..maxAgeSeconds = _lerp(5.5, 9.0, random.nextDouble());
}

List<WindFlowParticle> seedWindParticles({
  required math.Random random,
  required double radiusNm,
  required double maxAltitudeFt,
  int count = windFlowParticleCount,
}) {
  const bands = 8;
  return [
    for (var i = 0; i < count; i++)
      WindFlowParticle.fresh(random, radiusNm, maxAltitudeFt,
          band: i % bands, bands: bands),
  ];
}

/// Tail of a streak that stays at or above the ground. Null when the head is underground.
({double east, double north})? windStreakAboveGround({
  required double headEast,
  required double headNorth,
  required double tailEast,
  required double tailNorth,
  required double altitudeFt,
  required double? Function(double eastNm, double northNm) groundFt,
}) {
  bool above(double east, double north) {
    final ground = groundFt(east, north);
    if (ground == null || !ground.isFinite) {
      return true;
    }
    return altitudeFt >= ground;
  }

  if (!above(headEast, headNorth)) {
    return null;
  }
  final midEast = (headEast + tailEast) / 2;
  final midNorth = (headNorth + tailNorth) / 2;
  if (above(tailEast, tailNorth) && above(midEast, midNorth)) {
    return (east: tailEast, north: tailNorth);
  }
  var lo = 0.0;
  var hi = 1.0;
  for (var i = 0; i < 8; i++) {
    final mid = (lo + hi) / 2;
    final east = headEast + (tailEast - headEast) * mid;
    final north = headNorth + (tailNorth - headNorth) * mid;
    if (above(east, north)) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (
    east: headEast + (tailEast - headEast) * lo,
    north: headNorth + (tailNorth - headNorth) * lo,
  );
}

WindFlowStreak? windFlowStreak(WindFlowParticle particle, WindFlowField field) {
  final wind =
      field.sample(particle.eastNm, particle.northNm, particle.altitudeFt);
  final speed = wind.speedKt;
  if (speed < 0.5) {
    return null;
  }
  final length = windFlowLengthNm(speed);
  final life = particle.maxAgeSeconds <= 0
      ? 1.0
      : (particle.ageSeconds / particle.maxAgeSeconds).clamp(0.0, 1.0);
  return WindFlowStreak(
    headEast: particle.eastNm,
    headNorth: particle.northNm,
    tailEast: particle.eastNm - wind.eastKt / speed * length,
    tailNorth: particle.northNm - wind.northKt / speed * length,
    altitudeFt: particle.altitudeFt,
    speedKt: speed,
    alpha: math.sin(math.pi * life),
  );
}

void advanceWindFlow({
  required List<WindFlowParticle> particles,
  required WindFlowField field,
  required math.Random random,
  required double dtSeconds,
  required double radiusNm,
  required double maxAltitudeFt,
}) {
  final dt = dtSeconds.isFinite ? dtSeconds.clamp(0.0, 0.05) : 0.0;
  for (final particle in particles) {
    particle.ageSeconds += dt;
    final wind =
        field.sample(particle.eastNm, particle.northNm, particle.altitudeFt);
    final speed = wind.speedKt;
    final outside =
        particle.eastNm.abs() > radiusNm || particle.northNm.abs() > radiusNm;
    final expired = particle.ageSeconds >= particle.maxAgeSeconds;
    if (outside || expired) {
      resetWindParticle(particle, random, radiusNm, maxAltitudeFt);
      continue;
    }
    if (speed < 0.5) {
      continue;
    }
    final step = speed * windFlowVisualNmPerKnotSecond * dt;
    particle.eastNm += wind.eastKt / speed * step;
    particle.northNm += wind.northKt / speed * step;
    if (particle.eastNm.abs() > radiusNm || particle.northNm.abs() > radiusNm) {
      resetWindParticle(particle, random, radiusNm, maxAltitudeFt);
    }
  }
}

double _lerp(double a, double b, double t) => a + (b - a) * t;
