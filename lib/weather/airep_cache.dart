import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:avaremp/data/weather_database_helper.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

import '../constants.dart';
import 'airep.dart';
import 'weather.dart';

class AirepCache extends WeatherCache {

  AirepCache(super.url, super.dbCall);

  @override
  Future<void> parse(List<Uint8List> data, [String? argument]) async {
    if(data.isEmpty) {
      return;
    }
    final List<int> decodedData;
    String decoded;
    List<Airep> aireps = [];

    try {
      decodedData = GZipCodec().decode(data[0]);
      decoded = utf8.decode(decodedData, allowMalformed: true);
    }
    catch(e) {
      Storage().setException("AIREP: unable to decode data.");
      return;
    }

    DateTime time = DateTime.now().toUtc();
    time = time.add(const Duration(minutes: Constants.weatherUpdateTimeMin)); // they update every minute but that's too fast

    if(decoded.startsWith("<?xml")) {
      final document = XmlDocument.parse(decoded);

      final textual = document.findAllElements("AircraftReport");
      for (var airep in textual) {

        try {
          String rt = airep.getElement("raw_text")!.innerText;
          double latitude = double.parse(airep.getElement("latitude")!.innerText);
          double longitude = double.parse(airep.getElement("longitude")!.innerText);
          String aircraft = airep.getElement("aircraft_ref")!.innerText;
          LatLng? pv = WeatherCache.parseAndValidateCoordinate(latitude.toString(), longitude.toString());
          if(pv == null) {
            continue;
          }
          Airep a = Airep("$aircraft@$latitude,$longitude", time, DateTime.now().toUtc(), Weather.sourceInternet, rt, pv);
          aireps.add(a);
        }
        catch(e) {
          continue;
        }
      }
    }

    await WeatherDatabaseHelper.db.addAireps(aireps);
  }
}

