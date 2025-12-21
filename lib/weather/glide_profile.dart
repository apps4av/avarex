import 'dart:math' as math;
import 'package:avaremp/aircraft.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/gps.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/winds_aloft.dart';
import 'package:latlong2/latlong.dart';

class GlideProfile {
  // Members that get set at object construction
  final List<double?> _distanceTotal;
  String _label = "";

  static const int _heightSteps = 10;
  static const int _directionSteps = 24;
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

  String get label => _label;

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

    // units in feet and seconds
    double currentSpeed = Storage().position.speed * _feetPerMeter; // feet per second
    double altitudeGps = Storage().position.altitude * _feetPerMeter; // feet
    double bearing = Storage().position.heading; // track true north
    _distanceTotal.fillRange(0, _directionSteps, null);
    _label = "";

    if(Storage().area.elevation == null) {
      return; // no area elevation, cannot compute glide
    }
    double elevation = Storage().area.elevation!;

    List<Aircraft> aircraftList = await UserDatabaseHelper.db.getAllAircraft();
    if(aircraftList.isEmpty) {
      return; // no aircraft, cannot compute glide
    }
    double sinkRate = (double.tryParse(aircraftList[0].sinkRate) ?? 100) / 60.0; // feet per second (sink rate was fpm if not specified use 100 fpm)

    WindsAloft? wa = Storage().area.windsAloft;
    if(null == wa) {
      return; // no winds aloft, cannot compute glide
    }
    // calculate airspeed from ground speed, direction, and wind speed.
    double? wSpeed;
    double? wAngle;
    (wAngle, wSpeed) = wa.getWindAtAltitude(altitudeGps);
    if(wSpeed == null || wAngle == null) {
      return; // no wind at altitude, cannot compute glide
    }

    // convert wind speed to feet per second from knots
    wSpeed = (wSpeed * _feetPerNm) / 3600.0;

    (double, double) t = WindTriangle.getTrueFromGroundAndWind(bearing, currentSpeed, wAngle, wSpeed);
    final double asT = t.$2; // true airspeed in feet per second
    double asToShow = GeoCalculations.convertSpeed(asT * Storage().units.fToM);
    _label = "${asToShow.round()}@${t.$1.round().toString()}\u00B0";

    // calculate winds from current altitude to ground.
    for (int dir = 0; dir < _directionSteps; dir++) {
      final double targetAngle = dir * _stepSizeDirection.toDouble();
      _distanceTotal[dir] = _findDistanceTo(bearing, targetAngle, sinkRate, altitudeGps, elevation, asT, wa);
      // now we know how far we can glide in each direction
    }
  }

  /// Shortest angular distance between two headings in degrees in range [0, 180].
  static double _angularDistance(double alpha, double beta) {
    final double phi = (beta - alpha).abs() % 360;
    final double distance = phi > 180 ? 360 - phi : phi;
    return distance;
  }

  /// Find distance covered when gliding from `bearing` to `bearingAt` given sink rate,
  /// altitudes, airspeed (as), and winds aloft.
  ///
  /// Returns miles (as in original code).
  static double? _findDistanceTo(double bearing, double bearingAt, double sinkRate, double altitudeGps, double elevation, double asT, WindsAloft wa) {
    double distance = 0.0;

    // calculate ground speed from airspeed, direction, and wind speed.
    for (int alt = 0; alt < _heightSteps; alt++) {
      // correct altitude based on direction as turn loses altitude, assume 1 second per 3 degrees, and shortest dir turn
      final double turnAngle = _angularDistance(bearing, bearingAt);
      final double altLost = turnAngle / 3.0 * sinkRate;
      double altitude = altitudeGps - altLost;
      if (altitude < 0) {
        altitude = 0;
      }

      final int stepSizeHeight = ((altitude - elevation) ~/ _heightSteps);
      final double thisAltitude = alt * stepSizeHeight.toDouble() + elevation;

      double? wSpeed;
      double? wAngle;
      (wAngle, wSpeed) = wa.getWindAtAltitude(thisAltitude);
      if(wSpeed == null || wAngle == null) {
        return null; // no wind at altitude, cannot compute glide
      }

      wSpeed = (wSpeed * _feetPerNm) / 3600.0;

      final double tas = asT - asT * ((thisAltitude / 1000.0) * 2.0 / 100.0); // 2% per 1000 ft approx

      final double deltaAngleRad = (bearingAt - wAngle) * math.pi / 180.0;
      final double gs = math.sqrt(tas * tas + wSpeed * wSpeed - 2.0 * tas * wSpeed * math.cos(deltaAngleRad));

      // how much time we spend in each zone, thermals not accounted for.
      // Avoid division by zero
      final double timeInZone = stepSizeHeight / sinkRate;
      distance += gs * timeInZone;
    }

    // convert feet to NM/miles
    return (distance / _feetPerMeter) * Storage().units.mTo;
  }

}

