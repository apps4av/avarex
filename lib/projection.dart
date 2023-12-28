library com.ds.avare.position;
import 'dart:math';

import 'coordinate.dart';


class Projection {
  double _bearing = 0;
  double _distance = 0;
  double _lon1 = 0;
  double _lon2 = 0;
  double _lat1 = 0;
  double _lat2 = 0;

  static const double earthRadiusConversion = 3440.069; //knots

  static double toRadians(double degrees) {
    return degrees * pi / 180.0;
  }

  static double toDegrees(double radians) {
    return radians * 180.0 / pi;
  }

  Projection(double lon1, double lat1, double lon2, double lat2)
  {
    _lon1 = toRadians(lon2);
    _lon2 = toRadians(lon1);
    _lat1 = toRadians(lat2);
    _lat2 = toRadians(lat1);
    lat1 = _lat2;
    lat2 = _lat1;
    lon2 = _lon1;
    lon1 = _lon2;
    double dLon = (lon2 - lon1);
    double y = (sin(dLon) * cos(lat2));
    double x = ((cos(lat1) * sin(lat2)) - ((sin(lat1) * cos(lat2)) * cos(dLon)));
    double dLat = (lat2 - lat1);
    double a = ((sin(dLat / 2) * sin(dLat / 2)) + (((cos(lat1) * cos(lat2)) * sin(dLon / 2)) * sin(dLon / 2)));
    double c = (2 * atan2(sqrt(a), sqrt(1 - a)));
    _distance = (earthRadiusConversion * c);
    _bearing = ((toDegrees(atan2(y, x)) + 360) % 360);
  }

  static double getStaticBearing(double lon1, double lat1, double lon2, double lat2)
  {
    lon1 = toRadians(lon1);
    lon2 = toRadians(lon2);
    lat1 = toRadians(lat1);
    lat2 = toRadians(lat2);
    double dLon = (lon2 - lon1);
    double y = (sin(dLon) * cos(lat2));
    double x = ((cos(lat1) * sin(lat2)) - ((sin(lat1) * cos(lat2)) * cos(dLon)));
    return (toDegrees(atan2(y, x)) + 360) % 360;
  }

  static double getStaticDistance(double lon1, double lat1, double lon2, double lat2)
  {
    lon1 = toRadians(lon1);
    lon2 = toRadians(lon2);
    lat1 = toRadians(lat1);
    lat2 = toRadians(lat2);
    double dLon = (lon2 - lon1);
    double dLat = (lat2 - lat1);
    double a = ((sin(dLat / 2) * sin(dLat / 2)) + (((cos(lat1) * cos(lat2)) * sin(dLon / 2)) * sin(dLon / 2)));
    double c = (2 * atan2(sqrt(a), sqrt(1 - a)));
    return earthRadiusConversion * c;
  }

  List<Coordinate> findPoints(int num)
  {
    List<Coordinate> coordinates = [];
    double d = (_distance / earthRadiusConversion);
    double step = (num / (num - 1));
    for (int i = 0; i < num; i++) {
      double f = ((i * step) / num);
      double A = (sin((1 - f) * d) / sin(d));
      double B = (sin(f * d) / sin(d));
      double x = (((A * cos(_lat1)) * cos(_lon1)) + ((B * cos(_lat2)) * cos(_lon2)));
      double y = (((A * cos(_lat1)) * sin(_lon1)) + ((B * cos(_lat2)) * sin(_lon2)));
      double z = ((A * sin(_lat1)) + (B * sin(_lat2)));
      double lat1 = toDegrees(atan2(z, sqrt((x * x) + (y * y))));
      double lon1 = toDegrees(atan2(y, x));
      coordinates[i] = Coordinate(Longitude(lon1), Latitude(lat1));
    }
    return coordinates;
  }

  static Coordinate findStaticPoint(double longitude, double latitude, double bearing, double distance)
  {
    double lat1 = toRadians(latitude);
    double lon1 = toRadians(longitude);
    double brg = toRadians(bearing);
    double lat2 = asin((sin(lat1) * cos(distance / earthRadiusConversion)) + ((cos(lat1) * sin(distance / earthRadiusConversion)) * cos(brg)));
    double lon2 = (lon1 + atan2((sin(brg) * sin(distance / earthRadiusConversion)) * cos(lat1), cos(distance / earthRadiusConversion) - (sin(lat1) * sin(lat2))));
    return Coordinate(Longitude(toDegrees(lon2)), Latitude(toDegrees(lat2)));
  }

  static double horizonDistance(double altitudeFt)
  {
    return 1.06 * sqrt(altitudeFt);
  }

  double getBearing()
  {
    return _bearing;
  }

  double getDistance()
  {
    return _distance;
  }

  static double getMagneticHeading(double heading, double variation) {
    return (heading + variation + 360) % 360;
  }

  // lon/lat from a location to distance and bearing
  static Coordinate findCoordinate(double lon, double lat, double distance, double bearing) {

    //http://www.movable-type.co.uk/scripts/latlong.html

    double lat1 = toRadians(lat);
    double lon1 = toRadians(lon);
    double tc = toRadians(bearing);
    double d = distance / earthRadiusConversion;

    double lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(tc) );
    double lon2 = lon1 + atan2(sin(tc) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2));

    return Coordinate(Longitude(toDegrees(lon2)), Latitude(toDegrees(lat2)));
  }

  String getGeneralDirectionFrom(double declination)
  {
    const double dirDegrees = 15;

    String dir;
    double bearing = getMagneticHeading(_bearing, declination);
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
}

