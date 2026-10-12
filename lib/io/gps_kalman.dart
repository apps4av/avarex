import 'dart:math';

import 'package:geolocator/geolocator.dart';

/// Constant-velocity Kalman filter for ownship from internal GPS, ADS-B, and NMEA.
///
/// States: north, east, altitude, vn, ve, vertical rate, heading.
/// After the last fix the filter coasts for [predictLimit] (the same window
/// as the "No GPS lock" warning), then freezes. Heading is held when speed
/// is below [restSpeedMs] so the aircraft does not snap north while parked.
class GpsKalman {
  /// Twice the Auto GPS switchover (external → internal), matching
  /// `Storage.gpsSwitchoverTimeMs * 2` used for the no-lock warning.
  static const Duration predictLimit = Duration(milliseconds: 2 * 30000);
  static const double restSpeedMs = 1.5;

  static const int _nState = 7;
  static const int _iN = 0;
  static const int _iE = 1;
  static const int _iAlt = 2;
  static const int _iVn = 3;
  static const int _iVe = 4;
  static const int _iVz = 5;
  static const int _iHdg = 6;

  static const double _mPerDegLat = 111320.0;

  bool _initialized = false;
  DateTime? _lastMeasurementTime;
  DateTime? _lastRawTimestamp;
  DateTime? _lastPredictTime;
  Position? _lastMeasurement;
  Position? _frozen;

  double _lat0 = 0;
  double _lon0 = 0;
  double _mPerDegLon = _mPerDegLat;

  final List<double> _x = List<double>.filled(_nState, 0);
  late _Mat _p;

  bool get initialized => _initialized;

  /// True while coasting on the last fix, before [predictLimit] expires.
  bool get coasting {
    if (!_initialized || _lastMeasurementTime == null) {
      return false;
    }
    final Duration age = DateTime.now().difference(_lastMeasurementTime!);
    return age > Duration.zero && age <= predictLimit;
  }

  void reset() {
    _initialized = false;
    _lastMeasurementTime = null;
    _lastRawTimestamp = null;
    _lastPredictTime = null;
    _lastMeasurement = null;
    _frozen = null;
    _x.fillRange(0, _nState, 0);
  }

  /// Filter one raw sample. A repeated [Position] (same timestamp) only
  /// predicts, so ADS-B, NMEA, and device GPS can all share this entry point.
  Position apply(Position raw, {DateTime? now}) {
    final DateTime t = now ?? DateTime.now();
    if (!_initialized ||
        _lastRawTimestamp == null ||
        raw.timestamp != _lastRawTimestamp) {
      update(raw);
      _lastRawTimestamp = raw.timestamp;
    }
    return output(raw, now: t);
  }

  void update(Position measurement) {
    if (_invalidFix(measurement)) {
      return;
    }
    final DateTime t = measurement.timestamp;
    if (!_initialized ||
        _lastMeasurementTime == null ||
        t.difference(_lastMeasurementTime!) > predictLimit) {
      _init(measurement);
      return;
    }
    _predictTo(t);
    _correct(measurement);
    _lastMeasurementTime = t;
    _lastPredictTime = t;
    _lastMeasurement = measurement;
    _frozen = null;
  }

  Position output(Position raw, {DateTime? now}) {
    if (!_initialized) {
      return raw;
    }
    _predictTo(now ?? DateTime.now());
    return _toPosition(raw, now ?? DateTime.now());
  }

  static bool _invalidFix(Position p) {
    if (!p.latitude.isFinite || !p.longitude.isFinite) {
      return true;
    }
    if (p.latitude.abs() < 1e-8 && p.longitude.abs() < 1e-8) {
      return true;
    }
    return false;
  }

