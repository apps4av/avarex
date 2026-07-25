import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/instruments/flight_status.dart';
import 'package:avaremp/io/gps.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Geometry for one physical runway (both ends) at the closest airport.
class _RunwayGeom {
  final String leIdent;
  final String heIdent;
  final LatLng le;
  final LatLng he;
  final double lengthFt;
  final double widthFt;
  final double leHeadingTrue;
  final double heHeadingTrue;

  const _RunwayGeom({
    required this.leIdent,
    required this.heIdent,
    required this.le,
    required this.he,
    required this.lengthFt,
    required this.widthFt,
    required this.leHeadingTrue,
    required this.heHeadingTrue,
  });
}

class _TrackSample {
  final DateTime at;
  final LatLng position;

  const _TrackSample({required this.at, required this.position});
}

/// Audible runway-crossing awareness.
///
/// Watches ownship against the runways of the **closest airport** and
/// announces when the ground track is about to meet a runway centerline.
/// Gated by [Storage.settings.isAudibleAlertsEnabled], same as GPWS and
/// traffic.
class RunwayAwareness {
  static RunwayAwareness? _instance;

  static const double _crossTrackBufferFt = 75;
  static const double _alignHeadingDeg = 25;
  static const Duration _historyWindow = Duration(seconds: 45);
  static const Duration _airportRefresh = Duration(seconds: 15);

  /// Time-to-centerline window for taxi / hold-short crossing alerts.
  /// ~15 s at 6 kt ≈ 150 ft — roughly hold-short, not half a taxiway away.
  static const double _crossingLookaheadSec = 15;

  /// Do not call "approaching runway" until within this cross-track distance.
  static const double _crossingMaxCrossFt = 250;

  /// Beyond runway ends (ft) still treated as the LE–HE segment for entry.
  static const double _crossingAlongPadFt = 150;

  /// At or above this speed while aligned on a runway is a takeoff / landing
  /// roll, not a crossing.
  static const double _runwayRollSpeedKt = 15;
  static const double _crossingMinSpeedKt = 3;

  final AssetSource _crossingAudio = AssetSource('approaching_runway.mp3');

  final AudioPlayer _audioPlayer = AudioPlayer();
  static AudioCache? _cache;

  final Queue<_TrackSample> _history = Queue<_TrackSample>();
  final Completer<RunwayAwareness> _startupCompleter = Completer();

  bool _isRunning = false;
  bool _isPlaying = false;
  bool _isUpdating = false;

  String? _airportId;
  AirportDestination? _airport;
  List<_RunwayGeom> _runways = const [];
  DateTime? _airportLoadedAt;

  /// Crossing keys already announced; cleared when the runway is no longer an
  /// imminent crossing so a later entry announces once again.
  final Set<String> _announced = {};

  /// Runway currently being crossed (for UI / debugging), else null.
  String? lastCrossingRunway;

  RunwayAwareness._();

  static Future<RunwayAwareness?> getAndStart() async {
    if (_instance == null) {
      _instance = RunwayAwareness._();
      await _instance!._loadAudio();
      _instance!._isRunning = true;
      _instance!._startupCompleter.complete(_instance);
    }
    return _instance!._startupCompleter.future;
  }

  static Future<void> stop() async {
    if (_instance == null) return;
    _instance!._isRunning = false;
    _instance!._isPlaying = false;
    await _instance!._audioPlayer.stop();
    _instance = null;
  }

  Future<void> _loadAudio() async {
    _cache ??= AudioCache(prefix: 'assets/audio/runway_incursion/');
    _audioPlayer.audioCache = _cache!;
    _audioPlayer.setReleaseMode(ReleaseMode.stop);
    try {
      await _cache!.loadAll([_crossingAudio.path]);
    } catch (_) {
      // Missing clip is non-fatal; play() will no-op via catchError.
    }
  }

