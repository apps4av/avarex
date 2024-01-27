import 'package:avaremp/weather.dart';

class Taf extends Weather {
  String text;

  Taf(super.station, super.expires, this.text);

  Map<String, Object?> toMap() {
    Map<String, Object?> map  = {
      "station": station,
      "utcMs": expires.millisecondsSinceEpoch,
      "raw": text,
    };
    return map;
  }

  factory Taf.fromMap(Map<String, dynamic> maps) {

    return Taf(
      maps['station'] as String,
      DateTime.fromMillisecondsSinceEpoch(maps['utcMs'] as int),
      maps['raw'] as String,
    );
  }

}

