class Conversions {
  static String convertSpeed(double gpsSpeed) {
    return (gpsSpeed * 1.94384).round().toString();
  }
  static String convertAltitude(double gpsAltitude) {
    return (gpsAltitude * 3.28084).round().toString();
  }
  static String convertTrack(double gpsHeading) {
    return "${gpsHeading.round().toString()}\u00b0";
  }

}