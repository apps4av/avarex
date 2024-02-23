import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:html/parser.dart';

class Notams {

  static Future<String?> get(String listOfAirports) async { // space separated list of airports
    String? ret;
    try {

      http.Response response = await http.post(
        Uri.parse("https://www.notams.faa.gov/dinsQueryWeb/queryRetrievalMapAction.do"),
        body: <String, String>{
          "retrieveLocId" : "KBOS",
          "reportType" : "Raw",
          "actionType" : "notamRetrievalByICAOs",
          "submit": "View+NOTAMSs",
        });

      // NOTAMS are in form <PRE></PRE>. Parse them.
      String data = utf8.decode(response.bodyBytes);
      var document = parse(data);
      var pres = document.getElementsByTagName("PRE");
      ret = pres.map((e) => e.text).toList().join("\n\n");
    }
    catch(e) {}
    return ret;

  }
}