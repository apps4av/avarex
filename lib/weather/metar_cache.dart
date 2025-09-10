import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:avaremp/constants.dart';
import 'package:avaremp/data/weather_database_helper.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:csv/csv.dart';
import 'package:latlong2/latlong.dart';
import 'metar.dart';
import 'weather.dart';


class MetarCache extends WeatherCache {

  Uint8List? image;

  MetarCache(super.url, super.dbCall);

  @override
  Future<void> parse(List<Uint8List> data, [String? argument]) async {
    if(data.isEmpty) {
      return;
    }
    final List<int> decodedData = GZipCodec().decode(data[0]);
    final List<Metar> metars = [];
    String decoded = utf8.decode(decodedData, allowMalformed: true);
    List<List<dynamic>> rows = const CsvToListConverter().convert(decoded, eol: "\n");
    for (List<dynamic> row in rows) {
      DateTime time = DateTime.now().toUtc();
      // observation time like 2024-01-27T18:26:00Z in row[2]
      time = time.add(const Duration(minutes: Constants.weatherUpdateTimeMin)); // they update every minute but that's too fast

      Metar m;
      try {
        LatLng? pv = WeatherCache.parseAndValidateCoordinate(row[3].toString(), row[4].toString());
        if(pv == null) {
          continue;
        }
        m = Metar(row[1], time, DateTime.now().toUtc(), Weather.sourceInternet, row[0], row[30], pv);
        metars.add(m);
      }
      catch(e) {
        continue;
      }
    }
    await WeatherDatabaseHelper.db.addMetars(metars);
 }

  // Get Closets Metar of this coordinate
  Metar? getClosestMetar(LatLng coordinate) {
    GeoCalculations geo = GeoCalculations();
    double distance = 25; // do not use metars more than 25 miles away
    Metar? selected;
    List<Metar> metars = Storage().metar.getAll().map((e) => e as Metar).toList();
    for(Metar m in metars) {
      double d = geo.calculateDistance(m.coordinate, coordinate);
      if(d < distance) {
        selected = m;
        distance = d;
      }
    }
    return selected;
  }

}