  /// Periodic entry point (e.g. from [Area.updateRunwayAwareness]).
  Future<void> update({
    required Position position,
    required Destination? closestAirport,
  }) async {
    if (!_isRunning) return;
    if (_isUpdating) return;
    _isUpdating = true;
    final List<String> toAnnounce = [];
    try {
      _recordSample(position);

      final double speedKt = GeoCalculations.convertSpeed(position.speed);
      // Taxi phase from FlightStatus (speed hysteresis around 20 kt) — not
      // GPS altitude / Storage.airborne.
      final bool onGround =
          Storage().flightStatus.phase == FlightStatus.phaseTaxi;
      await _ensureClosestAirport(closestAirport);

      if (_airport == null || _runways.isEmpty) {
        lastCrossingRunway = null;
        return;
      }

      if (!onGround) {
        lastCrossingRunway = null;
        _announced.clear();
        return;
      }

      final LatLng here = Gps.toLatLng(position);
      final double heading = position.heading;

      final List<_RunwayGeom> crossings = _crossingRunways(
        here: here,
        heading: heading,
        speedKt: speedKt,
      );

      lastCrossingRunway =
          crossings.isEmpty ? null : crossings.map((r) => r.leIdent).join(',');

      final Set<String> activeKeys = {
        for (final rw in crossings) 'x|$_airportId|${rw.leIdent}',
      };
      // Drop latches for runways we are no longer approaching so a later
      // entry can announce again; keep latches for still-active ones.
      _announced.removeWhere((k) => !activeKeys.contains(k));

      if (!Storage().settings.isAudibleAlertsEnabled()) return;

      for (final rw in crossings) {
        final key = 'x|$_airportId|${rw.leIdent}';
        if (!_announced.contains(key)) {
          _announced.add(key); // latch before play so a concurrent tick skips
          toAnnounce.add(key);
        }
      }
    } finally {
      _isUpdating = false;
    }

    // Play outside the update lock so 1 Hz samples keep flowing during audio.
    for (final key in toAnnounce) {
      await _announce(key);
    }
  }

  // -------------------- Crossing detection --------------------

  void _recordSample(Position position) {
    final now = DateTime.now();
    _history.add(_TrackSample(at: now, position: Gps.toLatLng(position)));
    while (_history.isNotEmpty &&
        now.difference(_history.first.at) > _historyWindow) {
      _history.removeFirst();
    }
  }

  /// Every runway whose centerline the ownship is about to meet.
  /// Caller already verified [FlightStatus.phaseTaxi].
  List<_RunwayGeom> _crossingRunways({
    required LatLng here,
    required double heading,
    required double speedKt,
  }) {
    if (speedKt < _crossingMinSpeedKt) return const [];
    // Rolling aligned on a runway is a takeoff / landing, not a crossing —
    // otherwise an intersecting runway would announce during the roll.
    if (_onRunwayOperation(here, heading, speedKt)) return const [];

    final List<_RunwayGeom> out = [];
    for (final rw in _runways) {
      if (_imminentCenterlineCrossing(
        here: here,
        heading: heading,
        speedKt: speedKt,
        rw: rw,
      )) {
        out.add(rw);
      }
    }
    return out;
  }

  /// On a runway, aligned with it, at takeoff/landing-roll speed.
  bool _onRunwayOperation(LatLng here, double heading, double speedKt) {
    if (speedKt < _runwayRollSpeedKt) return false;
    for (final rw in _runways) {
      if (!_pointInCorridor(here, rw)) continue;
      if (_headingAligned(heading, rw.leHeadingTrue) ||
          _headingAligned(heading, rw.heHeadingTrue)) {
        return true;
      }
    }
    return false;
  }

