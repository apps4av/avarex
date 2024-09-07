import 'dart:convert';
import 'dart:typed_data';
import 'package:avaremp/weather/tfr.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

import '../constants.dart';
import '../storage.dart';

class TfrCache extends WeatherCache {

  TfrCache(super.url, super.dbCall);

  @override
  Future<void> parse(Uint8List data, [String? argument]) async {
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

      // how many points each group can have
      int gCount = 0;

      for(var tfrGroup in tfrGroups) {

        final Iterable<XmlElement> scheduledGroups;

        String upper = "Check NOTAMs";
        String lower = "Check NOTAMs";
        List<String> effectiveGroup = [];
        List<String> expireGroup = [];
        try {
          upper = tfrGroup.findAllElements("valDistVerUpper").first.innerText.toString();
        }
        catch(e) {}
        try {
          lower = tfrGroup.findAllElements("valDistVerLower").first.innerText.toString();
        }
        catch(e) {}
        try {
          scheduledGroups = tfrGroup.findAllElements("ScheduleGroup");
          for(var scheduledGroup in scheduledGroups) {
            effectiveGroup.add(scheduledGroup.findAllElements("dateEffective").first.innerText.toString());
            expireGroup.add(scheduledGroup.findAllElements("dateExpire").first.innerText.toString());
          }
        }
        catch(e) {}
        if(effectiveGroup.isEmpty || expireGroup.isEmpty) {
          effectiveGroup = ["2000-01-01T00:00:00"];
          expireGroup = ["2100-01-01T00:00:00"];
        }

        try {
          var area = tfrGroup.findAllElements("abdMergedArea").first;
          var latitudes = area.findAllElements("geoLat");
          var longitudes = area.findAllElements("geoLong");
          var code = tfrGroup.findAllElements("codeId").first.innerText;

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

          // cannot draw this TFR
          if(ll.isEmpty) {
            continue;
          }

          // add each TFR for a given date/time as a separate TFR
          for(int count = effectiveGroup.length - 1; count >= 0; count--) { // draw last first so first can be drawn on top
            String effective = effectiveGroup[count];
            String expire = expireGroup[count];
            // parse date (UTC
            DateTime startsDt = DateTime.parse(effective);
            DateTime endsDt = DateTime.parse(expire);

            Tfr tfr = Tfr(
                "$url@$code$gCount",
                time,
                ll,
                upper.toString(),
                lower.toString(),
                startsDt.millisecondsSinceEpoch,
                endsDt.millisecondsSinceEpoch,
                gCount % ll.length);
            tfrs.add(tfr);
            gCount = gCount + 1;
          }
          // this separates duplicate with different times TFRs labels so all can be shown
        }
        catch(e) {
          // no coordinates
          continue;
        }
      }
    }
    Storage().realmHelper.addTfrs(tfrs);
  }
}

