import 'dart:async';
import 'dart:typed_data';

import 'package:avaremp/data/weather_database_helper.dart';
import 'package:avaremp/weather/metar_cache.dart';
import 'package:avaremp/weather/taf_cache.dart';
import 'package:avaremp/weather/tfr_cache.dart';
import 'package:avaremp/weather/weather.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;

import 'airep_cache.dart';
import 'airsigmet_cache.dart';
import 'notam_cache.dart';

class WeatherCache {

  final change = ValueNotifier<int>(0);

  final Map<String, Weather> _map = {};
  bool _isDownloading = false;
  final List<String> urls;
  final Future<List<Weather>>Function() _dbCall;
  int lastInsertTime = DateTime.now().millisecondsSinceEpoch;

  WeatherCache(this.urls, this._dbCall) {
    initialize();
  }

  // Download and parse
  Future<void> download([String? argument]) async {

    // do not start download if one already happening
    if(_isDownloading) {
      return;
    }
    _isDownloading = true;
    List<Uint8List> responses = [];
    for(String url in urls) {
        try {
          http.Response response = await http.get(Uri.parse(url));
          responses.add(response.bodyBytes);
        }
        catch(e) {}
    }
    await parse(responses);
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
      download(station);
    }
    return w;
  }

  List<Weather> getAll() {
    return _map.values.toList();
  }

  Weather? getQuick(String station) {
    return _map[station];
  }

  void put(Weather w) {
    _map[w.station] = w;
    if((DateTime.now().millisecondsSinceEpoch - lastInsertTime) > 5000) {
      change.value++;
      lastInsertTime = DateTime.now().millisecondsSinceEpoch;
    }
  }

  Future<void> parse(List<Uint8List> data, [String? argument]) async {
    // override this or nothing happens
    throw UnimplementedError();
  }

  Future<void> initialize() async {
    List<Weather> elements = await _dbCall();
    // load everything in cache map from database
    for(Weather element in elements) {
      if(!element.isVeryOld()) {
        _map[element.station] = element;
      }
    }
    change.value++;
  }

  static WeatherCache make(Type type) {

    if(type == MetarCache) {
      MetarCache cache = MetarCache(["https://aviationweather.gov/data/cache/metars.cache.csv.gz"],
          WeatherDatabaseHelper.db.getAllMetar);
      return cache;
    }
    else if(type == TafCache) {
      TafCache cache = TafCache(["https://aviationweather.gov/data/cache/tafs.cache.csv.gz"],
          WeatherDatabaseHelper.db.getAllTaf);
      return cache;
    }
    else if(type == WindsCache) {
      // default
      WeatherCache cache = WindsCache(
          ["https://aviationweather.gov/cgi-bin/data/windtemp.php?region=all&fcst=06&level=low",
           "https://aviationweather.gov/cgi-bin/data/windtemp.php?region=alaska&fcst=06&level=low",
           "https://aviationweather.gov/cgi-bin/data/windtemp.php?region=hawaii&fcst=06&level=low",
           "https://aviationweather.gov/cgi-bin/data/windtemp.php?region=other_pac&fcst=06&level=low"],
          WeatherDatabaseHelper.db.getAllWindsAloft);
      return cache;
    }
    else if(type == TfrCache) {
      // default
      WeatherCache cache = TfrCache(
          ["https://tfr.faa.gov/tfr2/list.html"],
          WeatherDatabaseHelper.db.getAllTfr);
      return cache;
    }
    else if(type == AirepCache) {
      // default
      WeatherCache cache = AirepCache(
          ["https://aviationweather.gov/data/cache/aircraftreports.cache.csv.gz"],
          WeatherDatabaseHelper.db.getAllAirep);
      return cache;
    }
    else if(type == AirSigmetCache) {
      // default
      WeatherCache cache = AirSigmetCache(
          ["https://aviationweather.gov/data/cache/airsigmets.cache.csv.gz"],
          WeatherDatabaseHelper.db.getAllAirSigmet);
      return cache;
    }
    else if(type == NotamCache) {
      // default
      WeatherCache cache = NotamCache(
          ["https://www.notams.faa.gov/dinsQueryWeb/latLongRadiusSearchMapAction.do"],
          WeatherDatabaseHelper.db.getAllNotams);
      return cache;
    }
    else {
      throw UnimplementedError();
    }
  }

}