  void _init(Position p) {
    _lat0 = p.latitude;
    _lon0 = p.longitude;
    _mPerDegLon = _lonMetersPerDegree(_lat0);
    _x[_iN] = 0;
    _x[_iE] = 0;
    _x[_iAlt] = p.altitude;
    final double hdg = _headingRad(p.heading);
    final double speed = max(0, p.speed);
    _x[_iVn] = speed * cos(hdg);
    _x[_iVe] = speed * sin(hdg);
    _x[_iVz] = 0;
    _x[_iHdg] = hdg;
    _p = _Mat.diagonal(_nState, const <double>[100, 100, 100, 25, 25, 25, 0.1]);
    _initialized = true;
    _lastMeasurementTime = p.timestamp;
    _lastPredictTime = p.timestamp;
    _lastMeasurement = p;
    _frozen = null;
  }

  void _predictTo(DateTime now) {
    if (_lastMeasurementTime == null) {
      return;
    }
    final DateTime coastEnd = _lastMeasurementTime!.add(predictLimit);
    final DateTime target = now.isAfter(coastEnd) ? coastEnd : now;
    final DateTime from = _lastPredictTime ?? _lastMeasurementTime!;
    if (!target.isAfter(from)) {
      return;
    }
    double dt = target.difference(from).inMicroseconds / 1e6;
    if (dt <= 0) {
      return;
    }
    _predict(dt);
    _lastPredictTime = target;
    if (now.isAfter(coastEnd)) {
      _frozen ??= _toPosition(_lastMeasurement ?? _zeroPosition(now), coastEnd);
    }
  }

  void _predict(double dt) {
    final _Mat f = _Mat.identity(_nState);
    f.set(_iN, _iVn, dt);
    f.set(_iE, _iVe, dt);
    f.set(_iAlt, _iVz, dt);

    final List<double> xn = List<double>.filled(_nState, 0);
    for (int i = 0; i < _nState; i++) {
      double s = 0;
      for (int j = 0; j < _nState; j++) {
        s += f.get(i, j) * _x[j];
      }
      xn[i] = s;
    }
    _x.setAll(0, xn);
    _x[_iHdg] = _wrapTwoPi(_x[_iHdg]);

    final bool rest = _speed < restSpeedMs;
    final double qAcc = rest ? 0.05 : 2.0;
    final double qVert = rest ? 0.05 : 1.0;
    final double qHdg = rest ? 1e-6 : 0.02;
    final _Mat q = _Mat(_nState, _nState);
    _fillCvNoise(q, _iN, _iVn, dt, qAcc);
    _fillCvNoise(q, _iE, _iVe, dt, qAcc);
    _fillCvNoise(q, _iAlt, _iVz, dt, qVert);
    q.set(_iHdg, _iHdg, qHdg * dt);

    _p = f.times(_p).times(f.transposed()).plus(q);
    _reanchorIfNeeded();
  }

  void _correct(Position p) {
    _reanchorIfNeeded();
    final double n = (p.latitude - _lat0) * _mPerDegLat;
    final double e = (p.longitude - _lon0) * _mPerDegLon;
    // Device/ADS-B/NMEA heading is not valid when the receiver reports rest.
    final bool rest = p.speed < restSpeedMs;
    final double hdgZ = rest ? _x[_iHdg] : _headingRad(p.heading);
    final double vnZ = rest ? 0 : p.speed * cos(hdgZ);
    final double veZ = rest ? 0 : p.speed * sin(hdgZ);

    // z = [n, e, alt, vn, ve, heading]
    const int m = 6;
    final List<double> z = <double>[n, e, p.altitude, vnZ, veZ, hdgZ];
    final _Mat h = _Mat(m, _nState);
    h.set(0, _iN, 1);
    h.set(1, _iE, 1);
    h.set(2, _iAlt, 1);
    h.set(3, _iVn, 1);
    h.set(4, _iVe, 1);
    h.set(5, _iHdg, 1);

    final List<double> y = List<double>.filled(m, 0);
    for (int i = 0; i < m; i++) {
      double hx = 0;
      for (int j = 0; j < _nState; j++) {
        hx += h.get(i, j) * _x[j];
      }
      y[i] = z[i] - hx;
    }
    y[5] = _wrapPi(y[5]);

    final List<double> rDiag = <double>[
      36, 36, 64, 1, 1, rest ? 1e6 : 0.0027,
    ];
    final _Mat r = _Mat.diagonal(m, rDiag);
    final _Mat s = h.times(_p).times(h.transposed()).plus(r);
    final _Mat sInv = s.inverted();
    if (sInv.rows == 0) {
      return;
    }
    final _Mat k = _p.times(h.transposed()).times(sInv);

    for (int i = 0; i < _nState; i++) {
      double add = 0;
      for (int j = 0; j < m; j++) {
        add += k.get(i, j) * y[j];
      }
      _x[i] += add;
    }
    _x[_iHdg] = _wrapTwoPi(_x[_iHdg]);
    if (rest) {
      _x[_iVn] = 0;
      _x[_iVe] = 0;
    }

    final _Mat iKh = _Mat.identity(_nState).minus(k.times(h));
    _p = iKh.times(_p).times(iKh.transposed()).plus(k.times(r).times(k.transposed()));
  }

