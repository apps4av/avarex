import 'dart:typed_data';

import 'package:avaremp/metar_cache.dart';
import 'package:avaremp/taf_cache.dart';
import 'package:avaremp/tfr_cache.dart';
import 'package:avaremp/weather.dart';
import 'package:avaremp/weather_database_helper.dart';
import 'package:avaremp/winds_cache.dart';
import 'package:http/http.dart' as http;

class WeatherCache {

  final Map<String, Weather> _map = {};
  bool _isDownloading = false;
  final String _url;
  final Future<List<Weather>>Function() _dbCall;

  WeatherCache(this._url, this._dbCall) {
    initialize();
  }

  // Download and parse
  Future<void> download() async {

    // do not start download if one already happening
    if(_isDownloading) {
      return;
    }
    _isDownloading = true;
    http.Response response = await http.get(Uri.parse(_url));
    await parse(response.bodyBytes);
    await initialize();
    _isDownloading = false;
  }

  Weather? get(String? station) {

    if(station == null) {
      return null; // something wrong
    }
    Weather? w = _map[station];

    // if not found or if found and expired, return null
    if(w == null) {
      return(null);
    }
    if(w.isExpired()) {
      download();
    }
    return w;
  }

  List<Weather> getAll() {
    return _map.values.toList();
  }

  Future<void> parse(Uint8List data) async {
    // override this or nothing happens
    throw UnimplementedError();
  }

  Future<void> initialize() async {
    List<Weather> elements = await _dbCall();
    // load everything in cache map from database
    for(Weather element in elements) {
      _map[element.station] = element;
    }
  }

  static WeatherCache make(Type type) {

    if(type == MetarCache) {
      MetarCache cache = MetarCache("https://aviationweather.gov/data/cache/metars.cache.csv.gz",
          WeatherDatabaseHelper.db.getAllMetar);
      return cache;
    }
    else if(type == TafCache) {
      TafCache cache = TafCache("https://aviationweather.gov/data/cache/tafs.cache.csv.gz",
          WeatherDatabaseHelper.db.getAllTaf);
      return cache;
    }
    else if(type == WindsCache) {
      // default
      WeatherCache cache = WindsCache(
          "https://aviationweather.gov/cgi-bin/data/windtemp.php?region=all&fcst=06&level=low",
          WeatherDatabaseHelper.db.getAllWindsAloft);
      return cache;
    }
    else if(type == TfrCache) {
      // default
      WeatherCache cache = TfrCache(
          "https://tfr.faa.gov/tfr2/list.html",
          WeatherDatabaseHelper.db.getAllTfr);
      return cache;
    }
    else {
      throw UnimplementedError();
    }
  }

}