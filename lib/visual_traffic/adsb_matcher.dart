import 'dart:math';

import 'package:avaremp/visual_traffic/decisions.dart';
import 'package:avaremp/visual_traffic/detection_models.dart';

/// Where this aircraft is, from GPS.
class OwnshipFix {
  const OwnshipFix({
    required this.latitude,
    required this.longitude,
    required this.altitudeFt,
    required this.speedKnots,
    this.trackDegrees,
  });

  final double latitude;
  final double longitude;
  final double altitudeFt;
  final double speedKnots;

  /// Ground track, true degrees. Null when GPS has none.
  final double? trackDegrees;
}

/// Another aircraft, from an ADS-B report.
class AdsbTarget {
  const AdsbTarget({
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.altitudeFt,
    this.airborne = true,
  });

  /// Callsign or address, as shown to the pilot.
  final String label;
  final double latitude;
  final double longitude;
  final double altitudeFt;
  final bool airborne;
}

enum AdsbStatus {
  /// A box in the picture is where this aircraft should be.
  matched,

  /// Should be in the picture, but there is no box there.
  inView,

  /// Near enough to see, but outside the camera's field of view.
  outOfView,

  /// Behind the camera.
  behind,

  /// Too far for a phone camera to see.
  tooFar,

  /// On the ground.
  ground,

  /// Could not be placed, because the heading or the horizon is not known.
  unplaced,
}

class AdsbNote {
  const AdsbNote({
    required this.label,
    required this.status,
    required this.reason,
    required this.distanceNm,
    this.boxId,
    this.errorDegrees,
  });

  final String label;
  final AdsbStatus status;
  final String reason;
  final double distanceNm;

  /// The box this aircraft matched, when [status] is matched.
  final int? boxId;

  /// How far that box is from where the aircraft should be, in degrees.
  final double? errorDegrees;
}

class AdsbPicture {
  const AdsbPicture({
    required this.notes,
    required this.labels,
    this.problem,
    this.trafficCount = 0,
    this.promoted = const {},
    this.cues = const [],
  });

  static const AdsbPicture empty = AdsbPicture(notes: [], labels: {});

  /// One line for each ADS-B aircraft, nearest first.
  final List<AdsbNote> notes;

  /// Box id to the aircraft that matched it.
  final Map<int, String> labels;

  /// Why aircraft could not be placed in the picture, or null.
  final String? problem;

  /// ADS-B aircraft known, before any were thrown out.
  final int trafficCount;

  /// Yellow boxes that line up closely enough with an ADS-B aircraft to be
  /// treated as that aircraft, so shown red. Box id to the aircraft label.
  final Map<int, String> promoted;

  /// Places where ADS-B says an aircraft is but no tracked spot is, for the
  /// model to look at. Nearest first, at most [AdsbMatcher.maxCues].
  final List<Cue> cues;
}

/// Works out where each ADS-B aircraft should appear in the camera picture and
/// whether a box is there.
///
/// The camera is taken to point along the GPS ground track, turned by a
/// pilot-set offset. How far it looks above the horizon, and how it is
/// rolled, come from the horizon in the picture. In a crab or a skid the
/// real heading differs from the track, so the match is rough. It is meant
/// to answer "is that box a known aircraft", not to aim at one.
class AdsbMatcher {
  const AdsbMatcher({
    this.maxVisibleNm = 3,
    this.toleranceDegrees = 6,
    this.promoteDegrees = 3.5,
    this.minSpeedKnots = 20,
    this.wingspanMeters = 11,
    this.maxCues = 3,
  });

  /// A phone camera cannot find an airplane much farther than this.
  final double maxVisibleNm;

  /// How far, in degrees, a box may be from where an aircraft should be and
  /// still count as it.
  final double toleranceDegrees;

  /// A yellow box this close to an ADS-B aircraft is taken to be that
  /// aircraft and shown red.
  final double promoteDegrees;

  /// Most places the model is asked to look at once.
  final int maxCues;

  /// GPS track is not trusted below this speed.
  final double minSpeedKnots;

  /// Used to say how big an aircraft would look.
  final double wingspanMeters;

  static const double _metersPerNm = 1852;
  static const double _feetToMeters = 0.3048;