  Position _toPosition(Position raw, DateTime timestamp) {
    if (_frozen != null &&
        _lastMeasurementTime != null &&
        timestamp.difference(_lastMeasurementTime!) > predictLimit) {
      return _copyStamp(_frozen!, timestamp);
    }
    final double lat = (_lat0 + _x[_iN] / _mPerDegLat).clamp(-90.0, 90.0);
    double lon = _lon0 + _x[_iE] / _mPerDegLon;
    lon = ((lon + 180) % 360 + 360) % 360 - 180;
    return Position(
      latitude: lat,
      longitude: lon,
      timestamp: timestamp,
      accuracy: raw.accuracy,
      altitude: _x[_iAlt],
      altitudeAccuracy: raw.altitudeAccuracy,
      heading: _headingDeg(_x[_iHdg]),
      headingAccuracy: raw.headingAccuracy,
      speed: _speed,
      speedAccuracy: raw.speedAccuracy,
    );
  }

  double get _speed {
    final double s = sqrt(_x[_iVn] * _x[_iVn] + _x[_iVe] * _x[_iVe]);
    return s.isFinite ? s : 0;
  }

  void _reanchorIfNeeded() {
    if (sqrt(_x[_iN] * _x[_iN] + _x[_iE] * _x[_iE]) < 50000) {
      return;
    }
    final double lat = _lat0 + _x[_iN] / _mPerDegLat;
    final double lon = _lon0 + _x[_iE] / _mPerDegLon;
    _lat0 = lat;
    _lon0 = lon;
    _mPerDegLon = _lonMetersPerDegree(_lat0);
    _x[_iN] = 0;
    _x[_iE] = 0;
  }

  static double _lonMetersPerDegree(double latDeg) {
    final double c = cos(latDeg * pi / 180.0).abs();
    return _mPerDegLat * max(c, 0.01);
  }

  static double _headingRad(double deg) {
    if (!deg.isFinite) {
      return 0;
    }
    return _wrapTwoPi(deg * pi / 180.0);
  }

  static double _headingDeg(double rad) {
    double deg = _wrapTwoPi(rad) * 180.0 / pi;
    if (deg >= 360) {
      deg = 0;
    }
    return deg;
  }

  static double _wrapTwoPi(double a) {
    double x = a % (2 * pi);
    if (x < 0) {
      x += 2 * pi;
    }
    return x;
  }

  static double _wrapPi(double a) {
    double x = a;
    while (x > pi) {
      x -= 2 * pi;
    }
    while (x < -pi) {
      x += 2 * pi;
    }
    return x;
  }

  static void _fillCvNoise(_Mat q, int iPos, int iVel, double dt, double qa) {
    final double dt2 = dt * dt;
    final double dt3 = dt2 * dt;
    q.set(iPos, iPos, qa * dt3 / 3);
    q.set(iPos, iVel, qa * dt2 / 2);
    q.set(iVel, iPos, qa * dt2 / 2);
    q.set(iVel, iVel, qa * dt);
  }

