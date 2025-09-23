import 'dart:typed_data';
import 'package:avaremp/app_log.dart';
import 'package:avaremp/constants.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/data/weather_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/weather.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:html/parser.dart' as html show parse;
import 'package:http/http.dart' as http;

import 'notam.dart';

class NotamCache extends WeatherCache {

  NotamCache(super.url, super.dbCall);

  @override
  Future<void> parse(List<Uint8List> data, [String? argument]) async {

    if(null == argument) {
      return;
    }

    String? cookie;
    //@@___asa_password___@@
    final responseHttp = await http.post(Uri.parse("https://rfinder.asalink.net/login.php?cmd=login&uid=apps4av&pwd=@@___asa_password___@@"));
    if (responseHttp.statusCode == 200) {
      try {
        cookie = responseHttp.headers['set-cookie'];
      }
      catch(e) {
        AppLog.logMessage("ASA NOTAM cookie error $e");
      }
    }

    Map<String, String> headers = {};
    headers['Cookie'] = cookie ?? "";
    final response = await http.get(Uri.parse("https://rfinder.asalink.net/avionet_run.php?form_id=notam_inquiry&apt_icao_id=$argument"), headers: headers);
    if (response.statusCode == 200) {
      String data = response.body;

      // Parse HTML
      final document = html.parse(data);

      // Find all <tt> elements
      final ttElements = document.getElementsByTagName('tt');

      // Store results
      List<List<String>> allNotams = [];

      for (var tt in ttElements) {
        // Get raw HTML text of this <tt>
        final ttHtml = tt.innerHtml;

        // Regex to capture content between <b>E)</b> and <br>
        final regex = RegExp(r'<b>E\)</b>\s*(.*?)<br>', dotAll: true);
        final match = regex.firstMatch(ttHtml);

        if (match != null) {
          // Extracted text
          String content = match.group(1) ?? '';

          // Clean HTML tags if any remain
          content = content.replaceAll(RegExp(r'<[^>]*>'), '').trim();

          // Split into lines
          List<String> lines = content.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

          allNotams.add(lines);
        }
      }

      String all = "";
      if(allNotams.isNotEmpty) {
        all = allNotams.join("\n\n");
      }
      Notam notam = Notam(argument,
          DateTime.now().toUtc().add(
              const Duration(minutes: Constants.weatherUpdateTimeMin)),
          DateTime.now().toUtc(),
          Weather.sourceInternet, all);

      await WeatherDatabaseHelper.db.addNotam(notam);
    }
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

    String ll = Destination.toSexagesimal(airport.coordinate);

    Map<String, String> body = {
      "geoLatDegree": ll.substring(0, 3),
      "geoLatMinute": ll.substring(3, 5),
      "geoLatNorthSouth": ll.substring(7, 8),
      "geoLongDegree": ll.substring(9, 12),
      "geoLongMinute": ll.substring(12, 14),
      "geoLongEastWest": ll.substring(16, 17),
      "reportType": "Raw",
      "geoLatLongRadius": "20",
      "actionType": "latLongSearch",
      "submit": "View+NOTAMs",
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

