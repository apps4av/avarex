/// What the detector decided about one target, and why. Shown in the
/// "Why" window so a pilot can see how a box was chosen or thrown out.
enum Verdict {
  /// Boxed red: the model called it an airplane.
  red,

  /// Boxed yellow: a steady mover the model has not confirmed.
  yellow,

  /// Not shown yet. Still being watched.
  watching,

  /// Looked at and thrown out.
  rejected,
}

class TargetNote {
  const TargetNote({
    required this.id,
    required this.x,
    required this.y,
    required this.verdict,
    required this.code,
    required this.reason,
  });

  /// Same id as the box, when there is one.
  final int id;

  /// Middle of the target as a fraction of the picture.
  final double x;
  final double y;

  final Verdict verdict;

  /// Short stable name for the reason, such as `glass` or `below`. A change
  /// of verdict or code is a new decision. A change in the numbers inside
  /// [reason] is not.
  final String code;

  /// The reason in words, with the numbers behind it.
  final String reason;
}

/// Where the horizon came from.
enum HorizonSource {
  /// Found as a line in the picture.
  picture,

  /// Worked out from the phone's tilt sensors.
  sensors,

  /// Not known.
  none,
}

/// The horizon the detector used, and how it compares with the phone's
/// sensors.
class HorizonReport {
  const HorizonReport({
    required this.source,
    this.tiltDegrees,
    this.pitchDegrees,
    this.sensorsAvailable = false,
    this.sensorTiltDiff,
    this.sensorPitchDiff,
  });

  static const HorizonReport unknown = HorizonReport(source: HorizonSource.none);

  /// The sensors and the picture may differ by this much, in degrees, before
  /// they are called a mismatch. Turns and bumps push the sensors around.
  static const double disagreeDegrees = 4;

  final HorizonSource source;

  /// Slope of the horizon in the picture, positive when it runs down to the
  /// right. Null when there is no horizon.
  final double? tiltDegrees;

  /// Degrees the camera looks above the horizon, negative below. Null when
  /// there is no horizon or the picture is upside down.
  final double? pitchDegrees;

  /// True when tilt sensor readings were available this frame.
  final bool sensorsAvailable;

  /// Absolute gap between the picture's horizon and the sensors', in
  /// degrees. Null unless both exist.
  final double? sensorTiltDiff;
  final double? sensorPitchDiff;

  bool get sensorsDisagree =>
      (sensorTiltDiff ?? 0) > disagreeDegrees ||
      (sensorPitchDiff ?? 0) > disagreeDegrees;
}

/// A box id for something the model found where ADS-B said an aircraft was,
/// with no tracked spot behind it, is negative. Shown as `A1`, `A2`, and so
/// on. Tracked targets are `T1`, `T2`, and so on.
String targetName(int id) => id < 0 ? 'A${-id}' : 'T$id';

/// A place in the picture where ADS-B says an aircraft should be, so the
/// model is asked to look there even though nothing was seen moving.
class Cue {
  const Cue({
    required this.key,
    required this.u,
    required this.v,
    required this.expectedPixels,
    required this.distanceNm,
  });

  /// The aircraft's callsign or address. Same cue, same key, frame to frame.
  final String key;

  /// Where it should be, as fractions of the picture.
  final double u;
  final double v;

  /// How wide it should look, in picture pixels.
  final double expectedPixels;

  final double distanceNm;
}

/// What happened when the model looked at a [Cue].
class CueResult {
  const CueResult({
    required this.key,
    required this.checks,
    required this.bestScore,
    required this.airplane,
    this.boxId,
  });

  final String key;

  /// Times the model has looked at this spot.
  final int checks;

  /// Highest airplane score it gave, even one too low to count.
  final double bestScore;

  /// True while the model sees an airplane near the cue.
  final bool airplane;

  /// The negative box id made for it, when [airplane] is true.
  final int? boxId;
}