  static Position _copyStamp(Position p, DateTime timestamp) {
    return Position(
      latitude: p.latitude,
      longitude: p.longitude,
      timestamp: timestamp,
      accuracy: p.accuracy,
      altitude: p.altitude,
      altitudeAccuracy: p.altitudeAccuracy,
      heading: p.heading,
      headingAccuracy: p.headingAccuracy,
      speed: p.speed,
      speedAccuracy: p.speedAccuracy,
    );
  }

  static Position _zeroPosition(DateTime timestamp) {
    return Position(
      latitude: 0,
      longitude: 0,
      timestamp: timestamp,
      accuracy: 0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

class _Mat {
  final int rows;
  final int cols;
  final List<double> a;

  _Mat(this.rows, this.cols) : a = List<double>.filled(rows * cols, 0);

  factory _Mat.identity(int n) {
    final _Mat m = _Mat(n, n);
    for (int i = 0; i < n; i++) {
      m.set(i, i, 1);
    }
    return m;
  }

  factory _Mat.diagonal(int n, List<double> d) {
    final _Mat m = _Mat(n, n);
    for (int i = 0; i < n && i < d.length; i++) {
      m.set(i, i, d[i]);
    }
    return m;
  }

  double get(int r, int c) => a[r * cols + c];

  void set(int r, int c, double v) => a[r * cols + c] = v;

  _Mat transposed() {
    final _Mat t = _Mat(cols, rows);
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        t.set(c, r, get(r, c));
      }
    }
    return t;
  }

  _Mat times(_Mat o) {
    final _Mat r = _Mat(rows, o.cols);
    for (int i = 0; i < rows; i++) {
      for (int k = 0; k < cols; k++) {
        final double aik = get(i, k);
        if (aik == 0) {
          continue;
        }
        for (int j = 0; j < o.cols; j++) {
          r.set(i, j, r.get(i, j) + aik * o.get(k, j));
        }
      }
    }
    return r;
  }

  _Mat plus(_Mat o) {
    final _Mat r = _Mat(rows, cols);
    for (int i = 0; i < a.length; i++) {
      r.a[i] = a[i] + o.a[i];
    }
    return r;
  }

  _Mat minus(_Mat o) {
    final _Mat r = _Mat(rows, cols);
    for (int i = 0; i < a.length; i++) {
      r.a[i] = a[i] - o.a[i];
    }
    return r;
  }

  /// Gauss-Jordan inverse. Empty matrix on failure.
  _Mat inverted() {
    if (rows != cols) {
      return _Mat(0, 0);
    }
    final int n = rows;
    final _Mat aug = _Mat(n, 2 * n);
    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        aug.set(i, j, get(i, j));
      }
      aug.set(i, n + i, 1);
    }
    for (int col = 0; col < n; col++) {
      int pivot = col;
      double best = aug.get(pivot, col).abs();
      for (int r = col + 1; r < n; r++) {
        final double v = aug.get(r, col).abs();
        if (v > best) {
          best = v;
          pivot = r;
        }
      }
      if (best < 1e-12) {
        return _Mat(0, 0);
      }
      if (pivot != col) {
        for (int c = 0; c < 2 * n; c++) {
          final double tmp = aug.get(col, c);
          aug.set(col, c, aug.get(pivot, c));
          aug.set(pivot, c, tmp);
        }
      }
      final double div = aug.get(col, col);
      for (int c = 0; c < 2 * n; c++) {
        aug.set(col, c, aug.get(col, c) / div);
      }
      for (int r = 0; r < n; r++) {
        if (r == col) {
          continue;
        }
        final double f = aug.get(r, col);
        if (f == 0) {
          continue;
        }
        for (int c = 0; c < 2 * n; c++) {
          aug.set(r, c, aug.get(r, c) - f * aug.get(col, c));
        }
      }
    }
    final _Mat inv = _Mat(n, n);
    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        inv.set(i, j, aug.get(i, n + j));
      }
    }
    return inv;
  }
}
