import 'dart:async';
import 'dart:typed_data';
import 'package:avaremp/data/weather_database_helper.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/unit_conversion.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;

import 'package:avaremp/weather/metar_cache.dart';
import 'package:avaremp/weather/taf_cache.dart';
import 'package:avaremp/weather/tfr_cache.dart';
import 'package:avaremp/weather/weather.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'airep_cache.dart';
import 'airsigmet_cache.dart';
import 'notam_cache.dart';


class WeatherCache {

  static const int minUpdateTime = 20000; // 20 seconds

  // stop from downloading weather continuously by storing when last time the weather was downloaded otherwise can get in download loop
  final Map<Type, DateTime> _lastDownload = {};
  final int _maxAge = 1 * 60 * 1000; // in ms

  final change = ValueNotifier<int>(0);

  final Map<String, Weather> _map = {};
  bool _isDownloading = false;
  final List<String> urls;
  final Future<List<Weather>>Function() _dbCall;
  int lastInsertTime = DateTime.now().millisecondsSinceEpoch;

  WeatherCache(this.urls, this._dbCall) {
    initialize();
  }

  static LatLng? parseAndValidateCoordinate(String latitude, String longitude) {
    try {
      double lat = double.parse(latitude);
      double lon = double.parse(longitude);
      if(UnitConversion.isLatitudeValid(lat) && UnitConversion.isLongitudeValid(lon)) {
        return LatLng(lat, lon);
      }
    }
    catch(e) {
    }
    return null;
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
        catch(e) {
          Storage().setException("Failed to download weather from Internet.");
        }
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
      if(_lastDownload.containsKey(w.runtimeType)) {
        if((DateTime.now().millisecondsSinceEpoch - _lastDownload[w.runtimeType]!.millisecondsSinceEpoch) < _maxAge) {
          return null;
        }
      }
      _lastDownload[w.runtimeType] = DateTime.now();
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
    if((DateTime.now().millisecondsSinceEpoch - lastInsertTime) > minUpdateTime) {
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
          [
            "https://aviationweather.gov/cgi-bin/data/windtemp.php?region=all&fcst=06&level=low", //CONUS Low (3k-39k)
            "https://aviationweather.gov/cgi-bin/data/windtemp.php?region=alaska&fcst=06&level=low", //AK Low (3k-39k)
            "https://aviationweather.gov/cgi-bin/data/windtemp.php?region=hawaii&fcst=06&level=low", //HI Low (1k-24k)
            "https://aviationweather.gov/cgi-bin/data/windtemp.php?region=other_pac&fcst=06&level=low", //US Pac Territories Low (1k-24k)

            "https://aviationweather.gov/cgi-bin/data/windtemp.php?region=all&fcst=12&level=low", //CONUS Low (3k-39k)
            "https://aviationweather.gov/cgi-bin/data/windtemp.php?region=alaska&fcst=12&level=low", //AK Low (3k-39k)
            "https://aviationweather.gov/cgi-bin/data/windtemp.php?region=hawaii&fcst=12&level=low", //HI Low (1k-24k)
            "https://aviationweather.gov/cgi-bin/data/windtemp.php?region=other_pac&fcst=12&level=low", //US Pac Territories Low (1k-24k)

            "https://aviationweather.gov/cgi-bin/data/windtemp.php?region=all&fcst=24&level=low", //CONUS Low (3k-39k)
            "https://aviationweather.gov/cgi-bin/data/windtemp.php?region=alaska&fcst=24&level=low", //AK Low (3k-39k)
            "https://aviationweather.gov/cgi-bin/data/windtemp.php?region=hawaii&fcst=24&level=low", //HI Low (1k-24k)
            "https://aviationweather.gov/cgi-bin/data/windtemp.php?region=other_pac&fcst=24&level=low", //US Pac Territories Low (1k-24k)

          ],
          WeatherDatabaseHelper.db.getAllWindsAloft);
      return cache;
    }
    else if(type == TfrCache) {
      // default
      WeatherCache cache = TfrCache(
          //["https://tfr.faa.gov/tfr2/list.html"],
          ["https://tfr.faa.gov/tfrapi/getTfrList"], // noticed/changed 2025-02-27
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
          [
            "https://aviationweather.gov/data/cache/gairmets.cache.xml.gz",
            "https://aviationweather.gov/data/cache/airsigmets.cache.csv.gz",
          ],
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
