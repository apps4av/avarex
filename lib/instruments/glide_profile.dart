import 'dart:math' as math;
import 'package:avaremp/aircraft/aircraft.dart';
import 'package:avaremp/aircraft/aircraft_performance.dart';
import 'package:avaremp/place/elevation_cache.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:avaremp/io/gps.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/winds_aloft.dart';
import 'package:latlong2/latlong.dart';

class GlideProfile {
  // Members that get set at object construction
  final List<double?> _distanceTotal;

  static const int _directionSteps = 30;
  static const double _feetPerNm = 6076.12;
  static const double _feetPerMeter = 3.28084;
  static const int _stepSizeDirection = (360 ~/ _directionSteps);

  GlideProfile() : _distanceTotal = List<double?>.filled(_directionSteps, null);

  LatLng getGlidePoint() {
    double? distance = _distanceTotal[0];
    LatLng ret = Gps.toLatLng(Storage().position);
    if(distance == null) {
      return ret; // no distance for this direction
    }
    return GeoCalculations().calculateOffset(ret, distance, 0 * _stepSizeDirection.toDouble());
  }

  List<LatLng> getGlideCircle() {
    GeoCalculations geoCalc = GeoCalculations();
    LatLng currentLocation = Gps.toLatLng(Storage().position);
    List<LatLng> points = [];
    for(int index = 0; index < _distanceTotal.length; index++) {
      final distance = _distanceTotal[index];
      if(distance == null) {
        continue; // no distance for this direction
      }
      LatLng point = geoCalc.calculateOffset(currentLocation, distance, index * _stepSizeDirection.toDouble());
      points.add(point);
    }
    if(points.isEmpty) {
      points.add(currentLocation); // for safety return current location if no points
    }
    points.add(points[0]); // close the circle
    return points;
  }

  void updateGlide() async {
    try {
    final List<double?> next = List<double?>.filled(_directionSteps, null);
    void publish() {
      for (int i = 0; i < _directionSteps; i++) {
        _distanceTotal[i] = next[i];
      }
      // area.update notifies before this async work finishes. Notify again
      // once the ring is actually ready so the map and 3D view redraw it.
      Storage().area.change.value++;
    }

    // units in feet and seconds
    double altitudeGps = Storage().position.altitude * _feetPerMeter; // feet
    double heading = Storage().position.heading; // track true north
    LatLng ll = Gps.toLatLng(Storage().position);

    // The aircraft chosen in the Aircraft & Performance dropdown.
    final SelectedAircraft selected = await Aircraft.resolveSelected();
    final Aircraft? aircraft = selected.saved;
    final AircraftPerformanceData? builtIn = selected.builtIn;
    if (aircraft == null && builtIn == null) {
      publish();
      return; // no aircraft, cannot compute glide
    }
    double sinkFpm = double.tryParse(aircraft?.sinkRate ?? '') ?? 0;
    if (sinkFpm <= 0) {
      sinkFpm = builtIn?.sinkRateFpm ?? 0;
    }
    if (sinkFpm <= 0) {
      sinkFpm = 100; // feet per minute when neither the profile nor a built-in table has one
    }
    final double sinkRate = sinkFpm / 60.0; // feet per second
    // Best glide of the active airplane in app speed units (not GPS ground speed).
    final double bestGlideSpeed = glideSpeedAppUnits(selected) * Storage().units.toMps * _feetPerMeter;

    WindsAloft? wa = Storage().area.windsAloft;
    // Missing winds still glide, with the wind taken as calm.
    double wSpeed = 0;
    double wAngle = 0;
    if(wa != null) {
      final (double? angle, double? speed) = wa.getWindAtAltitude(altitudeGps);
      if(angle != null && speed != null) {
        wAngle = angle;
        wSpeed = speed;
      }
    }

    // convert wind speed to feet per second from knots
    wSpeed = (wSpeed * _feetPerNm) / 3600.0;

    (double, double) t = WindTriangle.getTrueFromGroundAndWind(heading, bestGlideSpeed, wAngle, wSpeed);
    final double asT = t.$2; // true airspeed in feet per second

    // calculate winds from current altitude to ground.
    for (int dir = 0; dir < _directionSteps; dir++) {
      final double targetAngle = dir * _stepSizeDirection.toDouble();
      next[dir] = await _findDistanceTo(ll, heading, targetAngle, sinkRate, altitudeGps, asT, wa);
      // now we know how far we can glide in each direction
    }
    publish();
    } catch (_) {}
  }

