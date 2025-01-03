import 'dart:convert';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/storage.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';


class AltitudeProfile {

  // this creates a local cache
  static Future<List<double>> getAltitudeProfile(List<LatLng> points) async {
    // return as many as points
    List<double> altitudes = List.generate(points.length, (index) => -double.infinity);
    // find all elevations stored in the database
    List<double?> ee = await UserDatabaseHelper.db.getElevations(points);
    for(int i = 0; i < ee.length; i++) {
      if(ee[i] != null) {
        // take what we have, ask for the rest from internet
        altitudes[i] = ee[i]!;
      }
    }

    bool store = false;
    List<Map<String, double>> locations = [];
    for (int i = 0; i < ee.length; i++) {
      if(ee[i] != null) {
        continue;
      }
      store = true;
      locations.add({"latitude": points[i].latitude, "longitude": points[i].longitude});
    }

    if(store) { // new data needed
      String query = "https://api.open-elevation.com/api/v1/lookup";
      var response = await http.post(Uri.parse(query), body: jsonEncode({"locations": locations}));
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        int index = 0;
        for (int i = 0; i < ee.length; i++) {
          if(ee[i] != null) {
            continue;
          }
          if(index >= data['results'].length) {
            // something wrong. server responded with less data than requested
            continue;
          }
          altitudes[i] = (data['results'][index]['elevation'] * Storage().units.mToF);
          index++;
        }
        // new data, store
        await UserDatabaseHelper.db.insertElevations(points, altitudes);
      }
    }
    return altitudes;
  }
}



