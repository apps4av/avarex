import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:avaremp/constants.dart';
import 'package:avaremp/data/weather_database_helper.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/taf.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

import 'weather.dart';

class TafCache extends WeatherCache {

  TafCache(super.url, super.dbCall);

  @override
  Future<void> parse(List<Uint8List> data, [String? argument]) async {
    if(data.isEmpty) {
      return;
    }
    final List<int> decodedData;
    String decoded;
    final XmlDocument document;
    final Iterable<XmlElement> textual;
    final List<Taf> tafs = [];

    try {
      decodedData = GZipCodec().decode(data[0]);
      decoded = utf8.decode(decodedData, allowMalformed: true);
      document = XmlDocument.parse(decoded);
      textual = document.findAllElements("TAF");
    }
    catch(e) {
      // not gzipped
      Storage().setException("TAF: unable to decode data.");
      return;
    }

    if(decoded.startsWith("<?xml")) {
      for (var taf in textual) {
        try {
          String rt = taf.getElement("raw_text")!.innerText;
          double latitude = double.parse(taf.getElement("latitude")!.innerText);
          double longitude = double.parse(taf.getElement("longitude")!.innerText);
          String station = taf.getElement("station_id")!.innerText;
          LatLng? pv = WeatherCache.parseAndValidateCoordinate(latitude.toString(), longitude.toString());
          if(pv == null) {
            continue;
          }
          Taf t = Taf(station,
              DateTime.now().toUtc().add(const Duration(minutes: Constants.weatherUpdateTimeMin)),
              DateTime.now().toUtc(),
              Weather.sourceInternet, rt.toString().replaceAll(" FM", "\nFM").replaceAll(" BECMG", "\nBECMG").replaceAll(" TEMPO", "\nTEMPO"), pv);
          tafs.add(t);
        }
        catch(e) {
          continue;
        }
      }
    }

    await WeatherDatabaseHelper.db.addTafs(tafs);
  }
}

