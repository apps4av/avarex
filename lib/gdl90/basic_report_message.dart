import 'dart:math' as math;
import 'dart:typed_data';

import 'package:avaremp/gdl90/traffic_report_message.dart';
import 'package:avaremp/storage.dart';
import 'package:latlong2/latlong.dart';

/// Dart translation of com.ds.avare.adsb.gdl90.BasicReportMessage
class BasicReportMessage extends TrafficReportMessage {
  int hour = 0;
  int min = 0;
  int sec = 0;
  bool adsbTarget = false;
  bool tisbTarget = false;
  bool surfaceVehicle = false;
  bool adsbBeacon = false;
  bool adsrTarget = false;
  bool icaoAddressIsSelfAssigned = false;
  int addressQualifier = 0;
  double lon = 0.0;
  double lat = 0.0;
  int northerlyVelocity = 0;
  int easterlyVelocity = 0;
  int nic = 0;
  bool trueTrackAngle = false;
  bool magneticHeading = false;
  bool trueHeading = false;

  static final double lonLatResolution = 2.1457672E-5;

  static double degrees(double radians) => radians * 180.0 / math.pi;

  BasicReportMessage(super.type) {
    altitude = 0;
  }

  @override
  void parse(Uint8List msg) {
    // defensive: require minimal length (original code uses up to byte 19)
    if (msg.length < 20) {
      return;
    }

    callSign = '';

    int timeOfReception = 0;
    timeOfReception = (msg[2] & 0xFF) << 16;
    timeOfReception += (msg[1] & 0xFF) << 8;
    timeOfReception += (msg[0] & 0xFF);

    double hours = timeOfReception * 0.00008 / 3600.0;
    double minutes = (hours - hours.floorToDouble()) * 60.0;
    double seconds = (minutes - minutes.floorToDouble()) * 60.0;

    hour = hours.toInt();
    min = minutes.toInt();
    sec = seconds.toInt();

    int payloadTypeCode = (msg[3] & 0xF8) >> 3;

    switch (payloadTypeCode) {
      case 0:
        adsbTarget = true;
        tisbTarget = false;
        surfaceVehicle = false;
        adsbBeacon = false;
        adsrTarget = false;
        icaoAddressIsSelfAssigned = false;
        break;
      case 1:
        adsbTarget = true;
        tisbTarget = false;
        surfaceVehicle = false;
        adsbBeacon = false;
        adsrTarget = false;
        icaoAddressIsSelfAssigned = true;
        break;
      case 2:
        adsbTarget = false;
        tisbTarget = true;
        surfaceVehicle = false;
        adsbBeacon = false;
        adsrTarget = true;
        icaoAddressIsSelfAssigned = false;
        break;
      case 3:
        adsbTarget = false;
        tisbTarget = true;
        surfaceVehicle = false;
        adsbBeacon = false;
        adsrTarget = false;
        icaoAddressIsSelfAssigned = false;
        break;
      case 4:
        adsbTarget = false;
        tisbTarget = false;
        surfaceVehicle = true;
        adsbBeacon = false;
        adsrTarget = false;
        icaoAddressIsSelfAssigned = false;
        break;
      case 5:
        adsbTarget = false;
        tisbTarget = false;
        surfaceVehicle = false;
        adsbBeacon = true;
        adsrTarget = false;
        icaoAddressIsSelfAssigned = false;
        break;
      case 6:
        adsbTarget = false;
        tisbTarget = false;
        surfaceVehicle = false;
        adsbBeacon = false;
        adsrTarget = true;
        icaoAddressIsSelfAssigned = true;
        break;
      case 7:
        adsbTarget = false;
        tisbTarget = false;
        surfaceVehicle = false;
        adsbBeacon = false;
        adsrTarget = false;
        icaoAddressIsSelfAssigned = false;
        break;
      default:
        break;
    }

    addressQualifier = msg[3] & 0x07;

    icao = (msg[4] & 0xFF) << 16;
    icao += (msg[5] & 0xFF) << 8;
    icao += (msg[6] & 0xFF);

    // bytes [7-9]: 23 bits of latitude info (does not include bit 8 of byte 9)
    int tmp = 0;
    tmp = (msg[7] & 0xFF) << 16;
    tmp += (msg[8] & 0xFF) << 8;
    tmp += (msg[9] & 0xFE);
    tmp >>= 1;

    bool isSouth = (tmp & 0x800000) > 0;
    lat = tmp.toDouble() * lonLatResolution;
    if (isSouth) {
      lat = -lat;
    }

    // bytes [9-12]: 24 bits of longitude info (starts with bit 8 of byte 9)
    tmp = 0;
    tmp = (msg[10] & 0xFF) << 16;
    tmp |= (msg[11] & 0xFF) << 8;
    tmp |= (msg[12] & 0xFE);
    tmp >>= 1;

    if ((msg[9] & 1) == 1) {
      tmp += 0x800000;
    }

    bool isWest = (tmp & 0x800000) > 0;
    lon = (tmp & 0x7FFFFF).toDouble() * lonLatResolution;
    if (isWest) {
      lon = -1.0 * (180.0 - lon);
    }

    // byte [12], bit 8: altitude type (unused here)
    int codedAltitude = 0;
    codedAltitude = (msg[13] & 0xFF) << 4;
    codedAltitude += (msg[14] & 0xF0) >> 4;
    altitude = (codedAltitude * 25) - 1025;

    nic = msg[14] & 0x04;

    airborne = (msg[15] & 0x80) == 0;
    bool supersonic = (msg[15] & 0x40) != 0;

    bool horizVelocityIsSoutherly;
    bool horizVelocityIsWesterly;
    int vel = 0;
    int tracking = 0;
    int northVelocityMagnitude = 0;
    int eastVelocityMagnitude = 0;
    int multiplier = 1;
    int tahType = 0;

    if (airborne) {
      // data is horizontal velocity
      if (supersonic) {
        multiplier = 4;
      }

      vel = (msg[15] & 0x0F) << 6;
      vel += (msg[16] & 0xFD) >> 2;
      horizVelocityIsSoutherly = (msg[15] & 0x10) != 0;
      northVelocityMagnitude = (vel * multiplier) - multiplier;

      if (horizVelocityIsSoutherly) {
        northVelocityMagnitude *= -1;
      }
      northerlyVelocity = northVelocityMagnitude;

      vel = 0;
      if ((msg[16] & 1) > 0) {
        vel = 0x200;
      }
      vel |= (msg[17] & 0xFF) << 1;
      if ((msg[18] & 0x80) > 0) {
        vel |= 0x01;
      }
      horizVelocityIsWesterly = (msg[16] & 0x02) != 0;

      eastVelocityMagnitude = (vel * multiplier) - multiplier;

      if (horizVelocityIsWesterly) {
        eastVelocityMagnitude *= -1;
      }
      easterlyVelocity = eastVelocityMagnitude;

      velocity = 0;
      trueTrackAngle = false;
      magneticHeading = false;
      trueHeading = false;
      heading = (360.0 +
          degrees(-math.atan2(-eastVelocityMagnitude.toDouble(), northVelocityMagnitude.toDouble()))) %
          360.0;

      // vertical velocity
      int verticalRate = 0;
      verticalRate = (msg[18] & 0x1F) << 4;
      verticalRate += (msg[19] & 0xF0) >> 4;
      verticalSpeed = (verticalRate * 64) - 64;
    } else {
      // object is on the ground
      vel = (msg[15] & 0x0F) << 6;
      vel += (msg[16] & 0xFD) >> 2;
      velocity = ((vel * multiplier) - multiplier).toDouble();

      tracking = (msg[17] & 0xFF) << 1;
      if ((msg[18] & 0x80) > 0) {
        tracking += 1;
      }

      heading = tracking * 0.703125;

      tahType = msg[16] & 0x02;

      switch (tahType) {
        case 1:
          trueTrackAngle = true;
          magneticHeading = false;
          trueHeading = false;
          break;
        case 2:
          trueTrackAngle = false;
          magneticHeading = true;
          trueHeading = false;
          break;
        case 3:
          trueTrackAngle = false;
          magneticHeading = false;
          trueHeading = true;
          break;
        default:
          trueTrackAngle = false;
          magneticHeading = false;
          trueHeading = false;
          break;
      }
      northerlyVelocity = 0;
      easterlyVelocity = 0;
      verticalSpeed = 0;
    }

    // payloadTypeCode specific handling in original was empty; retained for parity
    if (payloadTypeCode == 0) {
      // nothing
    } else if ((payloadTypeCode == 1) || (payloadTypeCode == 2) || (payloadTypeCode == 3)) {
      // nothing
    }

    coordinates = LatLng(lat, lon);
    Storage().trafficCache.putTraffic(this);
  }
}