  /// True when the ownship track will meet the LE–HE centerline soon.
  ///
  /// Geometry: runway = segment [LE, HE]. Position expressed as
  /// (alongFt, crossFt) in that frame. Cross-track rate is
  /// `speed * sin(heading − runwayBearing)`. Time-to-line = |cross| / |ẋ|.
  /// Alert if TTL ≤ [_crossingLookaheadSec] and the contact point lies on the
  /// segment (with a small pad past each threshold).
  bool _imminentCenterlineCrossing({
    required LatLng here,
    required double heading,
    required double speedKt,
    required _RunwayGeom rw,
  }) {
    // Parallel to the runway — taxiing alongside is not a crossing.
    if (_headingAligned(heading, rw.leHeadingTrue) ||
        _headingAligned(heading, rw.heHeadingTrue)) {
      return false;
    }

    final (alongFt, crossFt) = _runwayFrame(here, rw);
    final double runwayBearing =
        GeoCalculations().calculateBearing(rw.le, rw.he);
    final double rel = _smallestSignedAngle(heading - runwayBearing);
    final double speedFps = speedKt * 1.68781; // kt → ft/s
    final double crossRateFps = speedFps * sin(rel * pi / 180.0);
    final double alongRateFps = speedFps * cos(rel * pi / 180.0);

    // Already on / straddling the centerline while not runway-aligned.
    if (crossFt.abs() <= rw.widthFt / 2 + _crossTrackBufferFt &&
        alongFt >= -_crossingAlongPadFt &&
        alongFt <= rw.lengthFt + _crossingAlongPadFt) {
      return true;
    }

    // Too far laterally — wait until near hold-short.
    if (crossFt.abs() > _crossingMaxCrossFt) return false;

    // Same sign means moving away or parallel in cross-track. Still accept a
    // recent path that already met the line (a completed through-crossing).
    if (crossFt == 0 || crossFt * crossRateFps >= 0) {
      return _recentPathMeetsCenterline(rw);
    }

    final double ttlSec = crossFt.abs() / crossRateFps.abs();
    if (ttlSec > _crossingLookaheadSec) return false;

    final double contactAlong = alongFt + alongRateFps * ttlSec;
    return contactAlong >= -_crossingAlongPadFt &&
        contactAlong <= rw.lengthFt + _crossingAlongPadFt;
  }

  /// True if a recent track segment met the LE–HE centerline (cross or touch).
  bool _recentPathMeetsCenterline(_RunwayGeom rw) {
    if (_history.length < 2) return false;
    final samples = _history.toList();
    final start = max(1, samples.length - 8);
    for (int i = start; i < samples.length; i++) {
      if (_segmentMeetsCenterline(
          samples[i - 1].position, samples[i].position, rw)) {
        return true;
      }
    }
    return false;
  }

  // -------------------- Airport / runway geometry --------------------

  Future<void> _ensureClosestAirport(Destination? closest) async {
    final String? id = closest?.locationID;
    final now = DateTime.now();
    final bool stale = _airportLoadedAt == null ||
        now.difference(_airportLoadedAt!) > _airportRefresh;
    if (id == null || id.isEmpty) {
      _airportId = null;
      _airport = null;
      _runways = const [];
      return;
    }
    if (id == _airportId && !stale && _runways.isNotEmpty) return;

    final AirportDestination? ap = await MainDatabaseHelper.db.findAirport(id);
    _airportId = id;
    _airport = ap;
    _airportLoadedAt = now;
    _runways = ap == null ? const [] : _parseRunways(ap);
  }

