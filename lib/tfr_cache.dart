import 'dart:convert';
import 'dart:typed_data';
import 'package:avaremp/tfr.dart';
import 'package:avaremp/weather_cache.dart';
import 'package:avaremp/weather_database_helper.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

import 'constants.dart';

class TfrCache extends WeatherCache {

  TfrCache(super.url, super.dbCall);

  final change = ValueNotifier<int>(0);

  @override
  Future<void> parse(Uint8List data) async {
    final List<Tfr> tfrs = [];
    String decoded = utf8.decode(data);

    // parse for https://tfr.faa.gov/save_pages/detail_4_6599.html
    RegExp exp = RegExp("save_pages/detail_[0-9]*_[0-9]*.html");

    Iterable<RegExpMatch> matches = exp.allMatches(decoded);
    List<String?> unique = matches.map((e) => e[0]).toSet().toList();
    for(String? match in unique) {
      if(null != match) {
        match = match.replaceAll(".html", ".xml");
      }
      else {
        continue;
      }
      String url = "https://tfr.faa.gov/$match";
      // now download each TFR
      http.Response response = await http.get(Uri.parse(url));
      decoded = utf8.decode(response.bodyBytes);
      // parse XML XML

      DateTime time = DateTime.now().toUtc();
      time = time.add(const Duration(minutes: Constants.weatherUpdateTimeMin)); // they update every minute but that's too fast

      final Iterable<XmlElement> tfrGroups;
      try {
        final document = XmlDocument.parse(decoded);
        tfrGroups = document.findAllElements("TFRAreaGroup");
      }
      catch(e) {
        continue; // no shape exists for this TFR
      }
      for(var tfrGroup in tfrGroups) {

        try {
          var area = tfrGroup.findAllElements("abdMergedArea").first;
          var latitudes = area.findAllElements("geoLat");
          var longitudes = area.findAllElements("geoLong");
          var upper = tfrGroup.findAllElements("valDistVerUpper");
          var lower = tfrGroup.findAllElements("valDistVerLower");
          var effective = tfrGroup.findAllElements("dateEffective");
          var expire = tfrGroup.findAllElements("dateExpire");
          var code = tfrGroup.findAllElements("codeId");

          String info = "";
          info += effective.isNotEmpty ? "In Effect Starting ${effective.first.innerText}\n" : "";
          info += expire.isNotEmpty ? "Expires ${expire.first.innerText}\n" : "";
          info += upper.isNotEmpty ? "Upper Altitude ${upper.first.innerText}\n" : "";
          info += lower.isNotEmpty ? "Lower Altitude ${lower.first.innerText}\n" : "";

          List<LatLng> ll = [];
          for(int count = 0; count < latitudes.length; count++) {
            String latitude = latitudes.elementAt(count).innerText;
            if(latitude.endsWith("N")) {
              latitude = latitude.replaceAll("N", "");
            }
            if(latitude.endsWith("S")) {
              latitude = "-${latitude.replaceAll('S', '')}";
            }
            String longitude = longitudes.elementAt(count).innerText;
            if(longitude.endsWith("E")) {
              longitude = longitude.replaceAll("E", "");
            }
            if(longitude.endsWith("W")) {
              longitude = "-${longitude.replaceAll('W', '')}";
            }
            ll.add(LatLng(double.parse(latitude), double.parse(longitude)));
          }

          Tfr tfr = Tfr(code.first.toString(), time, info, ll);
          tfrs.add(tfr);

        }
        catch(e) {
          continue;
        }

      }

    }
    WeatherDatabaseHelper.db.addTfrs(tfrs);
  }

  @override
  Future<void> initialize() async {
    super.initialize().then((value) => (change.value++));
  }

}

