import 'package:avaremp/visual_traffic/adsb_matcher.dart';
import 'package:avaremp/visual_traffic/decisions.dart';
import 'package:avaremp/visual_traffic/frame_analyzer.dart';
import 'package:avaremp/visual_traffic/gyro_motion.dart';

/// How a line in the Why window is colored.
enum Tone {
  /// A red box.
  alert,

  /// A yellow box.
  caution,

  /// Working as it should.
  good,

  /// Something that makes results less reliable.
  warn,

  /// Plain information.
  info,

  /// Thrown out or not applicable.
  muted,
}

class BoardLine {
  const BoardLine(this.text, this.tone);
  final String text;
  final Tone tone;
}

class BoardEvent {
  const BoardEvent(this.time, this.text, this.tone);
  final DateTime time;
  final String text;
  final Tone tone;
}

/// Builds the text of the Why window: what the sensors and model are doing,
/// what each target is and why, how ADS-B lines up, and a short history of
/// decisions that changed.
///
/// Pure Dart. The window just shows [sensors], [targets], [adsb] and
/// [events].
class DecisionBoard {
  DecisionBoard({this.maxEvents = 40, this.minEventGap = const Duration(seconds: 2)});

  final int maxEvents;

  /// The same thing is not logged twice inside this time, so a target on the
  /// edge of a limit does not flood the log.
  final Duration minEventGap;

  List<BoardLine> sensors = const [];
  List<BoardLine> targets = const [];
  List<BoardLine> adsb = const [];
  final List<BoardEvent> events = [];

  final Map<String, String> _lastState = {};
  final Map<String, Verdict> _lastVerdict = {};
  final Map<String, DateTime> _lastEventAt = {};
  final Map<String, String> _lastTargetName = {};

  /// Forgets the history, for a new camera session.
  void clear() {
    sensors = const [];
    targets = const [];
    adsb = const [];
    events.clear();
    _lastState.clear();
    _lastVerdict.clear();
    _lastEventAt.clear();
    _lastTargetName.clear();
  }

  /// [ownship] and [heading] are what the position and heading came to, and
  /// [gpsTrack] is the GPS track alone, so the window can show what the
  /// gyroscope added.
  void update({
    required AnalysisResult result,
    required AdsbPicture adsbPicture,
    OwnshipFix? ownship,
    double? heading,
    double? gpsTrack,
    DateTime? now,
  }) {
    final DateTime at = now ?? DateTime.now();
    final List<TargetNote> notes = _fuseNotes(result.notes, adsbPicture);
    sensors = _sensorLines(result, ownship, heading, gpsTrack);
    targets = _targetLines(notes, adsbPicture);
    adsb = _adsbLines(adsbPicture, result.cueResults);
    _logHorizon(result.horizonReport, at);
    _logGyro(result.gyroReport, at);
    _logTargets(notes, at);
    _logAdsb(adsbPicture, at);
  }

  /// Yellow targets that ADS-B has made red are reported as red, with the
  /// reason.
  List<TargetNote> _fuseNotes(List<TargetNote> notes, AdsbPicture picture) {
    if (picture.promoted.isEmpty) {
      return notes;
    }
    return notes.map((TargetNote n) {
      final String? label = picture.promoted[n.id];
      if (label == null || n.verdict != Verdict.yellow) {
        return n;
      }
      AdsbNote? match;
      for (final AdsbNote a in picture.notes) {
        if (a.boxId == n.id) {
          match = a;
        }
      }
      return TargetNote(
        id: n.id,
        x: n.x,
        y: n.y,
        verdict: Verdict.red,
        code: 'adsb',
        reason: 'A steady mover that lines up with ADS-B $label '
            '(${match?.distanceNm.toStringAsFixed(1) ?? "?"} nm, '
            '${match?.errorDegrees?.toStringAsFixed(1) ?? "?"}° off), so it is '
            'treated as that aircraft. The model has not confirmed it.',
      );
    }).toList();
  }

  // ---- live lines ----

