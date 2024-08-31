import 'dart:convert';
import 'dart:typed_data';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/weather/weather.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:http/http.dart' as http;

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

    // clean up the html file
    String ret = latin1.decode(data);
    List<String> parts = ret.split("<DIV");
    if(parts.length < 2) {
      return;
    }
    // remove headers
    ret = "<DIV${parts[1]}";
    parts = ret.split("DIV>");
    if(parts.length < 2) {
      return;
    }

    // add back to top
    ret = "<html lang='EN'><BODY><A name='top'></A>${parts[0]}DIV></BODY></html>";
    parts = ret.split("<TABLE>");
    if(parts.length < 2) {
      return;
    }
    // remove boilerplate
    parts.removeAt(1);
    ret = parts.join("<TABLE>");

    DateTime time = DateTime.now().toUtc();
    // observation time like 2024-01-27T18:26:00Z in row[2]
    time = time.add(const Duration(minutes: Constants.weatherUpdateTimeMin)); // they update every minute but that's too fast
    Notam notam = Notam(argument, time, ret);

    Storage().realmHelper.addNotam(notam);
  }

  // Download and parse, override because this is a POST
  @override
  Future<void> download([String? argument]) async {
    if(null == argument) {
      return;
    }

    // find lat/lon
    Destination? airport = await MainDatabaseHelper.db.findAirport(argument);
    if(null == airport) {
      return;
    }

    //43° 27' 11.75" N, 74° 30' 54.03" W
    RegExp exp = RegExp(r"([0-9]+). ([0-9]+). ([0-9.]+). ([NS]), ([0-9]+). ([0-9]+). ([0-9.]+). ([EW])");
    Match? match = exp.firstMatch(airport.coordinate.toSexagesimal());
    if(null == match) {
      return;
    }

    Map<String, String> body = {
      "geoLatDegree": match.group(1)!,
      "geoLatMinute": match.group(2)!,
      "geoLatNorthSouth": match.group(4)!,
      "geoLongDegree": match.group(5)!,
      "geoLongMinute": match.group(6)!,
      "geoLongEastWest": match.group(8)!,
      "reportType": "Raw",
      "geoLatLongRadius": "20",
      "actionType": "latLongSearch",
      "submit": "View+NOTAMs",
    };

    try {
      http.Response response = await http.post(
          Uri.parse(url),
          body: body);
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

