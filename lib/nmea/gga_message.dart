import 'package:avaremp/nmea/nmea_message.dart';
import 'package:latlong2/latlong.dart';

class GGAMessage extends NmeaMessage {
  GGAMessage(super.type);

  LatLng coordinate = const LatLng(0, 0);
  int altitude = -100;

  @override
  void parse(String data) {
    List<String> tokens = data.split(",");

    if (tokens.length < 11) {
      return;
    }

    double tmp;
    double tmp1;
    try {
      tmp = double.parse(tokens[2]);
      tmp1 = (tmp.toInt() ~/ 100).toDouble();
      double lat = (tmp - (tmp1 * 100.0)) / 60 + tmp1;
      if (tokens[3] == "S") {
        lat = -lat;
      }

      tmp = double.parse(tokens[4]);
      tmp1 = (tmp.toInt() ~/ 100).toDouble();
      double lon = (tmp - (tmp1 * 100.0)) / 60 + tmp1;
      if (tokens[5] == "W") {
        lon = -lon;
      }

      coordinate = LatLng(lat, lon);

      double alt = double.parse(tokens[9]);
      if(tokens[10] == "M") {
        altitude = (alt * 3.28084).round();
      }
      else {
        altitude = alt.round();
      }
    }
    catch (e) {}
  }

}