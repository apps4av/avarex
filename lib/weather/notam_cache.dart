import 'dart:convert';
import 'dart:typed_data';
import 'package:avaremp/weather/weather.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;

import '../constants.dart';
import '../storage.dart';
import 'notam.dart';

class NotamCache extends WeatherCache {

  NotamCache(super.url, super.dbCall);

  @override
  Future<void> parse(Uint8List data, [String? argument]) async {

    if(null == argument) {
      return;
    }

    String ret = utf8.decode(data);
    var document = parser.parse(ret);
    var pres = document.getElementsByTagName("PRE");
    String notamText = pres.map((e) => e.text).toList().join("\n\n");

    DateTime time = DateTime.now().toUtc();
    // observation time like 2024-01-27T18:26:00Z in row[2]
    time = time.add(const Duration(minutes: Constants.weatherUpdateTimeMin)); // they update every minute but that's too fast
    Notam notam = Notam(argument, time, notamText);

    Storage().weatherRealmHelper.addNotam(notam);
  }

  // Download and parse, override because this is a POST
  @override
  Future<void> download([String? argument]) async {
    if(null == argument) {
      return;
    }

    try {
      http.Response response = await http.post(
          Uri.parse(url),
          body: <String, String>{
            "retrieveLocId": argument,
            "reportType": "Raw",
            "actionType": "notamRetrievalByICAOs",
            "submit": "View+NOTAMSs",
          });
      await parse(response.bodyBytes, argument);
    }
    catch(e) {}
    await initialize();
  }

  // wait till we get it either from cache or from internet
  Future<Weather?> getSync(String? station) async {
    Weather? w = super.get(station);
    if(null == w) {
      // if not found, download
      await download(station);
      w = super.get(station);
    }
    return w;
  }
}