  List<BoardLine> _sensorLines(
    AnalysisResult result,
    OwnshipFix? ownship,
    double? heading,
    double? gpsTrack,
  ) {
    final HorizonReport h = result.horizonReport;
    final List<BoardLine> lines = [];
    lines.add(_gpsLine(ownship, heading, gpsTrack));
    lines.add(_gyroLine(result.gyroReport));
    switch (h.source) {
      case HorizonSource.picture:
        if (h.sensorsDisagree) {
          lines.add(BoardLine(
            'Horizon from the picture. The phone sensors disagree '
            '(tilt ${_deg(h.sensorTiltDiff)}, pitch ${_deg(h.sensorPitchDiff)}), '
            'so they are ignored. This is normal in a turn or bumps.',
            Tone.warn,
          ));
        } else if (h.sensorTiltDiff != null) {
          lines.add(BoardLine(
            'Horizon from the picture. The phone sensors agree '
            '(tilt ${_deg(h.sensorTiltDiff)}, pitch ${_deg(h.sensorPitchDiff)}).',
            Tone.good,
          ));
        } else {
          lines.add(BoardLine(
            h.sensorsAvailable
                ? 'Horizon from the picture. The phone sensors point too far up or down to compare.'
                : 'Horizon from the picture. No sensor readings to compare.',
            Tone.info,
          ));
        }
      case HorizonSource.sensors:
        lines.add(const BoardLine(
          'No clear horizon in the picture (haze or cloud), so the phone '
          'sensors are used. They are wrong in a banked turn.',
          Tone.warn,
        ));
      case HorizonSource.none:
        lines.add(const BoardLine(
          'No horizon found, so sky and ground cannot be told apart.',
          Tone.warn,
        ));
    }
    final double? pitch = h.pitchDegrees;
    final double? tilt = h.tiltDegrees;
    if (pitch != null && tilt != null) {
      lines.add(BoardLine(
        'Camera looks ${pitch.abs().toStringAsFixed(0)}° '
        '${pitch >= 0 ? "above" : "below"} the horizon, horizon tilted '
        '${tilt.abs().toStringAsFixed(0)}°.',
        Tone.info,
      ));
    }
    lines.add(result.modelAvailable
        ? const BoardLine('Model: on. It checks steady movers.', Tone.good)
        : const BoardLine(
            'Model: off. Nothing can be confirmed, so no red boxes.',
            Tone.warn,
          ));
    if (result.cluttered) {
      lines.add(const BoardLine(
        'Busy sky: too many spots, so unconfirmed ones are held back.',
        Tone.warn,
      ));
    }
    return lines;
  }

  BoardLine _gpsLine(OwnshipFix? ownship, double? heading, double? gpsTrack) {
    if (ownship == null) {
      return const BoardLine(
        'Position: no GPS fix. ADS-B cannot be compared with the picture.',
        Tone.warn,
      );
    }
    final String speed = '${ownship.speedKnots.round()} kt, '
        '${ownship.altitudeFt.round()} ft';
    if (heading == null || ownship.speedKnots < 20) {
      return BoardLine(
        'Position: GPS fix, $speed. Heading is not trusted at this speed, so '
        'ADS-B is not placed in the picture.',
        Tone.warn,
      );
    }
    String added = '';
    if (gpsTrack != null) {
      double diff = (heading - gpsTrack + 540) % 360 - 180;
      if (diff.abs() >= 0.5) {
        added = ', ${diff >= 0 ? "+" : "-"}${diff.abs().toStringAsFixed(0)}° '
            'from the gyroscope since the last fix';
      }
    }
    return BoardLine(
      'Position: GPS fix, $speed. Heading ${heading.round()}° '
      '(GPS track${added.isEmpty ? "" : added}).',
      Tone.good,
    );
  }

  BoardLine _gyroLine(GyroReport g) {
    switch (g.state) {
      case GyroState.none:
        return const BoardLine(
          'Gyroscope: no readings, so the picture alone is used to follow the scene.',
          Tone.info,
        );
      case GyroState.learning:
        return const BoardLine(
          'Gyroscope: waiting for a turn or a bump to compare with the picture.',
          Tone.info,
        );
      case GyroState.agrees:
        final String corr = g.correlation == null
            ? ''
            : ' (match ${g.correlation!.toStringAsFixed(2)})';
        final String fill = g.filledIn
            ? ' The picture is too plain to measure the turn, so the gyroscope '
                'supplied the slide.'
            : '';
        return BoardLine('Gyroscope agrees with the picture$corr.$fill', Tone.good);
      case GyroState.mismatch:
        final String corr = g.correlation == null
            ? ''
            : ' (match ${g.correlation!.toStringAsFixed(2)})';
        return BoardLine(
          'Gyroscope does not match how the picture slid$corr, so it is not '
          'used to follow the scene.',
          Tone.warn,
        );
    }
  }

