import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:avaremp/taf.dart';
import 'package:avaremp/weather_cache.dart';
import 'package:avaremp/weather_database_helper.dart';
import 'package:csv/csv.dart';

class TafCache extends WeatherCache {

  TafCache(super.url, super.dbCall);

  @override
  Future<void> parse(Uint8List data) async {
    final List<int> decodedData = GZipCodec().decode(data);
    final List<Taf> tafs = [];
    String decoded = utf8.decode(decodedData, allowMalformed: true);
    List<List<dynamic>> rows = const CsvToListConverter().convert(decoded, eol: "\n");
    for (List<dynamic> row in rows) {

      Taf t;
      try {
        // valid till time like 2024-01-27T18:26:00Z in row[5]
        DateTime time = DateTime.parse(row[5]).toUtc();
        t = Taf(row[1], time, row[0].toString().replaceAll(" FM", "\nFM"));
        tafs.add(t);
      }
      catch(e) {
        continue;
      }
    }
    WeatherDatabaseHelper.db.addTafs(tafs);
  }
}

