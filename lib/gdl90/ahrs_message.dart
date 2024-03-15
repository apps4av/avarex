import 'dart:typed_data';

import 'package:avaremp/pfd_painter.dart';

import 'message.dart';

class AhrsMessage extends Message {

  double? aoa;
  double? yaw;
  double? roll;
  double? pitch;
  double? slip;
  double? turnTrend;
  double? acceleration;
  double? altitude;
  double? vsi;
  double? speed;

  AhrsMessage(super.type);

  double _combineBytesForFloat(int hi, int lo) {

    int ih = (hi) & 0xFF;
    int il = (lo) & 0xFF;
    int sum = (ih << 8) + il;

    if(sum > 32767) {
      // negative number
      return (-(65536 - sum).toDouble());
    }
    else {
      return (sum.toDouble());
    }

  }

  double _combineBytesForFloatUnsigned(int hi, int lo) {

    int ih = (hi) & 0xFF;
    int il = (lo) & 0xFF;
    int sum = (ih << 8) + il;

    return (sum.toDouble());
  }

  void setPfd(PfdData pfd) {
    pfd.aoa = aoa == null ? pfd.aoa : aoa!;
    pfd.yaw = yaw == null ? pfd.yaw : yaw!;
    pfd.roll = roll == null ? pfd.roll : roll!;
    pfd.pitch = pitch == null ? pfd.pitch : pitch!;
    pfd.slip = slip == null ? pfd.slip : slip!;
    pfd.turnTrend = turnTrend == null ? pfd.turnTrend : turnTrend!;
    pfd.altitude = altitude == null ? pfd.altitude : altitude!;
    pfd.vsi = vsi == null ? pfd.vsi : vsi!;
    pfd.speed = speed == null ? pfd.speed : speed!;
  }

  @override
  void parse(Uint8List message) {

    if (0x45 == message[0]) { // iLevil

      if (0x2 == message[1]) { // Aoa
        // 1.0 is critical aoa
        // 0.68 is start of red range
        // 0.0 is neutral Aoa
        int id = 3;
        int m0 = message[id++].toInt();
        if (m0 != 0xFF) {
          aoa = (m0.toDouble()) / 100;
        }
      }
      else if (0x1 == message[1]) { // AHRS

        int m0 = 0,
            m1 = 0,
            m2 = 0,
            m3 = 0,
            m4 = 0,
            m5 = 0,
            m6 = 0,
            m7 = 0,
            m8 = 0,
            m9 = 0,
            m10 = 0,
            m11 = 0,
            m12 = 0,
            m13 = 0,
            m14 = 0,
            m15 = 0,
            m16 = 0,
            m17 = 0;
        try {
          int id = 3;
          m0 = message[id++].toInt();
          m1 = message[id++].toInt();
          m2 = message[id++].toInt();
          m3 = message[id++].toInt();
          m4 = message[id++].toInt();
          m5 = message[id++].toInt();
          m6 = message[id++].toInt();
          m7 = message[id++].toInt();
          m8 = message[id++].toInt();
          m9 = message[id++].toInt();
          m10 = message[id++].toInt();
          m11 = message[id++].toInt();
          m12 = message[id++].toInt();
          m13 = message[id++].toInt();
          m14 = message[id++].toInt();
          m15 = message[id++].toInt();
          m16 = message[id++].toInt();
          m17 = message[id++].toInt();
        }
        catch (e) {
          // to accomodate various ADSB devices as this is not well defined array.
        }

        double num;
        num = _combineBytesForFloat(m0, m1);
        if (num != 0x7FFF) {
          roll = num / 10;
        }
        num = _combineBytesForFloat(m2, m3);
        if (num != 0x7FFF) {
          pitch = num / 10;
        }
        num = _combineBytesForFloat(m4, m5);
        if (num != 0x7FFF) {
          yaw = num / 10;
        }
        num = _combineBytesForFloat(m6, m7);
        if (num != 0x7FFF) {
          slip = num / 10;
        }
        num = _combineBytesForFloat(m8, m9);
        if (num != 0x7FFF) {
          turnTrend = num / 10; // degrees per second
        }
        num = _combineBytesForFloat(m10, m11);
        if (num != 0x7FFF) {
          acceleration = num / 10;
        }
        num = _combineBytesForFloat(m12, m13);
        if (num != 0x7FFF) {
          speed = num / 10;
        }
        num = _combineBytesForFloatUnsigned(m14, m15);
        if (num != 0xFFFF) {
          altitude = num - 5000; // 5000 is SL
        }
        num = _combineBytesForFloat(m16, m17);
        if (num != 0x7FFF) {
          vsi = num;
        }
      }
    }
  }
}