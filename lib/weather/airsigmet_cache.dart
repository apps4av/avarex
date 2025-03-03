import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:avaremp/constants.dart';
import 'package:avaremp/data/weather_database_helper.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:csv/csv.dart';
import 'package:latlong2/latlong.dart';

import 'airsigmet.dart';

class AirSigmetCache extends WeatherCache {

  AirSigmetCache(super.url, super.dbCall);

  @override
  Future<void> parse(List<Uint8List> data, [String? argument]) async {
    if(data.isEmpty) {
      return;
    }
    final List<int> decodedData = GZipCodec().decode(data[0]);

    List<AirSigmet> airSigmet = [];
    String decoded = utf8.decode(decodedData, allowMalformed: true);
    List<List<dynamic>> rows = const CsvToListConverter().convert(decoded, eol: "\n");
    for (List<dynamic> row in rows) {
      DateTime time = DateTime.now().toUtc();
      time = time.add(const Duration(minutes: Constants.weatherUpdateTimeMin)); // they update every minute but that's too fast

      AirSigmet a;
      try {
        // Tail number @lat, lon
        List<String> points = row[3].split(";");
        List<LatLng> ll = [];
        for(String point in points) {
          List<String> cc = point.split(":"); 
          LatLng aPoint = LatLng(double.parse(cc[1]), double.parse(cc[0]));
          ll.add(aPoint);
        }
        a = AirSigmet(row[3].toString(), time, row[0].toString(), ll, row[8].toString(), row[9].toString(), row[10].toString());
        airSigmet.add(a);
      }
      catch(e) {
        continue;
      }
    }

    await WeatherDatabaseHelper.db.addAirSigmets(airSigmet);
  }
}

