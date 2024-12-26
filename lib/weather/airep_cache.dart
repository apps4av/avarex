import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:avaremp/data/weather_database_helper.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:csv/csv.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import 'airep.dart';

class AirepCache extends WeatherCache {

  AirepCache(super.url, super.dbCall);

  @override
  Future<void> parse(List<Uint8List> data, [String? argument]) async {
    if(data.isEmpty) {
      return;
    }
    final List<int> decodedData = GZipCodec().decode(data[0]);

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
    await WeatherDatabaseHelper.db.addAireps(aireps);
  }
}

