import 'package:avaremp/nmea/nmea_message.dart';
import 'package:latlong2/latlong.dart';

class RMCMessage extends NmeaMessage {
  RMCMessage(super.type);

  LatLng coordinate = const LatLng(0, 0);
  int speed = 0;
  int track = 0;

  @override
  void parse(String data) {
    List<String> tokens = data.split(",");

    if (tokens.length < 9) {
      return;
    }

    double tmp;
    double tmp1;
    try {
      tmp = double.parse(tokens[3]);
      tmp1 = (tmp.toInt() ~/ 100).toDouble();
      double lat = (tmp - (tmp1 * 100.0)) / 60 + tmp1;
      if (tokens[4] == "S") {
        lat = -lat;
      }

      tmp = double.parse(tokens[5]);
      tmp1 = (tmp.toInt() ~/ 100).toDouble();
      double lon = (tmp - (tmp1 * 100.0)) / 60 + tmp1;
      if (tokens[6] == "W") {
        lon = -lon;
      }

      coordinate = LatLng(lat, lon);

      speed = (double.parse(tokens[7]) / 1.94384).round();
      track = double.parse(tokens[8]).round();

    }
    catch (e) {}

  }

}