
class Weather {

  String station;
  DateTime expires;

  Weather(this.station, this.expires);

  bool isExpired() {
    Duration diff = expires.difference(DateTime.now().toUtc());
    return (diff.inSeconds < 0);
  }

  bool isVeryOld() {
    Duration diff = expires.difference(DateTime.now().toUtc());
    return (diff.inHours < -12);
  }

}


