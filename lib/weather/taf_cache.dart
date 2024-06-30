import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/taf.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:csv/csv.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';

class TafCache extends WeatherCache {

  TafCache(super.url, super.dbCall);

  @override
  Future<void> parse(Uint8List data, [String? argument]) async {
    final List<int> decodedData = GZipCodec().decode(data);
    final List<Taf> tafs = [];
    String decoded = utf8.decode(decodedData, allowMalformed: true);
    List<List<dynamic>> rows = const CsvToListConverter().convert(decoded, eol: "\n");

    DateTime time = DateTime.now().toUtc();
    time = time.add(const Duration(minutes: Constants.weatherUpdateTimeMin)); // they update every minute but that's too fast

    for (List<dynamic> row in rows) {

      Taf t;
      try {
        double? latitude = double.tryParse(row[7].toString());
        double? longitude = double.tryParse(row[8].toString());
        if(latitude != null && longitude != null) {
          t = Taf(row[1], time, row[0].toString().replaceAll(" FM", "\nFM").replaceAll(" BECMG", "\nBECMG").replaceAll(" TEMPO", "\nTEMPO"), LatLng(latitude, longitude));
          tafs.add(t);
        }
      }
      catch(e) {
        continue;
      }
    }

    Storage().realmHelper.addTafs(tafs);
  }
}

