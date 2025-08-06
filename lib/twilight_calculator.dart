import 'dart:math';

class TwilightCalculator {
  static const int day = 0;
  static const int night = 1;
  static const double _degreesToRadians = pi / 180.0;
  static const double _j0 = 0.0009;
  static const double _altitudeCorrectionCivilTwilight = 0;
  static const double _c1 = 0.0334196;
  static const double _c2 = 0.000349066;
  static const double _c3 = 0.000005236;
  static const double _obliquity = 0.40927971;
  static const int _utc2000ms = 946728000000;

  static (DateTime? sunset, DateTime? sunrise) calculateTwilight(double latitude, double longitude) {
    int sunset;
    int sunrise;


    final int time = DateTime.now().millisecondsSinceEpoch;
    final double daysSince2000 = (time - _utc2000ms) / Duration.millisecondsPerDay;
    final double meanAnomaly = 6.240059968 + daysSince2000 * 0.01720197;
    final double trueAnomaly = meanAnomaly + _c1 * sin(meanAnomaly) + _c2 * sin(2 * meanAnomaly) + _c3 * sin(3 * meanAnomaly);
    final double solarLng = trueAnomaly + 1.796593063 + pi;
    final double arcLongitude = -longitude / 360;
    double n = (daysSince2000 - _j0 - arcLongitude).roundToDouble();
    double solarTransitJ2000 = n + _j0 + arcLongitude + 0.0053 * sin(meanAnomaly) - 0.0069 * sin(2 * solarLng);
    double solarDec = asin(sin(solarLng) * sin(_obliquity));
    final double latRad = latitude * _degreesToRadians;
    double cosHourAngle = (sin(_altitudeCorrectionCivilTwilight) - sin(latRad) * sin(solarDec)) / (cos(latRad) * cos(solarDec));

    if (cosHourAngle >= 1) {
      return (null, null);
    }
    else if (cosHourAngle <= -1) {
      return (null, null);
    }
    double hourAngle = acos(cosHourAngle) / (2 * pi);
    sunset = ((solarTransitJ2000 + hourAngle) * Duration.millisecondsPerDay).round() + _utc2000ms;
    sunrise = ((solarTransitJ2000 - hourAngle) * Duration.millisecondsPerDay).round() + _utc2000ms;
    // this returns local time, since offset was added
    return (DateTime.fromMillisecondsSinceEpoch(sunrise, isUtc: true),
      DateTime.fromMillisecondsSinceEpoch(sunset, isUtc: true));
  }
}


