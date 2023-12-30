library com.ds.avare.position;
import 'dart:math';

import 'package:latlong2/latlong.dart';

import 'constants.dart';


class GeoCalculations {

  final Distance _distance = const Distance();

  static const double segmentLength = 100; // nm
  static const double earthRadiusConversion = 3440.069; // nm

  static double toDegrees(double radians) {
    return radians * 180.0 / pi;
  }
  static double toRadians(double degrees) {
    return degrees * pi / 180.0;
  }
  // points on greater circle
  List<LatLng> findPoints(LatLng begin, LatLng end) {


    List<LatLng> coordinates = [];
    double lat1 = toRadians(begin.latitude);
    double lon1 = toRadians(begin.longitude);
    double lat2 = toRadians(end.latitude);
    double lon2 = toRadians(end.longitude);

    if(lat1 == lat2 && lon1 == lon2) {
      return []; // same point
    }

    double distance = calculateDistance(begin, end);
    double num = (distance / segmentLength).roundToDouble();
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

  String getGeneralDirectionFrom(double bearingIn, double declination)
  {
    const double dirDegrees = 15;

    String dir;
    double bearing = getMagneticHeading(bearingIn, declination);
    if ((bearing > dirDegrees) && (bearing <= (90 - dirDegrees))) {
      dir = "SW of";
    } else {
      if ((bearing > (90 - dirDegrees)) && (bearing <= (90 + dirDegrees))) {
        dir = "W  of";
      } else {
        if ((bearing > (90 + dirDegrees)) && (bearing <= (180 - dirDegrees))) {
          dir = "NW of";
        } else {
          if ((bearing > (180 - dirDegrees)) && (bearing <= (180 + dirDegrees))) {
            dir = "N  of";
          } else {
            if ((bearing > (180 + dirDegrees)) && (bearing <= (270 - dirDegrees))) {
              dir = "NE of";
            } else {
              if ((bearing > (270 - dirDegrees)) && (bearing <= (270 + dirDegrees))) {
                dir = "E  of";
              } else {
                if ((bearing > (270 + dirDegrees)) && (bearing <= (360 - dirDegrees))) {
                  dir = "SE of";
                } else {
                  dir = "S  of";
                }
              }
            }
          }
        }
      }
    }
    return dir;
  }


  double calculateDistance(ll1, ll2) {
    return Constants.metersToKnots(_distance.as(LengthUnit.Meter, ll1, ll2));
  }

  double calculateBearing(ll1, ll2) {
    return _distance.bearing(ll1, ll2);
  }

  LatLng calculateOffset(from, distance, heading) {
    return _distance.offset(from, Constants.knotsToMeters(distance), heading);
  }

}