  List<_RunwayGeom> _parseRunways(AirportDestination ap) {
    final List<_RunwayGeom> out = [];
    final geo = GeoCalculations();
    for (final r in ap.runways) {
      try {
        final String leIdent = (r['LEIdent'] as String?)?.trim() ?? '';
        final String heIdent = (r['HEIdent'] as String?)?.trim() ?? '';
        // Need both ends — helipads / stubs (e.g. KORD H1) lack HE coords.
        // Falling back to the ARP used to draw a phantom centerline through
        // the terminal and false-alarm "approaching runway" on the ramp.
        if (leIdent.isEmpty || heIdent.isEmpty) continue;

        final double leLat = double.parse(r['LELatitude'].toString());
        final double leLon = double.parse(r['LELongitude'].toString());
        final double heLat = double.parse(r['HELatitude'].toString());
        final double heLon = double.parse(r['HELongitude'].toString());
        final LatLng le = LatLng(leLat, leLon);
        final LatLng he = LatLng(heLat, heLon);
        // Degenerate ends (same point / tiny stub).
        if (_metersBetween(le, he) < 100) continue;

        double lengthFt;
        try {
          lengthFt = double.parse(r['Length'].toString());
        } catch (_) {
          lengthFt = 0;
        }
        if (lengthFt <= 0) {
          lengthFt = _metersBetween(le, he) * 3.28084;
        }

        double widthFt;
        try {
          widthFt = double.parse(r['Width'].toString());
        } catch (_) {
          widthFt = 75;
        }

        double leHdg;
        try {
          leHdg = double.parse(r['LEHeadingT'].toString());
        } catch (_) {
          leHdg = geo.calculateBearing(le, he);
        }

        out.add(_RunwayGeom(
          leIdent: leIdent,
          heIdent: heIdent,
          le: le,
          he: he,
          lengthFt: lengthFt,
          widthFt: widthFt,
          leHeadingTrue: leHdg,
          heHeadingTrue: (leHdg + 180) % 360,
        ));
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  // -------------------- Geometry helpers --------------------

  static final Distance _haversine = const Distance(calculator: Haversine());

  static double _metersBetween(LatLng a, LatLng b) =>
      _haversine.as(LengthUnit.Meter, a, b);

  bool _headingAligned(double heading, double runwayHdg) =>
      _smallestAngle(heading, runwayHdg) <= _alignHeadingDeg;

  double _smallestAngle(double a, double b) {
    var d = (a - b).abs() % 360;
    if (d > 180) d = 360 - d;
    return d;
  }

  double _smallestSignedAngle(double deg) {
    var d = deg % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  /// Along-track feet from LE toward HE; cross-track feet left-positive.
  (double alongFt, double crossFt) _runwayFrame(LatLng p, _RunwayGeom rw) {
    final double lenM = max(1.0, _metersBetween(rw.le, rw.he));
    final double brg = GeoCalculations().calculateBearing(rw.le, rw.he);
    final double distM = _metersBetween(rw.le, p);
    final double brgP = GeoCalculations().calculateBearing(rw.le, p);
    final double ang = _smallestSignedAngle(brgP - brg) * pi / 180.0;
    final double alongM = distM * cos(ang);
    final double crossM = distM * sin(ang);
    // Scale along to published length when ends are slightly off.
    final double scale = rw.lengthFt / (lenM * 3.28084);
    return (alongM * 3.28084 * scale, crossM * 3.28084);
  }

  bool _pointInCorridor(LatLng p, _RunwayGeom rw) {
    final (along, cross) = _runwayFrame(p, rw);
    final half = rw.widthFt / 2 + _crossTrackBufferFt;
    if (cross.abs() > half) return false;
    return along >= -_crossTrackBufferFt &&
        along <= rw.lengthFt + _crossTrackBufferFt;
  }

  /// Track segment meets LE→HE centerline: proper cross *or* arrival onto it.
  bool _segmentMeetsCenterline(LatLng a, LatLng b, _RunwayGeom rw) {
    final (alongA, crossA) = _runwayFrame(a, rw);
    final (alongB, crossB) = _runwayFrame(b, rw);
    final double minAlong = -_crossingAlongPadFt;
    final double maxAlong = rw.lengthFt + _crossingAlongPadFt;

    // Either endpoint already on the line within the runway segment.
    if (crossA.abs() < 1.0 && alongA >= minAlong && alongA <= maxAlong) {
      return true;
    }
    if (crossB.abs() < 1.0 && alongB >= minAlong && alongB <= maxAlong) {
      return true;
    }

    // Cross-track sign change ⇒ segment straddles the centerline.
    if (crossA == 0 || crossB == 0 || crossA * crossB > 0) return false;
    final double t = crossA.abs() / (crossA.abs() + crossB.abs());
    final double alongHit = alongA + (alongB - alongA) * t;
    return alongHit >= minAlong && alongHit <= maxAlong;
  }

  // -------------------- Audio --------------------

  /// Play one callout. Caller latches [key] in [_announced] before invoking.
  Future<void> _announce(String key) async {
    // Wait out an in-progress clip so multi-runway crossings each get audio.
    while (_isPlaying) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!_isRunning) return;
    }
    _isPlaying = true;
    try {
      await _audioPlayer.play(_crossingAudio);
      await _audioPlayer.onPlayerComplete.first
          .timeout(const Duration(seconds: 8), onTimeout: () {});
    } catch (_) {
      // ignore missing asset / playback errors
    } finally {
      _isPlaying = false;
    }
  }
}
