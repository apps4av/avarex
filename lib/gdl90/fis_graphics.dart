import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'dlac.dart';

class FisGraphics {

  String text = "";
  String startTime = "";
  String endTime = "";
  List<LatLng> coordinates = [];
  int geometryOverlayOptions = shapeNone;
  String location = "";
  bool valid = false;
  int reportNumber = 0;
  String label = "";

  static const int shapeNone = -1;
  static const int shapePolygonMSL = 3;
  static const int shapePrisonMsl = 7;
  static const int shapePrismAgl = 8;
  static const int shapePoint3DAgl = 9;

  static String _parseDate(int b0, int b1, int b2, int b3, int format) {
    DateTime now = DateTime.now();
    switch (format) {
      case 0: // No date/time used.
        return "";
      case 1: // Month, Day, Hours, Minutes.
        return DateTime(now.year, b0, b1, b2, b3).toUtc().toString();
      case 2: // Day, Hours, Minutes.
        return DateTime(now.year, now.month, b0, b1, b2).toUtc().toString();
      case 3: // Hours, Minutes.
        return DateTime(now.year, now.month, now.day, b0, b1).toUtc().toString();
    }

    return "";
  }

  LatLng _parseLatLon(int lat, int lon, bool alt) {
    double factor = 0.000687;

    if (alt) {
      factor = 0.001373;
    }
    double latC = factor * lat.toDouble();
    double lonC = factor * lon.toDouble();
    if (latC > 90) {
      latC = latC - 180;
    }
    if (lonC > 180) {
      lonC = lonC - 360;
    }

    return LatLng(latC, lonC);
  }