  AdsbPicture match({
    required OwnshipFix? ownship,
    required List<AdsbTarget> traffic,
    required List<DetectionBox> boxes,
    required double fovH,
    required double fovV,
    required int pictureWidth,
    required int pictureHeight,
    required HorizonReport horizon,
    double yawOffsetDegrees = 0,
  }) {
    if (ownship == null) {
      return AdsbPicture(
        notes: const [],
        labels: const {},
        problem: 'No GPS position, so ADS-B cannot be compared with the picture.',
        trafficCount: traffic.length,
      );
    }
    String? problem;
    final double? track = ownship.trackDegrees;
    final double? tilt = horizon.tiltDegrees;
    final double? pitch = horizon.pitchDegrees;
    if (track == null || ownship.speedKnots < minSpeedKnots) {
      problem = 'Speed ${ownship.speedKnots.round()} kt: GPS heading is not '
          'reliable below ${minSpeedKnots.round()} kt, so ADS-B cannot be '
          'placed in the picture.';
    } else if (tilt == null || pitch == null) {
      problem = 'No horizon in the picture or from the phone sensors, so the '
          'camera tilt is unknown and ADS-B cannot be placed.';
    }

    final double aspect = pictureWidth / pictureHeight;
    final List<AdsbNote> notes = [];
    final List<_Candidate> placed = [];
    for (final AdsbTarget target in traffic) {
      final double distanceM = _distanceMeters(
        ownship.latitude,
        ownship.longitude,
        target.latitude,
        target.longitude,
      );
      final double nm = distanceM / _metersPerNm;
      final String label = target.label;
      if (nm > maxVisibleNm) {
        notes.add(AdsbNote(
          label: label,
          status: AdsbStatus.tooFar,
          distanceNm: nm,
          reason: '${nm.toStringAsFixed(1)} nm away: too far for the camera '
              '(limit about ${maxVisibleNm.toStringAsFixed(0)} nm).',
        ));
        continue;
      }
      if (!target.airborne) {
        notes.add(AdsbNote(
          label: label,
          status: AdsbStatus.ground,
          distanceNm: nm,
          reason: '${nm.toStringAsFixed(1)} nm away, on the ground.',
        ));
        continue;
      }
      if (problem != null) {
        notes.add(AdsbNote(
          label: label,
          status: AdsbStatus.unplaced,
          distanceNm: nm,
          reason: '${nm.toStringAsFixed(1)} nm away, close enough to see, '
              'but it cannot be placed in the picture.',
        ));
        continue;
      }
      final double bearing = _bearing(
        ownship.latitude,
        ownship.longitude,
        target.latitude,
        target.longitude,
      );
      final double relative = _wrap180(bearing - (track! + yawOffsetDegrees));
      final double elevation = atan2(
            (target.altitudeFt - ownship.altitudeFt) * _feetToMeters,
            max(distanceM, 1),
          ) *
          180 /
          pi;
      if (relative.abs() >= 90) {
        notes.add(AdsbNote(
          label: label,
          status: AdsbStatus.behind,
          distanceNm: nm,
          reason: '${nm.toStringAsFixed(1)} nm away, ${relative.abs().round()}° '
              '${relative >= 0 ? "right" : "left"} of the camera: behind it.',
        ));
        continue;
      }
      final _Candidate c = _project(
        label: label,
        nm: nm,
        distanceM: distanceM,
        relative: relative,
        elevation: elevation,
        pitch: pitch!,
        tilt: tilt!,
        fovH: fovH,
        aspect: aspect,
      );
      if (c.u < -0.02 || c.u > 1.02 || c.v < -0.02 || c.v > 1.02) {
        final bool sideways = (relative.abs() / (fovH / 2)) >
            ((elevation - pitch).abs() / (fovV / 2));
        notes.add(AdsbNote(
          label: label,
          status: AdsbStatus.outOfView,
          distanceNm: nm,
          reason: sideways
              ? '${nm.toStringAsFixed(1)} nm away, ${relative.abs().round()}° '
                  '${relative >= 0 ? "right" : "left"} of the camera. The '
                  'camera sees ${(fovH / 2).round()}° each side.'
              : '${nm.toStringAsFixed(1)} nm away, '
                  '${(elevation - pitch).abs().round()}° '
                  '${elevation - pitch >= 0 ? "above" : "below"} the camera '
                  'center. The camera sees ${(fovV / 2).round()}° up and down.',
        ));
        continue;
      }
      placed.add(c);
    }

    // One box for one aircraft, closest pairs first.
    final List<_Pair> pairs = [];
    for (int i = 0; i < placed.length; i++) {
      for (int j = 0; j < boxes.length; j++) {
        final double dx = (placed[i].u - boxes[j].centerX) * fovH;
        final double dy = (placed[i].v - boxes[j].centerY) * fovV;
        final double d = sqrt(dx * dx + dy * dy);
        if (d <= toleranceDegrees) {
          pairs.add(_Pair(i, j, d));
        }
      }
    }
    pairs.sort((_Pair a, _Pair b) => a.distance.compareTo(b.distance));
    final Map<int, _Pair> taken = {};
    final Set<int> usedBoxes = {};
    for (final _Pair pair in pairs) {
      if (taken.containsKey(pair.target) || usedBoxes.contains(pair.box)) {
        continue;
      }
      taken[pair.target] = pair;
      usedBoxes.add(pair.box);
    }

    final Map<int, String> labels = {};
    final Map<int, String> promoted = {};
    final List<Cue> cues = [];
    for (int i = 0; i < placed.length; i++) {
      final _Candidate c = placed[i];
      final _Pair? pair = taken[i];
      final double widthDegrees =
          atan(wingspanMeters / max(c.distanceM, 1)) * 180 / pi;
      final double pixels = widthDegrees / fovH * pictureWidth;
      if (pair != null) {
        final DetectionBox box = boxes[pair.box];
        labels[box.id] = '${c.label} ${c.nm.toStringAsFixed(1)}nm';
        final bool fromCue = box.id < 0;
        if (box.tier == DetectionTier.possible && pair.distance <= promoteDegrees) {
          promoted[box.id] = c.label;
        }
        // A box that exists only because the model was asked to look here
        // needs the question asked again, or it would vanish.
        if (fromCue) {
          cues.add(Cue(
            key: c.label,
            u: c.u,
            v: c.v,
            expectedPixels: pixels,
            distanceNm: c.nm,
          ));
        }
        notes.add(AdsbNote(
          label: c.label,
          status: AdsbStatus.matched,
          distanceNm: c.nm,
          boxId: box.id,
          errorDegrees: pair.distance,
          reason: '${c.nm.toStringAsFixed(1)} nm away. Box ${targetName(box.id)} is '
              '${pair.distance.toStringAsFixed(1)}° from where it should be.',
        ));
      } else {
        cues.add(Cue(
          key: c.label,
          u: c.u,
          v: c.v,
          expectedPixels: pixels,
          distanceNm: c.nm,
        ));
        notes.add(AdsbNote(
          label: c.label,
          status: AdsbStatus.inView,
          distanceNm: c.nm,
          reason: '${c.nm.toStringAsFixed(1)} nm away and in the picture, but '
              'no box within ${toleranceDegrees.round()}°. A small airplane '
              'would be about ${pixels < 1 ? "under 1" : pixels.round()} px wide.',
        ));
      }
    }
    notes.sort((AdsbNote a, AdsbNote b) => a.distanceNm.compareTo(b.distanceNm));
    cues.sort((Cue a, Cue b) => a.distanceNm.compareTo(b.distanceNm));
    if (cues.length > maxCues) {
      cues.removeRange(maxCues, cues.length);
    }
    return AdsbPicture(
      notes: notes,
      labels: labels,
      problem: problem,
      trafficCount: traffic.length,
      promoted: promoted,
      cues: cues,
    );
  }

