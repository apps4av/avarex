import 'dart:math';

import 'package:geomag/geomag.dart';
import 'package:latlong2/latlong.dart';

import 'constants.dart';


class GeoCalculations {

  final Distance _distance = const Distance();
  final GeoMag _mag = GeoMag();

  static const double segmentLength = 100; // nm
  static const double earthRadiusConversion = 3440.069; // nm

  static double toDegrees(double radians) {
    return radians * 180.0 / pi;
  }
  static double toRadians(double degrees) {
    return degrees * pi / 180.0;
  }
  // points on greater circle
  List<LatLng> findPoints(LatLng begin, LatLng end, [int? segmentLengthIn]) {

    List<LatLng> coordinates = [];
    double lat1 = toRadians(begin.latitude);
    double lon1 = toRadians(begin.longitude);
    double lat2 = toRadians(end.latitude);
    double lon2 = toRadians(end.longitude);

    double distance = calculateDistance(begin, end);
    if(0 == distance) {
      return []; // same point
    }
    double num = (distance / (segmentLengthIn?? segmentLength)).roundToDouble();
    num = num < 2 ? 2 : num;
    double d = (distance / earthRadiusConversion);
    double step = (num / (num - 1));
    for (double i = 0; i < num; i = i + 1) {
      double f = (i * step) / num;
      double A = (sin((1 - f) * d) / sin(d));
      double B = (sin(f * d) / sin(d));
      double x = (((A * cos(lat1)) * cos(lon1)) + ((B * cos(lat2)) * cos(lon2)));
      double y = (((A * cos(lat1)) * sin(lon1)) + ((B * cos(lat2)) * sin(lon2)));
      double z = ((A * sin(lat1)) + (B * sin(lat2)));
      double degreeLat = toDegrees(atan2(z, sqrt((x * x) + (y * y))));
      double degreeLon = toDegrees(atan2(y, x));
      coordinates.add(LatLng(degreeLat, degreeLon));
    }

    return coordinates;
  }

  static double horizonDistance(double altitudeFt)
  {
    return 1.06 * sqrt(altitudeFt);
  }


  static double getMagneticHeading(double heading, double variation) {
    return (heading + variation + 360) % 360;
  }

  static String getGeneralDirectionFrom(double bearingIn, double declination)
  {
    const double dirDegrees = 15;

    String dir;
    double bearing = getMagneticHeading(bearingIn, declination);
    if ((bearing > dirDegrees) && (bearing <= (90 - dirDegrees))) {
      dir = "SW of";
    } else {
      if ((bearing > (90 - dirDegrees)) && (bearing <= (90 + dirDegrees))) {
        dir = "W of";
      } else {
        if ((bearing > (90 + dirDegrees)) && (bearing <= (180 - dirDegrees))) {
          dir = "NW of";
        } else {
          if ((bearing > (180 - dirDegrees)) && (bearing <= (180 + dirDegrees))) {
            dir = "N of";
          } else {
            if ((bearing > (180 + dirDegrees)) && (bearing <= (270 - dirDegrees))) {
              dir = "NE of";
            } else {
              if ((bearing > (270 - dirDegrees)) && (bearing <= (270 + dirDegrees))) {
                dir = "E of";
              } else {
                if ((bearing > (270 + dirDegrees)) && (bearing <= (360 - dirDegrees))) {
                  dir = "SE of";
                } else {
                  dir = "S of";
                }
              }
            }
          }
        }
      }
    }
    return dir;
  }


  double calculateDistance(LatLng ll1, LatLng ll2) {
    return Constants.mToNm(_distance(ll1, ll2));
  }

  double calculateBearing(LatLng ll1, LatLng ll2) {
    double bearing = _distance.bearing(ll1, ll2);
    bearing = bearing < 0 ? bearing + 360 : bearing;
    return bearing;
  }

  double getVariation(LatLng ll1) {
    return -_mag.calculate(ll1.latitude, ll1.longitude).dec; // somehow the package sends inverse
  }

  LatLng calculateOffset(LatLng from, double distance, double heading) {
    return _distance.offset(from, Constants.nmToM(distance), heading);
  }

  static int convertSpeed(double gpsSpeed) {
    return (gpsSpeed * 1.94384).round();
  }
  static int convertAltitude(double gpsAltitude) {
    return (gpsAltitude * 3.28084).round();
  }
  static int convertMagneticHeading(double heading) {
    return heading.round();
  }

}

