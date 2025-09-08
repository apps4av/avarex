import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'dlac.dart';

class FisGraphics {

  String text = "";
  String startTime = "";
  String endTime = "";
  String altitudeBottom = "0";
  String altitudeTop = "0";
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
    double factor = 0.00068665;

    if (alt) {
      factor = 0.00137329;
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

    format = ((data[0]).toInt() & 0xF0) >> 4;
    count = ((data[1]).toInt() & 0xF0) >> 4;

    location = Dlac.decode(data[2], data[3], data[4]);
    location = Dlac.format(location);

    data = data.sublist(6);

    // run count loop
    for(int cc = 0; cc < count; cc++) {

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
      if (format == 2) {
        int length = ((data[0].toInt() & 0xFF) << 8) + (data[1].toInt() & 0xFF);
        if (data.length < length) {
          return;
        }
        reportNumber =
            ((data[2].toInt() & 0xFF) << 6) + ((data[3].toInt() & 0xFC) >> 2);

        int len = length - 5;

        text = "";
        data = data.sublist(5);
        for (int i = 0; i < (len - 3); i += 3) {
          text += Dlac.decode(data[0], data[1], data[2]);
          data = data.sublist(3);
        }
        text = Dlac.format(text);
      }
      else if (format == 8) {
        reportNumber =
            ((data[1].toInt() & 0x3F) << 8) + (data[2].toInt() & 0xFF);

        // (6-1). (6.22 - Graphical Overlay Record Format).
        int flag = data[4] & 0x01;

        if (0 == flag) { // Numeric index.
          label = (((data[5].toInt() & 0xFF) << 8) + (data[6].toInt() & 0xFF))
              .toString();
          data = data.sublist(7);
        }
        else {
          label = Dlac.decode(data[5], data[6], data[7]) +
              Dlac.decode(data[8], data[9], data[10]) +
              Dlac.decode(data[11], data[12], data[13]);
          label = Dlac.format(label);
          data = data.sublist(14);
        }

        flag = (data[0].toInt() & 0x40) >> 6;

        if (0 == flag) { //TODO: Check.
          data = data.sublist(2);
        } else {
          data = data.sublist(5);
        }

        int applicabilityOptions = (data[0].toInt() & 0xC0) >> 6;
        int dtFormat = (data[0].toInt() & 0x30) >> 4;
        geometryOverlayOptions = data[0].toInt() & 0x0F;
        int overlayVerticesCount = (data[1].toInt() & 0x3F) +
            1; // Document instructs to add 1. (6.20).

        // Parse all of the dates.
        switch (applicabilityOptions) {
          case 0: // No times given. UFN.
            data = data.sublist(2);
            break;
          case 1: // Start time only. WEF.
            startTime = _parseDate(
                data[2].toInt(), data[3].toInt(), data[4].toInt(),
                data[5].toInt(), dtFormat);
            endTime = "";
            data = data.sublist(6);
            break;
          case 2: // End time only. TIL.
            endTime = _parseDate(
                data[2].toInt(), data[3].toInt(), data[4].toInt(),
                data[5].toInt(), dtFormat);
            startTime = "";
            data = data.sublist(6);
            break;
          case 3: // Both start and end times. WEF.
            startTime = _parseDate(
                data[2].toInt(), data[3].toInt(), data[4].toInt(),
                data[5].toInt(), dtFormat);
            endTime = _parseDate(
                data[6].toInt(), data[7].toInt(), data[8].toInt(),
                data[9].toInt(), dtFormat);
            data = data.sublist(10);
            break;
        }

        // Now we have the vertices.
        switch (geometryOverlayOptions) {
          case shapePolygonMSL: // Extended Range 3D Polygon (MSL).
            for (int i = 0; i < overlayVerticesCount; i++) {
              int lon =
                  ((data[0].toInt() & 0xFF) << 11) +
                  ((data[1].toInt() & 0xFF) << 3) +
                  ((data[2].toInt() & 0xE0) >> 5);

              int lat =
                  ((data[2].toInt() & 0x1F) << 14) +
                  ((data[3].toInt() & 0xFF) << 6) +
                  ((data[4].toInt() & 0xFC) >> 2);

              // do not need altitude for shapes
              int alt = (((data[4].toInt() & 0x03) << 8) +
                  (data[5].toInt() & 0xFF)) * 100;
              altitudeTop = alt.toString();

              LatLng c = _parseLatLon(lat, lon, false);
              coordinates.add(c);
              data = data.sublist(6);
            }
            break;

          case shapePoint3DAgl: // Extended Range 3D Point (AGL). p.47.
            if (data.length >= 6) {
              int lon = ((data[0].toInt() & 0xFF) << 11) +
                  ((data[1] & 0xFF).toInt() << 3) +
                  ((data[2].toInt() & 0xE0) >> 5);

              int lat = ((data[2].toInt() & 0x1F) << 14) +
                  ((data[3].toInt() & 0xFF) << 6) +
                  ((data[4].toInt() & 0xFC) >> 2);

              int alt = (((data[4].toInt() & 0x03) << 8) + (data[5].toInt() & 0xFF)) * 100;
              altitudeTop = alt.toString();

              LatLng c = _parseLatLon(lat, lon, false);
              coordinates.add(c);
              data = data.sublist(6);
            }
            else {
              return;
            }
            break;
          case shapePrismAgl:
          case shapePrisonMsl: // Extended Range Circular Prism (7 = MSL, 8 = AGL)
            if (data.length >= 14) {
              int bottomLon = ((data[0].toInt() & 0xFF) << 10) +
                  ((data[1].toInt() & 0xFF) << 2) +
                  ((data[2].toInt() & 0xC0) >> 6);
              int bottomLat = ((data[2].toInt() & 0x3F) << 10) +
                  ((data[3].toInt() & 0xFF) << 4) +
                  ((data[4].toInt() & 0xF0) >> 4);

              int topLon = ((data[4].toInt() & 0x0F) << 14) +
                  ((data[5].toInt() & 0xFF) << 6) +
                  ((data[6].toInt() & 0xFC) >> 2);
              int topLat = ((data[6].toInt() & 0x03) << 16) +
                  ((data[7].toInt() & 0xFF) << 8) + ((data[8].toInt() & 0xFF));

              int bottomAlt = ((data[9].toInt() & 0xFE) >> 1) * 5;
              int topAlt = (((data[9].toInt() & 0x01) << 6) + (data[10].toInt() & 0xFC) >> 2) * 100;
              altitudeBottom = bottomAlt.toString();
              altitudeTop = topAlt.toString();

              // only 2D
              LatLng b = _parseLatLon(bottomLat, bottomLon, true);
              LatLng t = _parseLatLon(topLat, topLon, true);

              double rLon = (((data[10].toInt() & 0x03) << 7) +
                  ((data[11].toInt() & 0xFE) >> 1)).toDouble() * 0.2;
              double rLat = (((data[11].toInt() & 0x01) << 8) +
                  (data[12].toInt() & 0xFF)).toDouble() * 0.2;
              //int alpha = recordData[13].toInt() & 0xFF;
              LatLng r = LatLng(rLat, rLon);
              // make a circle with top, bottom and radius
              // TODO : Implement this
              data = data.sublist(14);
            }
            else {
              return;
            }
            break;
        }
      }
      else {
        return;
      }
    }

    valid = true;
  }

}