  /// Best-glide speed in the app's speed units. A saved Best Glide Speed wins.
  /// Otherwise the selected built-in aircraft supplies its POH speed.
  static double glideSpeedAppUnits(SelectedAircraft selected) {
    final Aircraft? aircraft = selected.saved;
    final AircraftPerformanceData? builtIn = selected.builtIn;
    final double? saved = double.tryParse(aircraft?.bestGlide ?? '');
    if (saved != null && saved > 0) {
      return saved;
    }
    if (builtIn != null && builtIn.bestGlideKt > 0) {
      final double factor = Storage().units.knotsTo == 0 ? 1 : Storage().units.knotsTo;
      return builtIn.bestGlideKt * factor;
    }
    if (aircraft != null) {
      return aircraft.bestGlideSpeed;
    }
    return 65.0;
  }

  /// Shortest angular distance between two headings in degrees in range [0, 180].
  static double _angularDistance(double alpha, double beta) {
    final double phi = (beta - alpha).abs() % 360;
    final double distance = phi > 180 ? 360 - phi : phi;
    return distance;
  }

  /// Find distance covered when gliding from `heading` to `bearingAt` given sink rate,
  /// altitudes, airspeed (as), and winds aloft.
  ///
  /// Returns miles (as in original code).
  static Future<double?> _findDistanceTo(LatLng currentPosition, double heading, double bearingAt, double sinkRate, double altitudeGps, double asT, WindsAloft? wa) async {
    double distance = 0.0;
    // correct altitude based on direction as turn loses altitude, assume 1 second per 3 degrees, and shortest dir turn
    final double turnAngle = _angularDistance(heading, bearingAt);
    final double altLost = turnAngle / 3.0 * sinkRate;
    double altitude = altitudeGps - altLost;
    if (altitude < 0) {
      altitude = 0;
    }

    // calculate ground speed from airspeed, direction, and wind speed.
    final double stepSizeHeight = 100;
    for (double alt = altitude; alt >= 0; alt -= stepSizeHeight) {
      double wSpeed = 0;
      double wAngle = 0;
      if(wa != null) {
        final (double? angle, double? speed) = wa.getWindAtAltitude(alt);
        if(angle != null && speed != null) {
          wAngle = angle;
          wSpeed = speed;
        }
      }

      wSpeed = (wSpeed * _feetPerNm) / 3600.0;

      final double tas = asT - asT * ((alt / 1000.0) * 2.0 / 100.0); // 2% per 1000 ft approx

      final double deltaAngleRad = (bearingAt - wAngle) * math.pi / 180.0;
      final double gs = math.sqrt(tas * tas + wSpeed * wSpeed - 2.0 * tas * wSpeed * math.cos(deltaAngleRad));

      // how much time we spend in each zone, thermals not accounted for.
      // Avoid division by zero
      final double timeInZone = stepSizeHeight / sinkRate;
      // find where we could get to
      double? e;
      LatLng ll = GeoCalculations().calculateOffset(currentPosition, distance, bearingAt);
      e = await ElevationCache.getElevation(ll);
      if(e == null) {
        // Tiles ran out farther along. Keep the reach already found.
        if(distance > 0) {
          return distance;
        }
      } else if(e > alt) {
        // we have reached elevation at this distance and cannot glide past
        return distance;
      }

      // convert feet to NM/miles
      distance += (gs * timeInZone  / _feetPerMeter) * Storage().units.mTo;
    }

    return distance;
  }

}

