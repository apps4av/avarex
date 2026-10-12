import 'dart:math';

import 'package:latlong2/latlong.dart';

/// FAA holding-pattern entry (AIM 5-3-8).
enum HoldEntry {
  direct,
  parallel,
  teardrop;

  String get label {
    switch (this) {
      case HoldEntry.direct:
        return "Direct";
      case HoldEntry.parallel:
        return "Parallel";
      case HoldEntry.teardrop:
        return "Teardrop";
    }
  }
}

/// One holding pattern to draw on the map. Courses are magnetic.
class HoldPattern {
  final LatLng fix;
  final double inboundMagnetic;
  final bool rightTurns;

  /// Straight-leg length in nautical miles.
  final double legNm;
  final double speedKt;
  final String name;

  const HoldPattern({
    required this.fix,
    required this.inboundMagnetic,
    required this.rightTurns,
    required this.legNm,
    required this.speedKt,
    required this.name,
  });
}

/// Arrow sitting on the hold, pointing along [trueCourse].
class HoldArrow {
  final LatLng at;
  final double trueCourse;

  const HoldArrow({required this.at, required this.trueCourse});
}

class HoldShape {
  final List<LatLng> pattern;
  final List<LatLng> entry;
  final HoldEntry entryType;

  /// Holding fix, where the entry begins.
  final LatLng entryPoint;

  /// One arrow on each turn, in the direction of flight.
  final List<HoldArrow> turnArrows;

  /// Arrows along the orange entry, in the direction of flight.
  final List<HoldArrow> entryArrows;

  const HoldShape({
    required this.pattern,
    required this.entry,
    required this.entryType,
    required this.entryPoint,
    required this.turnArrows,
    required this.entryArrows,
  });
}

const double _earthNm = 3440.065;

/// Standard-rate (3°/s) turn radius in nautical miles.
double holdRadiusNm(double speedKt) => speedKt / (60 * pi);

/// Straight-leg length for a timed hold.
double holdLegNm(double speedKt, double minutes) => speedKt * minutes / 60;

const double _msToKt = 1.943844;

/// Ground speed used to size the racetrack. Below 60 kt (parked or taxi)
/// a hold has no useful size, so use a light-aircraft 90 kt.
double holdSpeedKt(double groundSpeedKt) {
  if (!groundSpeedKt.isFinite || groundSpeedKt < 60) {
    return 90;
  }
  return groundSpeedKt.roundToDouble();
}

double holdSpeedFromMs(double metersPerSecond) =>
    holdSpeedKt(metersPerSecond * _msToKt);

bool holdUsingAssumedSpeed(double metersPerSecond) {
  final double kt = metersPerSecond * _msToKt;
  return !kt.isFinite || kt < 60;
}

double _norm(double deg) {
  final double m = deg % 360;
  return m < 0 ? m + 360 : m;
}

double _angleDelta(double from, double to) {
  return (_norm(to - from) + 180) % 360 - 180;
}

/// Entry for an aircraft flying [courseToFix] (magnetic) toward the fix.
///
/// Right turns, measured clockwise from the inbound course: direct through
/// 110°, teardrop from there to 180°, parallel from 180° to 290°, then
/// direct again. The 110° and 290° boundaries are direct; 180° is parallel.
/// Left turns mirror that about the inbound course.
HoldEntry holdEntry({
  required double inboundMagnetic,
  required double courseToFix,
  required bool rightTurns,
}) {
  double rel = _norm(courseToFix - inboundMagnetic);
  if (!rightTurns) {
    rel = _norm(-rel);
  }
  if (rel > 110 && rel < 180) {
    return HoldEntry.teardrop;
  }
  if (rel >= 180 && rel < 290) {
    return HoldEntry.parallel;
  }
  return HoldEntry.direct;
}

LatLng _offset(LatLng from, double distanceNm, double bearingDeg) {
  final double d = distanceNm / _earthNm;
  final double br = bearingDeg * pi / 180;
  final double lat1 = from.latitude * pi / 180;
  final double lon1 = from.longitude * pi / 180;
  final double lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(br));
  final double lon2 = lon1 +
      atan2(sin(br) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2));
  return LatLng(lat2 * 180 / pi, _norm(lon2 * 180 / pi + 180) - 180);
}

double holdBearing(LatLng from, LatLng to) {
  final double lat1 = from.latitude * pi / 180;
  final double lat2 = to.latitude * pi / 180;
  final double dLon = (to.longitude - from.longitude) * pi / 180;
  final double y = sin(dLon) * cos(lat2);
  final double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
  return _norm(atan2(y, x) * 180 / pi);
}

double holdDistanceNm(LatLng a, LatLng b) {
  final double lat1 = a.latitude * pi / 180;
  final double lat2 = b.latitude * pi / 180;
  final double dLat = lat2 - lat1;
  final double dLon = (b.longitude - a.longitude) * pi / 180;
  final double h = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
  return 2 * _earthNm * asin(min(1.0, sqrt(h)));
}

/// Turn [sweepDeg] from [headingDeg] at standard rate. Right increases heading.
List<LatLng> _arc({
  required LatLng start,
  required double headingDeg,
  required double sweepDeg,
  required bool right,
  required double radiusNm,
  double stepDeg = 10,
}) {
  final double sign = right ? 1.0 : -1.0;
  final LatLng center = _offset(start, radiusNm, _norm(headingDeg + 90 * sign));
  final List<LatLng> pts = [start];
  double swept = 0;
  while (swept + 0.01 < sweepDeg) {
    final double step = min(stepDeg, sweepDeg - swept);
    swept += step;
    final double h = _norm(headingDeg + swept * sign);
    pts.add(_offset(center, radiusNm, _norm(h - 90 * sign)));
  }
  return pts;
}

