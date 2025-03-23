import 'package:avaremp/weather/weather.dart';

class Notam extends Weather {

  String text;

  Notam(super.station, super.expires, super.recieved, super.source, this.text);

  Map<String, Object?> toMap() {
    Map<String, Object?> map  = {
      "station": station,
      "utcMs": expires.millisecondsSinceEpoch,
      "receivedMs": received.millisecondsSinceEpoch,
      "source": source,
      "raw": text,
    };
    return map;
  }

  factory Notam.fromMap(Map<String, dynamic> maps) {

    return Notam(
      maps['station'] as String,
      DateTime.fromMillisecondsSinceEpoch(maps['utcMs'] as int),
      DateTime.fromMillisecondsSinceEpoch(maps['receivedMs'] as int),
      maps['source'] as String,
      maps['raw'] as String,
    );
  }

  @override
  String toString() {
    return "${super.toString()}$text";
  }
}

