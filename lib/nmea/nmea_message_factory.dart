import 'dart:typed_data';

import 'package:avaremp/nmea/nmea_ownship_message.dart';
import 'package:avaremp/nmea/rmc_message.dart';
import 'package:avaremp/nmea/rtm_message.dart';

import 'gga_message.dart';
import 'nmea_message.dart';

class NmeaMessageFactory {

  static RMCMessage? _rmc;
  static GGAMessage? _gga;

  // Find NMEA checksum that excludes $ and things including, after *
  static int checkSum(Uint8List message) {
    int xor = 0;
    int i = 1;
    int len = message.length;
    //Find checksum from after $ to before *
    while (i < len) {
      if (message[i] == 42) {
        break;
      }
      xor = xor ^ (message[i].toInt() & 0xFF);
      i++;
    }

    return xor;
  }

  static NmeaMessage? buildMessage(Uint8List message) {
    NmeaMessage? ret;

    int len = message.length;

    if(len < 6) {
      //A simple check for length
      return ret;
    }

    //Check checksum
    //Starts with $G, ends with checksum *DD
    if(message[0] == 36 && message[1] == 71) {
      int xor = checkSum(message);

      //Checksum is in xor data[len - 1] and data[len - 2] has checksum in Hex
      int start = message.indexOf(42) + 1;
      try {
        Uint8List cs = message.sublist(start, start + 2);
        String css = String.fromCharCodes(cs);
        int cssInt = int.parse(css, radix: 16);
        if (cssInt != xor) {
          return ret;
        }
      }
      catch(e) {
        return ret;
      }
    }
    else {
      return ret;
    }

    String type;
    String data = String.fromCharCodes(message);
    try {
      type = data.substring(3, data.indexOf(","));
    }
    catch (e) {
      return ret;
    }

    // Find which message we have
    switch(type) {
      case NmeaMessageType.recommendedMinimumSentence:
        var m = RMCMessage(type);
        m.parse(data);
        // need to combine RMC ang GGA for best ownship
        _rmc = m;
        ret = NmeaOwnShipMessage.fromGgaRmc(_gga, _rmc);
        break;
      case NmeaMessageType.essentialFix:
        var m = GGAMessage(type);
        m.parse(data);
        _gga = m;
        ret = NmeaOwnShipMessage.fromGgaRmc(_gga, _rmc);
        break;
      case NmeaMessageType.traffic:
        var m = RTMMessage(type);
        m.parse(data);
        ret = NmeaOwnShipMessage.fromRtm(m);
        break;
      default:
        return ret;
    }

    return(ret);
  }
}

class NmeaMessageType {

  static const String recommendedMinimumSentence = "RMC";
  static const String essentialFix = "GGA";
  static const String traffic = "RTM";
  static const String ownShip = "OwnShip";
}