/// Continue the turn until the heading points at [fix], then straight in.
List<LatLng> _turnToFix({
  required LatLng start,
  required LatLng fix,
  required double headingDeg,
  required bool right,
  required double radiusNm,
  required double minSweepDeg,
}) {
  const double stepDeg = 8;
  final double sign = right ? 1.0 : -1.0;
  final LatLng center = _offset(start, radiusNm, _norm(headingDeg + 90 * sign));
  final List<LatLng> pts = [start];
  double swept = 0;
  while (swept < 340) {
    swept += stepDeg;
    final double h = _norm(headingDeg + swept * sign);
    final LatLng cur = _offset(center, radiusNm, _norm(h - 90 * sign));
    pts.add(cur);
    if (swept + 0.1 >= minSweepDeg &&
        _angleDelta(h, holdBearing(cur, fix)).abs() <= stepDeg) {
      break;
    }
  }
  pts.add(fix);
  return pts;
}

HoldShape buildHoldShape({
  required HoldPattern hold,
  required LatLng aircraft,
  required double variation,
}) {
  final double speed = hold.speedKt >= 60 ? hold.speedKt : 90;
  final double radius = holdRadiusNm(speed);
  final double leg = hold.legNm < 1 ? 1 : hold.legNm;
  final bool right = hold.rightTurns;
  final double sign = right ? 1.0 : -1.0;
  final double inbound = _norm(hold.inboundMagnetic + variation);
  final double outbound = _norm(inbound + 180);

  final List<LatLng> outTurn = _arc(
    start: hold.fix,
    headingDeg: inbound,
    sweepDeg: 180,
    right: right,
    radiusNm: radius,
  );
  final LatLng outEnd = _offset(outTurn.last, leg, outbound);
  final List<LatLng> inTurn = _arc(
    start: outEnd,
    headingDeg: outbound,
    sweepDeg: 180,
    right: right,
    radiusNm: radius,
  );
  final List<LatLng> pattern = [...outTurn, outEnd, ...inTurn, hold.fix];

  final bool atFix = holdDistanceNm(aircraft, hold.fix) < 0.2;
  final double courseMag = atFix
      ? hold.inboundMagnetic
      : _norm(holdBearing(aircraft, hold.fix) - variation);
  final HoldEntry entryType = atFix
      ? HoldEntry.direct
      : holdEntry(
          inboundMagnetic: hold.inboundMagnetic,
          courseToFix: courseMag,
          rightTurns: right,
        );

  // Entry maneuver only. The course from the aircraft to the fix is not drawn.
  final List<LatLng> entry = [];
  if (entryType != HoldEntry.direct) {
    final double legHeading = entryType == HoldEntry.teardrop
        ? _norm(outbound - 30 * sign)
        : outbound;
    // A 30° teardrop for the whole NM leg crosses the outbound leg: the
    // racetrack is only two standard-rate radii wide. Stop where the return
    // turn still stays inside that leg. Parallel stays on the non-holding side.
    final double teardropLimit = radius * (2 + sqrt(3));
    final double entryLeg =
        entryType == HoldEntry.teardrop ? min(leg, teardropLimit) : leg;
    final LatLng legEnd = _offset(hold.fix, entryLeg, legHeading);
    entry.add(hold.fix);
    entry.addAll(_turnToFix(
      start: legEnd,
      fix: hold.fix,
      headingDeg: legHeading,
      right: right,
      radiusNm: radius,
      minSweepDeg: entryType == HoldEntry.parallel ? 150 : 60,
    ));
  }

  return HoldShape(
    pattern: pattern,
    entry: entry,
    entryType: entryType,
    entryPoint: hold.fix,
    turnArrows: [
      _turnArrow(hold.fix, inbound, right, radius, 90),
      _turnArrow(outEnd, outbound, right, radius, 90),
    ],
    entryArrows: _arrowsAlong(entry),
  );
}

/// Direction-of-flight marks along [path], skipping the endpoints.
List<HoldArrow> _arrowsAlong(List<LatLng> path) {
  if (path.length < 2) {
    return [];
  }
  final List<double> cum = [0];
  for (int i = 1; i < path.length; i++) {
    cum.add(cum.last + holdDistanceNm(path[i - 1], path[i]));
  }
  final double total = cum.last;
  if (total < 0.4) {
    return [];
  }
  final List<double> marks = total < 1.5
      ? [total * 0.5]
      : [total * 0.22, total * 0.5, total * 0.78];
  final List<HoldArrow> arrows = [];
  for (final double dist in marks) {
    int i = 1;
    while (i < cum.length - 1 && cum[i] < dist) {
      i++;
    }
    final double span = cum[i] - cum[i - 1];
    final double t = span <= 0 ? 0 : ((dist - cum[i - 1]) / span).clamp(0.0, 1.0);
    final LatLng from = path[i - 1];
    final double course = holdBearing(from, path[i]);
    arrows.add(HoldArrow(
      at: span <= 0.01 ? from : _offset(from, span * t, course),
      trueCourse: course,
    ));
  }
  return arrows;
}

/// Point and heading [sweepDeg] into a standard-rate turn.
HoldArrow _turnArrow(
  LatLng start,
  double headingDeg,
  bool right,
  double radiusNm,
  double sweepDeg,
) {
  final double sign = right ? 1.0 : -1.0;
  final double h = _norm(headingDeg + sweepDeg * sign);
  final LatLng center = _offset(start, radiusNm, _norm(headingDeg + 90 * sign));
  return HoldArrow(
    at: _offset(center, radiusNm, _norm(h - 90 * sign)),
    trueCourse: h,
  );
}
