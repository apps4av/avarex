import 'package:avaremp/weather/weather.dart';

class Notam extends Weather {

  String text;

  Notam(super.station, super.expires, this.text);

  Map<String, Object?> toMap() {
    Map<String, Object?> map  = {
      "station": station,
      "utcMs": expires.millisecondsSinceEpoch,
      "raw": text,
    };
    return map;
  }

  factory Notam.fromMap(Map<String, dynamic> maps) {

    return Notam(
      maps['station'] as String,
      DateTime.fromMillisecondsSinceEpoch(maps['utcMs'] as int),
      maps['raw'] as String,
    );
  }

  @override
  String toString() {
    return text;
  }
}