  void decode(Uint8List data) {

    int format;
    int count;
    int length;

    format = ((data[0]).toInt() & 0xF0) >> 4;
    count = ((data[1]).toInt() & 0xF0) >> 4;
    // Only support 1 record
    if (count != 1) {
      return;
    }

    location = Dlac.decode(data[2], data[3], data[4]);
    location = Dlac.format(location);

    /*
      0 - No data
      1 - Unformatted ASCII Text
      2 - Unformatted DLAC Text
      3 - Unformatted DLAC Text w/ dictionary
      4 - Formatted Text using ASN.1/PER
      5-7 - Future Use
      8 - Graphical Overlay
      9-15 - Future Use
    */
    switch (format) {
      case 0:
        return;
      case 2:
        length = ((data[6].toInt() & 0xFF) << 8) + (data[7].toInt() & 0xFF);
        if (data.length - length < 6) {
          return;
        }

        reportNumber = ((data[8].toInt() & 0xFF) << 6) + ((data[9].toInt() & 0xFC) >> 2);

        int len = length - 5;

        text = "";
        for (int i = 0; i < (len - 3); i += 3) {
          text += Dlac.decode(data[i + 11], data[i + 12], data[i + 13]);
        }
        text = Dlac.format(text);
        break;

      case 8:

        Uint8List recordData = data.sublist(6);

        reportNumber = ((recordData[1].toInt() & 0x3F) << 8) + (recordData[2].toInt() & 0xFF);

        // (6-1). (6.22 - Graphical Overlay Record Format).
        int flag = recordData[4] & 0x01;

        if (0 == flag) { // Numeric index.
          label = ((( recordData[5].toInt() & 0xFF) << 8) + (recordData[6].toInt() & 0xFF)).toString();
          recordData = recordData.sublist(7);
        } else {
          label = Dlac.decode(recordData[5], recordData[6], recordData[7]) +
              Dlac.decode(recordData[8], recordData[9], recordData[10]) +
              Dlac.decode(recordData[11], recordData[12], recordData[13]);
          label = Dlac.format(label);
          recordData = recordData.sublist(14);
        }

        flag = (recordData[0].toInt() & 0x40) >> 6;

        if (0 == flag) { //TODO: Check.
          recordData = recordData.sublist(2);
        } else {
          recordData = recordData.sublist(5);
        }

        int applicabilityOptions = (recordData[0].toInt() & 0xC0) >> 6;
        int dtFormat = (recordData[0].toInt() & 0x30) >> 4;
        geometryOverlayOptions = recordData[0].toInt() & 0x0F;
        int overlayVerticesCount = (recordData[1].toInt() & 0x3F) + 1; // Document instructs to add 1. (6.20).

        // Parse all of the dates.
        switch (applicabilityOptions) {
          case 0: // No times given. UFN.
            recordData = recordData.sublist(2);
            break;
          case 1: // Start time only. WEF.
            startTime = _parseDate(recordData[2].toInt(), recordData[3].toInt(), recordData[4].toInt(), recordData[5].toInt(), dtFormat);
            endTime = "";
            recordData = recordData.sublist(6);
            break;
          case 2: // End time only. TIL.
            endTime = _parseDate(recordData[2].toInt(), recordData[3].toInt(), recordData[4].toInt(), recordData[5].toInt(), dtFormat);
            startTime = "";
            recordData = recordData.sublist(6);
            break;
          case 3: // Both start and end times. WEF.
            startTime = _parseDate(recordData[2].toInt(), recordData[3].toInt(), recordData[4].toInt(), recordData[5].toInt(), dtFormat);
            endTime = _parseDate(recordData[6].toInt(), recordData[7].toInt(), recordData[8].toInt(), recordData[9].toInt(), dtFormat);
            recordData = recordData.sublist(10);
            break;

        }

        // Now we have the vertices.
        switch (geometryOverlayOptions) {
          case shapePolygonMSL: // Extended Range 3D Polygon (MSL).
            for (int i = 0; i < overlayVerticesCount; i++) {
              int lon = ((recordData[6 * i].toInt() & 0xFF) << 11) +
                  ((recordData[6 * i + 1].toInt() & 0xFF) << 3) +
                  ((recordData[6 * i + 2].toInt() & 0xE0) >> 5);

              int lat = ((recordData[6 * i + 2].toInt() & 0x1F) << 14) +
                  ((recordData[6 * i + 3].toInt() & 0xFF) << 6) +
                  ((recordData[6 * i + 4].toInt() & 0xFC) >> 2);

              // do not need altitude for shapes
              // int alt = (((recordData[6 * i + 4].toInt() & 0x03) << 8) + (recordData[6 * i + 5].toInt() & 0xFF)) * 100;

              LatLng c = _parseLatLon(lat, lon, false);
              coordinates.add(c);
            }
            break;

          case shapePoint3DAgl: // Extended Range 3D Point (AGL). p.47.
            if (recordData.length >= 6) {
              int lon = ((recordData[0].toInt() & 0xFF) << 11) +
                  ((recordData[1] & 0xFF).toInt() << 3) +
                  ((recordData[2].toInt() & 0xE0) >> 5);

              int lat = ((recordData[2].toInt() & 0x1F) << 14) +
                  ((recordData[3].toInt() & 0xFF) << 6) +
                  ((recordData[4].toInt() & 0xFC) >> 2);

              // int alt = (((recordData[4].toInt() & 0x03) << 8) + (recordData[5].toInt() & 0xFF)) * 100;

              LatLng c = _parseLatLon(lat, lon, false);
              coordinates.add(c);
            }
            else {
              return;
            }
            break;
          case shapePrismAgl:
          case shapePrisonMsl:// Extended Range Circular Prism (7 = MSL, 8 = AGL)
            if (recordData.length >= 14) {

              //int bottomLon = ((recordData[0].toInt() & 0xFF) << 10) + ((recordData[1].toInt() & 0xFF) << 2) + ((recordData[2].toInt() & 0xC0) >> 6);
              //int bottomLat = ((recordData[2].toInt() & 0x3F) << 10) + ((recordData[3].toInt() & 0xFF) << 4) + ((recordData[4].toInt() & 0xF0) >> 4);

              int topLon = ((recordData[4].toInt() & 0x0F) << 14) + ((recordData[5].toInt() & 0xFF) << 6) + ((recordData[6].toInt() & 0xFC) >> 2);
              int topLat = ((recordData[6].toInt() & 0x03) << 16) + ((recordData[7].toInt() & 0xFF) << 8) + ((recordData[8].toInt() & 0xFF));

              //int bottomAlt = ((recordData[9].toInt() & 0xFE) >> 1) * 5;
              //int topAlt = (((recordData[9].toInt() & 0x01) << 6) + (recordData[10].toInt() & 0xFC) >> 2) * 100;


              // only 2D
              //LatLng b = _parseLatLon(bottomLat, bottomLon, true);
              LatLng t = _parseLatLon(topLat, topLon, true);

              coordinates.add(t);

              // This is not a coordinate
              //double rLon = (((recordData[10].toInt() & 0x03) << 7) + ((recordData[11].toInt() & 0xFE) >> 1)).toDouble() * 0.2;
              //double rLat = (((recordData[11].toInt() & 0x01) << 8) + (recordData[12].toInt() & 0xFF)).toDouble() * 0.2;
              // int alpha = recordData[13].toInt() & 0xFF;
              //LatLng r = LatLng(rLat, rLon);
            }
            else {
              return;
            }
            break;
          default:
            return;
        }
        break;
      default:
        return;
    }

    valid = true;
  }

}