import 'dart:math';

import 'package:avaremp/visual_traffic/frame_analyzer.dart';
import 'package:avaremp/visual_traffic/gyro_motion.dart';

/// A direction or a rotation rate, in some set of axes.
class Vec3 {
  const Vec3(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
}

/// Turns a phone sensor reading into camera axes.
///
/// Phone axes: x across the screen to the right, y toward the top of the
/// screen, z out of the screen. Camera axes: x to the right of the upright
/// picture, y toward its bottom, z out through the lens (the back camera
/// looks out of the back of the phone, so z flips).
///
/// [deviceDegrees] is how far the phone is turned from upright portrait, as
/// the camera plugin reports it: 0 portrait, 90 landscape with the top of the
/// phone to the left, 180 upside down, 270 landscape with the top to the
/// right. The same mapping is right for a direction and for a rotation rate.
Vec3 deviceToCamera(int deviceDegrees, double x, double y, double z) {
  switch (((deviceDegrees % 360) + 360) % 360) {
    case 90:
      return Vec3(-y, -x, -z);
    case 180:
      return Vec3(-x, y, -z);
    case 270:
      return Vec3(y, x, -z);
    default:
      return Vec3(x, -y, -z);
  }
}

/// Keeps track of which way is down, and which way the aircraft is heading,
/// by combining the phone's gyroscope, its accelerometer, the horizon seen in
/// the picture, and GPS.
///
/// - The gyroscope moves the estimate smoothly, and is what carries it through
///   a turn or bump. It drifts slowly.
/// - The horizon in the picture, when there is one, pulls the estimate back
///   quickly. It is the most trustworthy.
/// - The accelerometer pulls it back very slowly, and only when the phone is
///   not being pushed around. In a banked turn the accelerometer points the
///   wrong way, so it is ignored there.
/// - GPS gives the heading once a second. The gyroscope carries it between
///   fixes.
///
/// All directions are in camera axes (see [deviceToCamera]).
class AttitudeFilter {
  AttitudeFilter({
    this.accelTimeConstant = 60,
    this.pictureWeight = 0.25,
    this.gravityBand = 0.03,
  });

  /// Seconds the accelerometer takes to pull the estimate most of the way.
  final double accelTimeConstant;

  /// How much of the gap to the picture's horizon is closed each time the
  /// picture is applied.
  final double pictureWeight;

  /// The accelerometer is used only when its size is within this fraction of
  /// gravity. A banked turn pulls more than that.
  final double gravityBand;

  static const double _g = 9.80665;

  double _gx = 0, _gy = 1, _gz = 0;
  bool _has = false;
  int? _lastGyroMs;
  int? _lastAccelMs;

  // Rotation since the last frame was sent for analysis, camera axes, radians.
  double _rx = 0, _ry = 0, _rz = 0;

  // Heading carried from the last GPS fix.
  double? _fixTrack;
  Object? _fixKey;
  double _yawSinceFix = 0;

  bool get hasAttitude => _has;

  /// Which way is down, in camera axes. Null before anything is known.
  GravityHint? get gravity => _has ? GravityHint(_gx, _gy, _gz) : null;

  /// How far the camera has turned since the last [takeRotation], in radians
  /// about the camera axes.
  MotionHint get rotation => MotionHint(_rx, _ry, _rz);

  /// Returns the rotation since the last call and starts counting again.
  MotionHint takeRotation() {
    final MotionHint out = MotionHint(_rx, _ry, _rz);
    _rx = _ry = _rz = 0;
    return out;
  }

  /// Forgets the rotation counted so far without using it.
  void clearRotation() {
    _rx = _ry = _rz = 0;
  }

  void reset() {
    _has = false;
    _lastGyroMs = null;
    _lastAccelMs = null;
    _rx = _ry = _rz = 0;
    _fixTrack = null;
    _fixKey = null;
    _yawSinceFix = 0;
  }