  List<BoardLine> _targetLines(List<TargetNote> notes, AdsbPicture adsbPicture) {
    if (notes.isEmpty) {
      return const [BoardLine('No targets being tracked.', Tone.muted)];
    }
    final List<BoardLine> lines = [];
    for (final TargetNote note in notes) {
      final String name = _verdictName(note.verdict);
      String text = '${targetName(note.id)} $name: ${note.reason}';
      if ((note.verdict == Verdict.red || note.verdict == Verdict.yellow) &&
          note.code != 'adsb' &&
          note.code != 'adsb-cue') {
        text += _adsbSuffix(note, adsbPicture);
      }
      lines.add(BoardLine(text, _toneFor(note.verdict)));
    }
    return lines;
  }

  String _adsbSuffix(TargetNote note, AdsbPicture picture) {
    final String? label = picture.labels[note.id];
    if (label != null) {
      return ' ADS-B: $label.';
    }
    if (picture.problem != null) {
      return '';
    }
    return ' No ADS-B aircraft is at that spot (no transponder, or out of ADS-B range).';
  }

  List<BoardLine> _adsbLines(AdsbPicture picture, List<CueResult> cueResults) {
    final List<BoardLine> lines = [];
    final String? problem = picture.problem;
    if (problem != null) {
      lines.add(BoardLine(problem, Tone.warn));
    }
    if (picture.trafficCount == 0 && problem == null) {
      lines.add(const BoardLine(
        'No ADS-B traffic received. Is the receiver connected and the traffic layer on?',
        Tone.muted,
      ));
    }
    for (final AdsbNote note in picture.notes) {
      String text = '${note.label}: ${note.reason}';
      CueResult? cue;
      for (final CueResult c in cueResults) {
        if (c.key == note.label) {
          cue = c;
        }
      }
      if (cue != null) {
        if (cue.airplane) {
          text += ' The model sees an airplane there.';
        } else if (cue.checks > 0) {
          text += ' The model looked there ${cue.checks} '
              '${cue.checks == 1 ? "time" : "times"}: best airplane score '
              '${cue.bestScore.toStringAsFixed(2)}, '
              '${FrameAnalyzer.skyAirplaneScore} needed.';
        } else {
          text += ' Waiting for the model to look there.';
        }
      }
      lines.add(BoardLine(text, _adsbTone(note.status)));
    }
    return lines;
  }

  Tone _adsbTone(AdsbStatus status) {
    switch (status) {
      case AdsbStatus.matched:
        return Tone.good;
      case AdsbStatus.inView:
      case AdsbStatus.unplaced:
        return Tone.warn;
      case AdsbStatus.outOfView:
      case AdsbStatus.behind:
      case AdsbStatus.tooFar:
      case AdsbStatus.ground:
        return Tone.muted;
    }
  }

  Tone _toneFor(Verdict verdict) {
    switch (verdict) {
      case Verdict.red:
        return Tone.alert;
      case Verdict.yellow:
        return Tone.caution;
      case Verdict.watching:
        return Tone.info;
      case Verdict.rejected:
        return Tone.muted;
    }
  }

  String _verdictName(Verdict verdict) {
    switch (verdict) {
      case Verdict.red:
        return 'RED';
      case Verdict.yellow:
        return 'yellow';
      case Verdict.watching:
        return 'watching';
      case Verdict.rejected:
        return 'rejected';
    }
  }

  String _deg(double? value) => value == null ? '?' : '${value.toStringAsFixed(0)}°';

  // ---- history ----

  bool _due(String key, DateTime at) {
    final DateTime? last = _lastEventAt[key];
    if (last != null && at.difference(last) < minEventGap) {
      return false;
    }
    _lastEventAt[key] = at;
    return true;
  }

  void _add(DateTime at, String text, Tone tone) {
    events.add(BoardEvent(at, text, tone));
    if (events.length > maxEvents) {
      events.removeRange(0, events.length - maxEvents);
    }
  }

