import 'dart:typed_data';
import 'dart:convert';
import 'package:avaremp/constants.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/data/weather_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/weather.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:http/http.dart' as http;

import 'notam.dart';

class NotamCache extends WeatherCache {

  NotamCache(super.url, super.dbCall);

  @override
  Future<void> parse(List<Uint8List> data, [String? argument]) async {
    if(null == argument) {
      return;
    }

    // Store results
    List<String> allNotams = [];

    // JSON returned from Internet NOTAM API; grok it
    for (var notam in jsonDecode(utf8.decode(data[0]))['notamList']) {
      if (notam['traditionalMessage'] == null) continue;
      var text = notam['traditionalMessage'].replaceAll('\n', '');
      if (notam['featureName'] == "LTA") {  // Letters to Airmen: include?  hyperlink to reference?
        //continue;
        text = "[LTA] " + text + ", see " + notam['notamNumber'] + " (" + notam['comment'] + ")";
      } else {
        text = text.split(" ").sublist(2).join(" ");  // skip first 2 words, e.g. "!GNV 10/027"
      }
      allNotams.add(text);
    }

    String all = "Unable to get NOTAMs.";
    if(allNotams.isNotEmpty) {
      all = allNotams.join("\n");
    }
    Notam notam = Notam(argument,
        DateTime.now().toUtc().add(
            const Duration(minutes: Constants.weatherUpdateTimeMin)),
        DateTime.now().toUtc(),
        Weather.sourceInternet, all);
    await WeatherDatabaseHelper.db.addNotam(notam);
  }

  // Download and parse, override because this is a POST
  @override
  Future<void> download([String? argument]) async {
    if(null == argument) {
      return;
    }

    Destination? airport = await MainDatabaseHelper.db.findAirport(argument);
    if(null == airport) {
      return;
    }

    // find lat/lon
    //String ll = Destination.toSexagesimal(airport.coordinate);

    // 2025-11-25, bspatz: try NOTAMs via working FAA API, by locationID
    String _icaoID = airport.locationID;
    if (_icaoID.substring(0,1) == "K" && _icaoID.length == 4) { // more coverage
      _icaoID = _icaoID.substring(1) + ',' + _icaoID;
    }
    Map<String, String> body = {
      "searchType": "0",
      "sortColumns": "3 false", // column "Class" on notams.aim.faa.gov/notamSearch/nsapp.html
      "designatorsForLocation": _icaoID,
    };

    try {
      http.Response response = await http.post(
          Uri.parse(urls[0]),
          body: body);
      await parse([response.bodyBytes], argument);
    }
    catch(e) {
      Storage().setException("Unable to download NOTAM: $e");
    }
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
