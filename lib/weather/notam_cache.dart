import 'dart:convert';
import 'dart:typed_data';
import 'package:avaremp/constants.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/data/weather_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/weather.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;

import 'notam.dart';

class NotamCache extends WeatherCache {

  NotamCache(super.url, super.dbCall);

  /// Returns the inner text of <event:formattedText> (decoded from entities),
  /// or null if not found.
  String? extractFormattedText(String xmlString) {
    // Parse the XML document
    final doc = xml.XmlDocument.parse(xmlString);

    // Find all elements named "formattedText" (namespace prefix doesn't matter)
    final formattedElements = doc.findAllElements('event:formattedText');

    if (formattedElements.isEmpty) {
      return null;
    }

    final formatted = formattedElements.first;

    // Get all text within the formattedText element (including inner <html:div>)
    // xml package will decode &lt;pre&gt; to <pre>, etc.
    final text = formatted.innerText
        .replaceAll(RegExp("<[^>]+>"), " ")
        .replaceAll("\n", " ");

    return text.trim();
  }

  @override
  Future<void> parse(List<Uint8List> data, [String? argument]) async {

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

    try {

      // Store results
      List<String> allNotams = [];

      // ================================
      // 1. Get OAuth access token
      // ================================
      final tokenUrl = Uri.parse(
          "https://api-staging.cgifederal-aim.com/v1/auth/token");

      // Build Basic Auth header
      final creds = base64Encode(utf8.encode(
          "@@__faa_nms_api_client_id_secret__@@"));

      final tokenResponse = await http.post(
        tokenUrl,
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "Authorization": "Basic $creds",
        },
        body: {
          "grant_type": "client_credentials",
        },
      );

      if (tokenResponse.statusCode != 200) {
        return;
      }

      final tokenJson = jsonDecode(tokenResponse.body);
      final accessToken = tokenJson["access_token"];

      // ================================
      // 2. Use access token to call NOTAM API
      // ================================
      final notamUrl = Uri.parse(
          "https://api-staging.cgifederal-aim.com/nmsapi/v1/notams?location=${airport.locationID}"
      );

      final notamResponse = await http.get(
        notamUrl,
        headers: {
          "Authorization": "Bearer $accessToken",
          "nmsResponseFormat": "AIXM",
        },
      );

      if (notamResponse.statusCode != 200) {
        return;
      }

      // this is ugly, parse is not used for NOTAMs

      final data = jsonDecode(notamResponse.body)["data"]["aixm"];
      for (var item in data) {
        String? txt = extractFormattedText(item);
        if (null != txt) {
          allNotams.add(txt);
        }
      }

      String all = "Unable to get NOTAMs.";
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
    catch(e) {
      if(Storage().gpsInternal) {
        // no internet if GPS external, so do not log errors
        Storage().setException("Unable to download NOTAM: $e");
      }
      return;
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

