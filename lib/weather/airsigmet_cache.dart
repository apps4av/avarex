import 'dart:convert';
import 'package:universal_io/io.dart';
import 'dart:typed_data';
import 'package:avaremp/constants.dart';
import 'package:avaremp/data/weather_database_helper.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

import 'airsigmet.dart';
import 'weather.dart';

class AirSigmetCache extends WeatherCache {

  AirSigmetCache(super.url, super.dbCall);

  /// Sanitize an altitude attribute coming from the AviationWeather.gov feed.
  /// The feed sometimes uses bogus sentinels ("null00", "-1", "") for missing
  /// data, and pads valid values with leading zeros (e.g. "08000"). Returns
  /// the cleaned-up value or null if the value should be considered missing.
  static String? _cleanAltitude(String? raw) {
    if (raw == null) return null;
    final v = raw.trim();
    if (v.isEmpty) return null;
    if (v == "null00" || v == "null" || v == "-1" || v == "0") return null;
    final n = int.tryParse(v);
    if (n != null) {
      if (n <= 0) return null;
      return n.toString();
    }
    return v; // e.g. "FZL", "SFC"
  }

  /// Build a human readable altitude string from a GAIRMET element. Returns
  /// an empty string when no usable altitude information is available.
  static String _gairmetAltitude(XmlElement gairmet) {
    String? minA;
    String? maxA;
    String? level;
    for (final alt in gairmet.findElements("altitude")) {
      minA ??= _cleanAltitude(alt.getAttribute("min_ft_msl"));
      maxA ??= _cleanAltitude(alt.getAttribute("max_ft_msl"));
      level ??= _cleanAltitude(alt.getAttribute("level_ft_msl"));
    }
    if (level != null) {
      return "At $level MSL\n";
    }
    if (minA != null && maxA != null) {
      return "From $minA to $maxA MSL\n";
    }
    if (maxA != null) {
      return "Up to $maxA MSL\n";
    }
    if (minA != null) {
      return "From $minA MSL\n";
    }
    return "";
  }

  @override
  Future<void> parse(List<Uint8List> data, [String? argument]) async {

    if(data.isEmpty) {
      return;
    }

    List<AirSigmet> airSigmet = [];

    for(Uint8List datum in data) {

      final List<int> decodedData;
      String decoded;
      final XmlDocument document;
      final Iterable<XmlElement> textual;
      final Iterable<XmlElement> textual2;

      try {
        decodedData = GZipCodec().decode(datum);
        decoded = utf8.decode(decodedData, allowMalformed: true);
        document = XmlDocument.parse(decoded);
        textual = document.findAllElements("GAIRMET");
        textual2 = document.findAllElements("AIRSIGMET");
      }
      catch(e) {
        // not gzipped
        Storage().setException("AIRMET/SIGMET: unable to decode data.");
        continue;
      }

      if(decoded.startsWith("<?xml")) {
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
          String altitude;

          try {
            product = text.getElement("product")!.innerText;
            hazard = text
                .getElement("hazard")!
                .attributes
                .first
                .value;
          }
          catch (e) { // must have
            continue;
          }

          try {
            altitude = _gairmetAltitude(text);
          }
          catch (e) {
            altitude = "";
          }

          AirSigmet a = AirSigmet(
            (count++).toString(),
            // expires, ignore this
            DateTime.now().toUtc().add(const Duration(minutes : Constants.weatherUpdateTimeMin)),
            DateTime.now().toUtc(),
            Weather.sourceInternet,
            "AIRMET $product $hazard\n$altitude",
            points,
            hazard,
            "",
            product);
          airSigmet.add(a);
        }

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
          String altitude;

          try {
            product = text.getElement("raw_text")!.innerText;
            hazard = text
                .getElement("hazard")!
                .attributes
                .first
                .value;
          }
          catch (e) { // must have
            continue;
          }

          try {
            altitude = _gairmetAltitude(text);
          }
          catch (e) {
            altitude = "";
          }

          AirSigmet a = AirSigmet(
              (count++).toString(),
              //expires, ignore this
              DateTime.now().toUtc().add(const Duration(minutes : Constants.weatherUpdateTimeMin)),
              DateTime.now().toUtc(),
              Weather.sourceInternet,
              "AIRMET $product $hazard\n$altitude",
              points,
              hazard,
              "",
              product);
          airSigmet.add(a);
        }
      }

    }
    await WeatherDatabaseHelper.db.addAirSigmets(airSigmet);
  }
}