  /// Where an aircraft shows in the picture. [relative] is degrees right of
  /// the camera heading and [elevation] is degrees above the horizontal.
  _Candidate _project({
    required String label,
    required double nm,
    required double distanceM,
    required double relative,
    required double elevation,
    required double pitch,
    required double tilt,
    required double fovH,
    required double aspect,
  }) {
    final double scale = 2 * tan(fovH * pi / 360);
    final double x = tan(relative * pi / 180) / scale;
    final double y = -tan((elevation - pitch) * pi / 180) / scale;
    final double t = tilt * pi / 180;
    // The horizon is tilted in the picture, so everything turns with it.
    final double rx = x * cos(t) - y * sin(t);
    final double ry = x * sin(t) + y * cos(t);
    return _Candidate(
      label: label,
      nm: nm,
      distanceM: distanceM,
      u: 0.5 + rx,
      v: 0.5 + ry * aspect,
    );
  }

  static double _wrap180(double degrees) {
    double d = degrees % 360;
    if (d > 180) {
      d -= 360;
    }
    if (d <= -180) {
      d += 360;
    }
    return d;
  }

  static double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const double radius = 6371000;
    final double p1 = lat1 * pi / 180;
    final double p2 = lat2 * pi / 180;
    final double dp = (lat2 - lat1) * pi / 180;
    final double dl = (lon2 - lon1) * pi / 180;
    final double a = sin(dp / 2) * sin(dp / 2) +
        cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2);
    return 2 * radius * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _bearing(double lat1, double lon1, double lat2, double lon2) {
    final double p1 = lat1 * pi / 180;
    final double p2 = lat2 * pi / 180;
    final double dl = (lon2 - lon1) * pi / 180;
    final double y = sin(dl) * cos(p2);
    final double x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }
}

class _Candidate {
  const _Candidate({
    required this.label,
    required this.nm,
    required this.distanceM,
    required this.u,
    required this.v,
  });

  final String label;
  final double nm;
  final double distanceM;
  final double u;
  final double v;
}

class _Pair {
  const _Pair(this.target, this.box, this.distance);
  final int target;
  final int box;
  final double distance;
}
