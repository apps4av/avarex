import 'dart:typed_data';
import 'message.dart';

class OwnShipGeometricAltitudeMessage extends Message {

  int altitude = -305; // 1000 ft;

  OwnShipGeometricAltitudeMessage(super.type);

  @override
  void parse(Uint8List message) {

    /*
     *  bytes 0-1 are the altitude
     */
    int upper = (message[0].toInt() & 0xFF) << 8;
    int lower = (message[1].toInt() & 0xFF);
    if (upper == 0xFF00 && lower >= 0xE0) {
      return;//invalid
    }
    else {
      double alt = upper.toDouble() + lower.toDouble();
      alt *= 5;
      alt /= 3.28084;
      altitude = alt.round();
    }
  }
}