  /// A gyroscope reading, [w] in radians a second about the camera axes.
  void onGyro(Vec3 w, int timestampMs) {
    final int? last = _lastGyroMs;
    _lastGyroMs = timestampMs;
    if (last == null) {
      return;
    }
    final double dt = (timestampMs - last) / 1000;
    if (dt <= 0 || dt > 0.5) {
      return;
    }
    _rx += w.x * dt;
    _ry += w.y * dt;
    _rz += w.z * dt;
    if (!_has) {
      return;
    }
    // A fixed direction, seen from a turning body, turns the other way.
    final double nx = _gx - (w.y * _gz - w.z * _gy) * dt;
    final double ny = _gy - (w.z * _gx - w.x * _gz) * dt;
    final double nz = _gz - (w.x * _gy - w.y * _gx) * dt;
    _setDown(nx, ny, nz);
    // Turning about the down axis is turning right, a heading change.
    _yawSinceFix += (w.x * _gx + w.y * _gy + w.z * _gz) * dt * 180 / pi;
  }

  /// An accelerometer reading, [a] in meters a second squared in camera axes.
  /// It points away from the ground, the push of the floor.
  void onAccel(Vec3 a, int timestampMs) {
    final double size = sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
    if (size < 1e-6) {
      return;
    }
    final double dx = -a.x / size;
    final double dy = -a.y / size;
    final double dz = -a.z / size;
    if (!_has) {
      _setDown(dx, dy, dz);
      _has = true;
      _lastAccelMs = timestampMs;
      return;
    }
    final int? last = _lastAccelMs;
    _lastAccelMs = timestampMs;
    if (last == null) {
      return;
    }
    if ((size - _g).abs() > _g * gravityBand) {
      return;
    }
    final double dt = ((timestampMs - last) / 1000).clamp(0.0, 0.5);
    final double w = (dt / accelTimeConstant).clamp(0.0, 1.0);
    _setDown(_gx + (dx - _gx) * w, _gy + (dy - _gy) * w, _gz + (dz - _gz) * w);
  }

  /// The horizon as the picture shows it: [tiltDegrees] positive when it runs
  /// down to the right, [pitchDegrees] positive when the camera looks above
  /// it.
  void onPicture(double tiltDegrees, double pitchDegrees) {
    final double t = tiltDegrees * pi / 180;
    final double p = pitchDegrees * pi / 180;
    final double dx = -sin(t) * cos(p);
    final double dy = cos(t) * cos(p);
    final double dz = -sin(p);
    if (!_has) {
      _setDown(dx, dy, dz);
      _has = true;
      return;
    }
    _setDown(
      _gx + (dx - _gx) * pictureWeight,
      _gy + (dy - _gy) * pictureWeight,
      _gz + (dz - _gz) * pictureWeight,
    );
  }

  /// Tilt and pitch of the horizon the estimate says, the same way
  /// [onPicture] takes them. Null before anything is known.
  ({double tilt, double pitch})? get horizon {
    if (!_has) {
      return null;
    }
    // Inverse of onPicture.
    final double pitch = asin((-_gz).clamp(-1.0, 1.0));
    final double c = cos(pitch);
    if (c.abs() < 1e-6) {
      return null;
    }
    final double tilt = atan2(-_gx / c, _gy / c);
    return (tilt: tilt * 180 / pi, pitch: pitch * 180 / pi);
  }

  /// Tells the filter about the latest GPS ground track. [fixKey] changes
  /// whenever there is a new fix (for example the latitude and longitude).
  void onGps(double? trackDegrees, Object fixKey) {
    if (trackDegrees == null) {
      _fixTrack = null;
      _fixKey = fixKey;
      return;
    }
    if (_fixKey != fixKey || _fixTrack == null) {
      _fixKey = fixKey;
      _fixTrack = trackDegrees;
      _yawSinceFix = 0;
    }
  }

  /// The heading right now: the last GPS track plus what the gyroscope has
  /// turned since. Null when GPS has no track.
  double? get heading {
    final double? track = _fixTrack;
    if (track == null) {
      return null;
    }
    // After a long gap the gyroscope's drift could be larger than its help.
    return (track + _yawSinceFix + 720) % 360;
  }

  /// Degrees the gyroscope has turned the heading since the last GPS fix.
  double get yawSinceFix => _yawSinceFix;

  void _setDown(double x, double y, double z) {
    final double n = sqrt(x * x + y * y + z * z);
    if (n < 1e-9) {
      return;
    }
    _gx = x / n;
    _gy = y / n;
    _gz = z / n;
  }
}
