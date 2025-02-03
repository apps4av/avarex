import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:avaremp/constants.dart';
import 'package:avaremp/data/weather_database_helper.dart';
import 'package:avaremp/weather/taf.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:csv/csv.dart';
import 'package:latlong2/latlong.dart';

class TafCache extends WeatherCache {

  TafCache(super.url, super.dbCall);

  @override
  Future<void> parse(List<Uint8List> data, [String? argument]) async {
    if(data.isEmpty) {
      return;
    }
    final List<int> decodedData = GZipCodec().decode(data[0]);
    final List<Taf> tafs = [];
    String decoded = utf8.decode(decodedData, allowMalformed: true);
    List<List<dynamic>> rows = const CsvToListConverter().convert(decoded, eol: "\n");

    DateTime time = DateTime.now().toUtc();
    time = time.add(const Duration(minutes: Constants.weatherUpdateTimeMin)); // they update every minute but that's too fast

    for (List<dynamic> row in rows) {

      Taf t;
      try {
        double? lat = double.tryParse(row[7].toString());
        double? lon = double.tryParse(row[8].toString());
        if(lat != null && lon != null) {
          if(lat > 90 || lat < -90 || lon > 180 || lon < -180) {
            continue;
          }
          t = Taf(row[1], time, row[0].toString().replaceAll(" FM", "\nFM").replaceAll(" BECMG", "\nBECMG").replaceAll(" TEMPO", "\nTEMPO"), LatLng(lat, lon));
          tafs.add(t);
        }
      }
      catch(e) {
        continue;
      }
    }

    await WeatherDatabaseHelper.db.addTafs(tafs);
  }
}

