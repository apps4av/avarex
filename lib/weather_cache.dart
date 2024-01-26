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
    parse(response.body);
    await initialize();
    _isDownloading = false;
  }

  Weather? get(String? station) {

    if(station == null) {
      return null; // something wrong
    }
    Weather? w = _map[station];

    // if not found or if found and expired, try downloading and return null
    if(w == null) {
      download();
      return(null);
    }
    if(w.isExpired()) {
      download();
      return(null);
    }
    return w;
  }

  void parse(dynamic data) {
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
    WeatherCache w = WindsCache("https://aviationweather.gov/cgi-bin/data/windtemp.php?region=all&fcst=06&level=low",
        WeatherDatabaseHelper.db.getAllWindsAloft);
    return w;
  }

}