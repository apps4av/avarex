import 'dart:convert';
import 'dart:typed_data';
import 'package:avaremp/constants.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/data/weather_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/weather/weather.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import 'notam.dart';

class NotamCache extends WeatherCache {

  NotamCache(super.url, super.dbCall);

  @override
  Future<void> parse(List<Uint8List> data, [String? argument]) async {
    if(data.isEmpty) {
      return;
    }

    if(null == argument) {
      return;
    }

    // clean up the html file
    String ret = latin1.decode(data[0]);
    var document = html_parser.parse(ret);
    final anchors = document.querySelectorAll('TD');
    String retVal = "";

    bool start = false;
    for (var anchor in anchors) {

      String text = anchor.text.trim().replaceAll("\n"," ").replaceAll("\r"," ");

      if(text.startsWith("Data Current as of:")) {
        start = true;
      }

      if(!start) {
        continue;
      }

      if(text.contains("End of Report")) {
        break;
      }

      if(text.startsWith("No active NOTAMs")) {
        continue;
      }

      if(text.startsWith("Surrounding Airports")) {
        continue;
      }

      if(text.contains("Back to Top")) {
        continue;
      }
      if(text.isEmpty) {
        continue;
      }
      if(anchor.className == "textBlack12Bu") { // FAA puts notams in this class
        retVal = "$retVal **** $text ****\n\n";
      }
      else {
        retVal = "$retVal$text\n\n";
      }
    }



    DateTime time = DateTime.now().toUtc();
    // observation time like 2024-01-27T18:26:00Z in row[2]
    time = time.add(const Duration(minutes: Constants.weatherUpdateTimeMin)); // they update every minute but that's too fast
    Notam notam = Notam(argument, time, retVal);

    await WeatherDatabaseHelper.db.addNotam(notam);
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

    // 2025-03-13, bspatz: use airport-ID based search instead of lat/long; same DINS source
    //                     yields same NOTAM set, but longpress airport at top
    String _icaoID = airport.locationID;
    if (_icaoID[0] != "K") { _icaoID = "K" + _icaoID; }  // naive for US only?
    
    //String ll = Destination.toSexagesimal(airport.coordinate);
    Map<String, String> body = {
      //"geoLatDegree": ll.substring(0, 3),
      //"geoLatMinute": ll.substring(3, 5),
      //"geoLatNorthSouth": ll.substring(7, 8),
      //"geoLongDegree": ll.substring(9, 12),
      //"geoLongMinute": ll.substring(12, 14),
      //"geoLongEastWest": ll.substring(16, 17),
      //"reportType": "Raw",
      //"geoLatLongRadius": "20",
      //"actionType": "latLongSearch",
      
      "geoIcaoLocId": _icaoID,
      "reportType": "Raw",        // unused?  from top DINS page FORM; keeping for ZK
      "geoIcaoRadius": "20",      // could be Storage().settings.getStealthSetting("key-notam-radius", "20"),
      "actionType": "radiusSearch",
      
      "submit": "View+NOTAMs",
    };

    try {
      http.Response response = await http.post(
          Uri.parse(urls[0]),
          body: body);
      await parse([response.bodyBytes], argument);
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

