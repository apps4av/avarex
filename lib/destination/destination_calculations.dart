import 'dart:math';

import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:latlong2/latlong.dart';

import '../utils/geo_calculations.dart';

class DestinationCalculations {

  final Destination _from;
  final Destination _to;
  final double _speed;
  final double _fuelBurn;
  final double altitude;
  String wind = "";

  double distance = 0;
  double course = 0;
  double trueCourse = 0;
  double windCorrectionAngle = 0;
  double magneticCourse = 0;
  double time = 0;
  double fuel = 0;
  double groundSpeed = 0;
  double variation = 0;

  DestinationCalculations(this._from, this._to, this._speed, this._fuelBurn, this.altitude);

  // calculate all params like dist, bearing, time, altitude and fuel
  void calculateTo() {

    int fore = Storage().route.fore;

    GeoCalculations calculations = GeoCalculations();
    List<LatLng> points = calculations.findPoints(_from.coordinate, _to.coordinate);
    // take initial bearing only
    if(points.length < 2) {
      return;
    }

    for(int index = 0; index < points.length - 1; index++) {
      // distance accumulates
      double d = calculations.calculateDistance(points[index], points[index + 1]);

      // true course between points
      double tc = calculations.calculateBearing(points[index], points[index + 1]);

      double v1 = _from.geoVariation ?? 0;
      double v2 = _to.geoVariation ?? 0;
      double vStep = (v1 - v2) / points.length;

      // interpolate variation as this is a db query otherwise
      double v = v1 + vStep * index;

      double? ws, wd;
      (wd, ws) = WindsCache.getWindsAt(points[index], altitude.toDouble(), fore);
      ws = ws ?? 0;
      wd = wd ?? 0;

      WindSolution solution = WindSolution.solveWindTriangle(windSpeed: ws,
          windDirectionDeg: wd,
          courseDeg: tc,
          trueAirspeed: _speed);
      double gs = solution.groundSpeed;
      double wca = solution.wcaDeg;
      double mc = GeoCalculations.getMagneticHeading(tc, v);
      double c = (mc + wca) % 360;
      double t = 3600 * d / gs;
      double f = _fuelBurn * t / 3600;
      time += t; //sec
      fuel += f; // gallon per hour use
      distance += d;
      // show these at the start as averaging these makes no sense
      if(0 == index) {
        variation = v;
        trueCourse = tc;
        course = c;
        magneticCourse = mc;
        wind = "${wd.round()}@${ws.round()}";
        windCorrectionAngle = wca;
        groundSpeed = gs;
      }
    }

  }

  static const List<String> labels = ["FM", "TO", "AL", "TC", "VR", "MC", "WD", "CA", "MH", "DT", "GS", "TM", "FC"];
  static int columns = labels.length;
  List<String> getLog() {
    Duration d = Duration(seconds: time.round());
    List<String> log = [];
    log.add(_from.locationID);
    log.add(_to.locationID);
    log.add(altitude.round().toString());
    log.add(trueCourse.round().toString());
    log.add(variation.round().toString());
    log.add(magneticCourse.round().toString());
    log.add(wind);
    log.add(windCorrectionAngle.round().toString());
    log.add(course.round().toString());
    log.add(distance.round().toString());
    log.add(groundSpeed.round().toString());
    log.add("${d.inHours.toString().padLeft(1, "0")}:${(d.inMinutes % 60).toString().padLeft(2, "0")}");
    log.add(fuel.toStringAsFixed(1));
    return log;
  }

}

// AI generated
class WindSolution {
  final double wcaDeg; // Wind Correction Angle (degrees, +right / -left)
  final double headingDeg; // Corrected heading (degrees)
  final double groundSpeed; // Ground speed

  WindSolution({
    required this.wcaDeg,
    required this.headingDeg,
    required this.groundSpeed,
  });

  static WindSolution solveWindTriangle({
    required double windSpeed,
    required double windDirectionDeg, // FROM
    required double courseDeg,
    required double trueAirspeed,
  }) {

    final windDirRad = GeoCalculations.toRadians(windDirectionDeg);
    final courseRad = GeoCalculations.toRadians(courseDeg);

    final theta = windDirRad - courseRad;

    // Components
    final crosswind = windSpeed * sin(theta);
    final headwind = windSpeed * cos(theta);

    // Clamp for safety
    double clamp(double x) => x.clamp(-1.0, 1.0);

    // WCA
    final wcaRad = asin(clamp(crosswind / trueAirspeed));

    // Heading
    double headingDeg = GeoCalculations.toDegrees(courseRad + wcaRad);
    headingDeg = (headingDeg % 360 + 360) % 360;

    // Ground speed (corrected)
    final groundSpeed =
        sqrt(pow(trueAirspeed, 2) - pow(crosswind, 2)) - headwind;

    return WindSolution(
      wcaDeg: GeoCalculations.toDegrees(wcaRad),
      headingDeg: headingDeg,
      groundSpeed: groundSpeed,
    );
  }
}