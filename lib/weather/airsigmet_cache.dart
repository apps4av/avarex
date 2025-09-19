import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:avaremp/data/weather_database_helper.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

import 'airsigmet.dart';
import 'weather.dart';

class AirSigmetCache extends WeatherCache {

  AirSigmetCache(super.url, super.dbCall);

  @override
  Future<void> parse(List<Uint8List> data, [String? argument]) async {

    if(data.isEmpty) {
      return;
    }

    List<AirSigmet> airSigmet = [];

    for(Uint8List datum in data) {

      final List<int> decodedData;
      String decoded;
      try {
        decodedData = GZipCodec().decode(datum);
        decoded = utf8.decode(decodedData, allowMalformed: true);
      }
      catch(e) {
        // not gzipped
        Storage().setException("AIRMET/SIGMET: unable to decode data.");
        continue;
      }

      if(decoded.startsWith("<?xml")) {
        final document = XmlDocument.parse(decoded);

        final textual = document.findAllElements("GAIRMET");
        int count = 0;
        for (var text in textual) {
          final List<LatLng> points = [];
          final List<XmlElement> pointElements = text.findAllElements("point").toList();
          for (var point in pointElements) {
            try {
              double latitude = double.parse(
                  point.getElement("latitude")!.innerText);
              double longitude = double.parse(
                  point.getElement("longitude")!.innerText);
              points.add(LatLng(latitude, longitude));
            }
            catch (e) {
              continue;
            }
          }

          // cannot show
          if(points.isEmpty) {
            continue;
          }

          String? product;
          String? hazard;
          DateTime? expires;
          String? valid;
          String? minAltitude;
          String? maxAltitude;
          String? altitude;

          try {
            product = text.getElement("product")!.innerText;
            hazard = text
                .getElement("hazard")!
                .attributes
                .first
                .value;
            expires = DateTime.parse(text.getElement("expire_time")!.innerText);
            valid = text.getElement("valid_time")!.innerText;
          }
          catch (e) { // must have
            continue;
          }

          try {
            minAltitude = text.getElement("altitude")!.attributes[0].value;
            maxAltitude = text.getElement("altitude")!.attributes[1].value;
            altitude = "From $minAltitude to $maxAltitude MSL\n";
          }
          catch (e) {
            altitude = "";
          }

          AirSigmet a = AirSigmet(
            (count++).toString(),
            expires,
            DateTime.now(),
            Weather.sourceInternet,
            "AIRMET $product $hazard\nValid $valid\n$altitude",
            points,
            hazard,
            "",
            product);
          airSigmet.add(a);
        }

        final textual2 = document.findAllElements("AIRSIGMET");
        count = 0;
        for (var text in textual2) {
          final List<LatLng> points = [];
          final List<XmlElement> pointElements = text.findAllElements("point").toList();
          for (var point in pointElements) {
            try {
              double latitude = double.parse(
                  point.getElement("latitude")!.innerText);
              double longitude = double.parse(
                  point.getElement("longitude")!.innerText);
              points.add(LatLng(latitude, longitude));
            }
            catch (e) {
              continue;
            }
          }

          // cannot show
          if(points.isEmpty) {
            continue;
          }

          String? product;
          String? hazard;
          DateTime? expires;
          String? valid;
          String? minAltitude;
          String? maxAltitude;
          String? altitude;

          try {
            product = text.getElement("raw_text")!.innerText;
            hazard = text
                .getElement("hazard")!
                .attributes
                .first
                .value;
            expires = DateTime.parse(text.getElement("valid_time_to")!.innerText);
            valid = text.getElement("valid_time_from")!.innerText;
          }
          catch (e) { // must have
            continue;
          }

          try {
            minAltitude = text.getElement("altitude")!.getAttribute("min_ft_msl");
            maxAltitude = text.getElement("altitude")!.getAttribute("max_ft_msl");
            altitude = "${minAltitude ?? '0'} to ${maxAltitude ?? "--"} MSL\n";
          }
          catch (e) {
            altitude = "";
          }

          AirSigmet a = AirSigmet(
              (count++).toString(),
              expires,
              DateTime.now(),
              Weather.sourceInternet,
              "AIRMET $product $hazard\nValid $valid\n$altitude",
              points,
              hazard,
              "",
              product);
          airSigmet.add(a);
        }
      }

    }
/*      else {
        List<List<dynamic>> rows = const CsvToListConverter().convert(
            decoded, eol: "\n");
        for (List<dynamic> row in rows) {
          DateTime time = DateTime.now().toUtc();
          time = time.add(const Duration(minutes: Constants
              .weatherUpdateTimeMin)); // they update every minute but that's too fast

          AirSigmet a;
          try {
            // Tail number @lat, lon
            List<String> points = row[3].split(";");
            List<LatLng> ll = [];
            for (String point in points) {
              List<String> cc = point.split(":");
              // Tail number @lat, lon
              LatLng? pv = WeatherCache.parseAndValidateCoordinate(cc[1].toString(), cc[0].toString());
              if(pv != null) {
                ll.add(pv);
              }
            }
            a = AirSigmet(
                row[3].toString(),
                time,
                DateTime.now().toUtc(),
                Weather.sourceInternet,
                row[0].toString(),
                ll,
                row[8].toString(),
                row[9].toString(),
                row[10].toString());
            airSigmet.add(a);
          }
          catch (e) {
            continue;
          }
        }
      }*/


    await WeatherDatabaseHelper.db.addAirSigmets(airSigmet);
  }
}