  void _logHorizon(HorizonReport h, DateTime at) {
    final String state = '${h.source.name}/${h.sensorsDisagree}';
    final String? before = _lastState['horizon'];
    _lastState['horizon'] = state;
    if (before == null || before == state || !_due('horizon', at)) {
      if (before == null) {
        _lastEventAt['horizon'] = at;
      }
      return;
    }
    switch (h.source) {
      case HorizonSource.picture:
        _add(
          at,
          h.sensorsDisagree
              ? 'Horizon from the picture. Phone sensors disagree, ignored.'
              : 'Horizon from the picture. Sensors agree.',
          h.sensorsDisagree ? Tone.warn : Tone.good,
        );
      case HorizonSource.sensors:
        _add(at, 'Lost the horizon in the picture. Using phone sensors.', Tone.warn);
      case HorizonSource.none:
        _add(at, 'Lost the horizon. No sensor fallback.', Tone.warn);
    }
  }

  void _logGyro(GyroReport g, DateTime at) {
    final String state = g.state.name;
    final String? before = _lastState['gyro'];
    _lastState['gyro'] = state;
    if (before == null || before == state) {
      return;
    }
    // Learning and none are starting states, not news.
    if (g.state != GyroState.agrees && g.state != GyroState.mismatch) {
      return;
    }
    if (!_due('gyro', at)) {
      return;
    }
    _add(
      at,
      g.state == GyroState.agrees
          ? 'Gyroscope now agrees with the picture.'
          : 'Gyroscope no longer matches the picture. Not used.',
      g.state == GyroState.agrees ? Tone.good : Tone.warn,
    );
  }

  void _logTargets(List<TargetNote> notes, DateTime at) {
    final Set<String> seen = {};
    for (final TargetNote note in notes) {
      final String key = targetName(note.id);
      seen.add(key);
      final String state = '${note.verdict.name}/${note.code}';
      final String? before = _lastState[key];
      final Verdict? beforeVerdict = _lastVerdict[key];
      _lastState[key] = state;
      _lastVerdict[key] = note.verdict;
      _lastTargetName[key] = _verdictName(note.verdict);
      if (before == state) {
        continue;
      }
      // A target that is only being watched is not news.
      final bool news = note.verdict != Verdict.watching ||
          beforeVerdict == Verdict.red ||
          beforeVerdict == Verdict.yellow;
      if (!news || !_due(key, at)) {
        continue;
      }
      final String from = beforeVerdict == null || beforeVerdict == Verdict.watching
          ? ''
          : '${_verdictName(beforeVerdict)} to ';
      _add(
        at,
        '$key $from${_verdictName(note.verdict)}: ${note.reason}',
        _toneFor(note.verdict),
      );
    }
    // Boxes that were up and have gone.
    final List<String> gone = _lastState.keys
        .where((String k) =>
            (k.startsWith('T') || k.startsWith('A')) &&
            !k.startsWith('A:') &&
            !seen.contains(k))
        .toList();
    for (final String key in gone) {
      final Verdict? v = _lastVerdict[key];
      if ((v == Verdict.red || v == Verdict.yellow) && _due('gone-$key', at)) {
        _add(at, '$key lost: no longer seen (was ${_lastTargetName[key]}).', Tone.muted);
      }
      _lastState.remove(key);
      _lastVerdict.remove(key);
      _lastTargetName.remove(key);
    }
  }

  void _logAdsb(AdsbPicture picture, DateTime at) {
    final Set<String> seen = {};
    for (final AdsbNote note in picture.notes) {
      final String key = 'A:${note.label}';
      seen.add(key);
      final String state = note.status.name;
      final String? before = _lastState[key];
      _lastState[key] = state;
      if (before == state) {
        continue;
      }
      final bool quiet = before == null &&
          (note.status == AdsbStatus.tooFar ||
              note.status == AdsbStatus.behind ||
              note.status == AdsbStatus.ground ||
              note.status == AdsbStatus.outOfView);
      if (quiet || !_due(key, at)) {
        continue;
      }
      _add(at, 'ADS-B ${note.label}: ${note.reason}', _adsbTone(note.status));
    }
    final List<String> gone = _lastState.keys
        .where((String k) => k.startsWith('A:') && !seen.contains(k))
        .toList();
    for (final String key in gone) {
      _lastState.remove(key);
    }
  }
}
