import 'dart:convert';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/storage.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
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

  static Widget makeChart(BuildContext context, List<double> data) {
    return CustomPaint(painter: AltitudePainter(context, data),);
  }
}



class AltitudePainter extends CustomPainter {

  final BuildContext context;
  final List<double> data;
  double maxAltitude = 0;
  double minAltitude = 0;
  final double altitudeOfPlan = double.parse(Storage().route.altitude);
  List<Destination> destinations = Storage().route.getAllDestinations();
  int length = 0;
  final _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round
    ..color = Colors.green;

  AltitudePainter(this.context, this.data) {
    if(data.isEmpty) {
      return;
    }
    maxAltitude = data.reduce((value, element) => value > element ? value : element);
    minAltitude = data.reduce((value, element) => value < element ? value : element);
    // make minimum altitude in increments of 100
    minAltitude = (minAltitude / 100).floor() * 100;
    // make maximum altitude in increments of 100
    maxAltitude = (maxAltitude / 100).ceil() * 100;
    length = data.length;
  }

  @override
  void paint(Canvas canvas, Size size) {
    Color textColor = Colors.white;
    Color textBackColor = Colors.black;
    if(length == 0) {
      return;
    }
    double width = size.width;
    double height = size.height;
    double step = width / (length - 1);
    double stepY = height / (maxAltitude - minAltitude);

    _paint.color = Colors.grey;
    canvas.drawRect(Rect.fromLTRB(0, 0, width, height), _paint);

    List<Offset> points = [];
    for (int i = 0; i < length; i++) {
      double x = i * step;
      double y = height - (data[i] - minAltitude) * stepY;
      points.add(Offset(x, y));
    }

    double topAltitude = height - (altitudeOfPlan - minAltitude) * stepY;
    for (int i = 0; i < length - 1; i++) {
      // all areas into terrain mark red
      _paint.color = topAltitude < points[i].dy || topAltitude < points[i + 1].dy ? Colors.blue : Colors.orange;
      canvas.drawLine(points[i], points[i + 1], _paint);
    }

    // label text
    TextSpan span = TextSpan(style: TextStyle(fontSize: 10, color: textColor, backgroundColor: textBackColor), text: maxAltitude.round().toString().padLeft(5, " "));
    TextPainter tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, const Offset(0, 0));

    span = TextSpan(style: TextStyle(fontSize: 10, color: textColor, backgroundColor: textBackColor), text: minAltitude.round().toString().padLeft(5, " "));
    tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, Offset(0, height - tp.height));

    // choose destinations based on width with one destination per 1/5 screen pixels
    double xx = 0;
    // draw no more than 5 points on screen
    double last = -width / 5;
    for(int index = 0; index < destinations.length; index++) {
      if(destinations[index].calculations == null) {
        continue;
      }
      double inc = destinations[index].calculations!.distance * step;
      xx += inc;
      if(xx - last > width / 5) {
        last = xx;
        TextSpan span = TextSpan(style: TextStyle(fontSize: 10, color: textColor, backgroundColor: textBackColor),
            text: destinations[index].locationID);
        TextPainter tp = TextPainter(text: span,
            textAlign: TextAlign.left,
            textDirection: TextDirection.ltr);
        tp.layout();
        tp.paint(canvas, Offset(xx, height - tp.height));
      }
    }
  }

  @override
  bool shouldRepaint(oldDelegate) => false;


}
