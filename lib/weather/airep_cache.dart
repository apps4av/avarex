import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:csv/csv.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import '../storage.dart';
import 'airep.dart';

class AirepCache extends WeatherCache {

  AirepCache(super.url, super.dbCall);

  @override
  Future<void> parse(Uint8List data, [String? argument]) async {
    final List<int> decodedData = GZipCodec().decode(data);

    List<Airep> aireps = [];
    String decoded = utf8.decode(decodedData, allowMalformed: true);
    List<List<dynamic>> rows = const CsvToListConverter().convert(decoded, eol: "\n");
    for (List<dynamic> row in rows) {
      DateTime time = DateTime.now().toUtc();
      time = time.add(const Duration(minutes: Constants.weatherUpdateTimeMin)); // they update every minute but that's too fast

      Airep a;
      try {
        // Tail number @lat, lon
        a = Airep("${row[8]}@${row[9]},${row[10]}", time, row[43], LatLng(double.parse(row[9].toString()), double.parse(row[10].toString())));
        aireps.add(a);
      }
      catch(e) {
        continue;
      }
    }
    Storage().weatherRealmHelper.addAireps(aireps);
  }
}

