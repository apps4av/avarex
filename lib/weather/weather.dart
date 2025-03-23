

class Weather {

  String station;
  DateTime expires;
  DateTime received;
  String source;

  static const String sourceInternet = "Internet";
  static const String sourceADSB = "ADS-B";

  Weather(this.station, this.expires, this.received, this.source);

  bool isExpired() {
    Duration diff = expires.difference(DateTime.now().toUtc());
    return (diff.inSeconds < 0);
  }

  bool isVeryOld() {
    Duration diff = expires.difference(DateTime.now().toUtc());
    return (diff.inHours < -12);
  }

  @override
  String toString() {
    // do not show milliseconds in the time
    String r = received.toUtc().toString().substring(5, 16);
    return "*$source received ${r}Z*\n";
  }

}


