import 'dart:math';

import 'destination.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/metar.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class Airport {

  static Future<LatLng?> findCoordinatesFromRunway(AirportDestination da, String runwayName) async {
    // runway
    // find runway if not a fix or a nav
    LatLng? ll;
    RegExp regexp = RegExp(r"RW(?<runway>\d+[LRC]?)");
    RegExpMatch? runway = regexp.firstMatch(runwayName);
    if(null == runway) {
      return ll;
    }
    String? name = runway.namedGroup("runway");
    if(name == null) {
      return ll;
    }
    for (var r in da.runways) {
      try {
        if (name == r['LEIdent']) {
          double lat = double.parse(r['LELatitude']);
          double lon = double.parse(r['LELongitude']);
          ll = LatLng(lat, lon);
          break;
        }
        if (name == r['HEIdent']) {
          double lat = double.parse(r['HELatitude']);
          double lon = double.parse(r['HELongitude']);
          ll = LatLng(lat, lon);
          break;
        }
      }
      catch(e) {
        continue;
      }
    }
    return ll;
  }

  static ListView parseFrequencies(AirportDestination airport) {

    List<Map<String, dynamic>> frequencies = airport.frequencies;
    List<Map<String, dynamic>> awos = airport.awos;

    List<String> atis = [];
    List<String> clearance = [];
    List<String> ground = [];
    List<String> tower = [];
    List<String> automated = [];

    for(Map<String, dynamic> f in frequencies) {
      try {
        // Type, Freq
        String type = f['Type'];
        String freq = f['Freq'];
        if (type == 'LCL/P') {
          tower.add(freq);
        }
        else if (type == 'GND/P') {
          ground.add(freq);
        }
        else if (type.contains('ATIS')) {
          atis.add(freq);
        }
        else if (type == 'CD/P' || type.contains('CLNC')) {
          clearance.add(freq);
        }
        else {
          continue;
        }
      }
      catch(e) {}
    }

    for(Map<String, dynamic> f in awos) {
      try {
        // Type, Freq
        automated.add("${f['Type']} ${f['Frequency1']} ${f['Telephone1']}");
      }
      catch(e) {}
    }

    ListView view = ListView(children: [
      if(tower.isNotEmpty) ListTile(leading: const Icon(Icons.cell_tower), title: const Text("Tower"), subtitle: Text(tower.join("\n"))),
      if(ground.isNotEmpty) ListTile(leading: const Icon(Icons.airport_shuttle), title: const Text("Ground"), subtitle: Text(ground.join("\n"))),
      if(atis.isNotEmpty) ListTile(leading: const Icon(Icons.thermostat), title: const Text("ATIS"), subtitle: Text(atis.join("\n"))),
      if(clearance.isNotEmpty) ListTile(leading: const Icon(Icons.perm_identity), title: const Text("Clearance"), subtitle: Text(clearance.join("\n"))),
      if(airport.ctaf.isNotEmpty) ListTile(leading: const Icon(Icons.radio), title: const Text("CTAF"), subtitle: Text(airport.ctaf)),
      if(airport.unicom.isNotEmpty) ListTile(leading: const Icon(Icons.radio), title: const Text("UNICOM"), subtitle: Text(airport.unicom)),
      if(automated.isNotEmpty) ListTile(leading: const Icon(Icons.air), title: const Text("Automated"), subtitle: Text(automated.join("\n"))),
    ]);
    return view;
  }

  static Widget runwaysWidget(AirportDestination airport, double dimensions, BuildContext context) {
    return CustomPaint(size: Size(dimensions, dimensions), painter: RunwayPainter(airport, context));
  }

  static List<MapRunway> getRunwaysForMap(AirportDestination destination) {
    GeoCalculations geo = GeoCalculations();
    // pairs of two where a line will be drawn for runway, first is runway threshold, second 10 miles out
    List<MapRunway> runways = [];
    for(Map<String, dynamic> r in destination.runways) {
      double lat;
      try {
        lat = double.parse(r['LELatitude']);
      }
      catch (e) {
        lat = destination.coordinate.latitude;
      }
      double lon;
      try {
        lon = double.parse(r['LELongitude']);
      }
      catch (e) {
        lon = destination.coordinate.longitude;
      }
      double length;
      try {
        length = double.parse(r['Length']);
      }
      catch (e) {
        length = 1000;
      }
      double headingL;
      double headingH;

      try {
        headingL = double.parse(r['LEHeadingT']);
      }
      catch (e) {
        try {
          headingL =
              double.parse(r['LEIdent'].replaceAll(RegExp(r'[LCR]'), '')) * 10 - geo.getVariation(LatLng(lat, lon)); // remove L, R, C from it
        }
        catch (e) {
          continue; // give up, as we tried everything possible to find a runway
        }
      }
      headingH = headingL + 180;

      LatLng start = geo.calculateOffset(LatLng(lat, lon), MapRunway.lengthStart, headingL);
      LatLng end = geo.calculateOffset(start, MapRunway.lengthStart + length / 2000, headingL);
      bool leftPattern = r['HEPattern'] == 'Y' ? false : true;
      LatLng endNotch;
      if(leftPattern) {
        endNotch = geo.calculateOffset(end, 2, 90 + headingL);
      }
      else {
        endNotch = geo.calculateOffset(end, 2, -90 + headingL);
      }
      MapRunway rr = MapRunway(start, end, endNotch, r['HEIdent'], headingL);
      runways.add(rr);

      try {
        lat = double.parse(r['HELatitude']);
      }
      catch (e) {
        lat = destination.coordinate.latitude;
      }
      try {
        lon = double.parse(r['HELongitude']);
      }
      catch (e) {
        lon = destination.coordinate.longitude;
      }
      try {
        length = double.parse(r['Length']);
      }
      catch (e) {
        length = 1000;
      }
      start = geo.calculateOffset(LatLng(lat, lon), MapRunway.lengthStart, headingH);
      end = geo.calculateOffset(start, MapRunway.lengthStart + length / 2000, headingH);
      leftPattern = r['LEPattern'] == 'Y' ? false : true;
      if(leftPattern) {
        endNotch = geo.calculateOffset(end, 2, 90 + headingH);
      }
      else {
        endNotch = geo.calculateOffset(end, 2, -90 + headingH);
      }
      rr = MapRunway(start, end, endNotch, r['LEIdent'], headingH);
      runways.add(rr);

    }

    // calculate best runways based on wind direction
    double? windDirection;
    Metar? metar = Storage().metar.get(destination.locationID) as Metar?;
    double minWind = 0;
    int index = -1;
    if(metar != null) {
      windDirection = metar.getWindDirection();
      if(windDirection != null) {
        for(MapRunway runway in runways) {
          // wind component
          double speedComponent = sqrt(1 - cos((runway.heading - windDirection) * pi / 180.0));
          if(speedComponent > minWind) {
            minWind = speedComponent;
            index = runways.indexOf(runway);
          }
        }
      }
    }

    if(index != -1) {
      runways[index].best = true;
    }

    return runways;
  }
}

class MapRunway {
  static const double lengthStart = 4; // nm

  final LatLng start;
  final LatLng end;
  final String name;
  final LatLng endNotch;
  final double heading;
  bool best = false;
  MapRunway(this.start, this.end, this.endNotch, this.name, this.heading);
}

class RunwayPainter extends CustomPainter {

  AirportDestination airport;
  BuildContext context;

  RunwayPainter(this.airport, this.context);

  @override
  void paint(Canvas canvas, Size size) {

    List<Map<String, dynamic>> runways = airport.runways;

    double scale = size.width > size.height ? size.height : size.width;

    double maxLat = -180;
    double minLat = 180;
    double maxLon = -180;
    double minLon = 180;
    for(Map<String, dynamic> r in runways) {

      try {
        double leLat = double.parse(r['LELatitude']);
        double heLat = double.parse(r['HELatitude']);
        double leLon = double.parse(r['LELongitude']);
        double heLon = double.parse(r['HELongitude']);
        maxLat = leLat > maxLat ? leLat : maxLat;
        maxLat = heLat > maxLat ? heLat : maxLat;
        minLat = leLat < minLat ? leLat : minLat;
        minLat = heLat < minLat ? heLat : minLat;
        maxLon = leLon > maxLon ? leLon : maxLon;
        maxLon = heLon > maxLon ? heLon : maxLon;
        minLon = leLon < minLon ? leLon : minLon;
        minLon = heLon < minLon ? heLon : minLon;
      }
      catch (e) {}
    }

    Rect bounds = Rect.fromLTRB(minLon, maxLat, maxLon, minLat);
    double avg = max(bounds.width.abs(), bounds.height.abs());

    String info = "";

    //for each runway at this airport, draw the physical shape and then the data for each runway identifier
    for(Map<String, dynamic> r in runways) {

      double width = 0; // draw runways to width
      try {
        String w = r['Width'];
        width = double.parse(w);
      }
      catch (e) {
        width = 50;
      }
      width = width / 30;

      try {
        double leLat = double.parse(r['LELatitude']);
        double heLat = double.parse(r['HELatitude']);
        double leLon = double.parse(r['LELongitude']);
        double heLon = double.parse(r['HELongitude']);

        if(r['Length'] == "0") { // odd stuff like 0 length runways
          continue;
        }

        double apLat = airport.coordinate.latitude;
        double apLon = airport.coordinate.longitude;

        // adding this factor should cover all airport in US from center of the airport.
        double left = apLon - avg;
        double right = apLon + avg;
        double top = apLat + avg;
        double bottom = apLat - avg;

        // move down and to the side

        double px = scale / (left - right);
        double py = scale / (top - bottom);

        double lx = (left - leLon) * px;
        double ly = (top - leLat) * py;
        double hx = (left - heLon) * px;
        double hy = (top - heLat) * py;

        // draws the runway
        final paintLine = Paint()
          ..strokeWidth = width
          ..color = Colors.green.withOpacity(0.8); // runway color

        double offsetX = 0;
        double offsetY = 0;

        //calculate actual runway identifier headings
        double heHeading = pi/2 - atan2((leLat-heLat),(leLon-heLon));
        double leHeading = heHeading - pi;

        canvas.drawLine(Offset(lx + offsetX, ly + offsetY), Offset(hx + offsetX, hy + offsetY), paintLine);

        //create info string for low end runway identifier (1-17)
        String ident = "${r['LEIdent']} ";
        String pattern = r['LEPattern'] == 'Y' ? 'RP ' : '';
        String lights = r['LELights'].isEmpty ? "" : "${r['LELights']} ";
        String ils = r['LEILS'].isEmpty ? "" : "${r['LEILS']} ";
        String vgsi = r['LEVGSI'].isEmpty ? "" : "${r['LEVGSI']} ";
        TextSpan span = TextSpan(style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: scale / 64), text: ident);
        TextPainter tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
        tp.layout();
        canvas.save();
        canvas.translate(lx + offsetX, ly + offsetY);
        canvas.rotate(leHeading);
        tp.paint(canvas, Offset(-(tp.width / 2),0));
        canvas.restore();

        info += "$ident$pattern$lights$ils$vgsi\n";

        //create info string for high end runway identifier (18...36)
        ident = "${r['HEIdent']} ";
        pattern = r['HEPattern'] == 'Y' ? 'RP ' : '';
        lights = r['HELights'].isEmpty ? "" : "${r['HELights']} ";
        ils = r['HEILS'].isEmpty ? "" : "${r['HEILS']} ";
        vgsi = r['HEVGSI'].isEmpty ? "" : "${r['HEVGSI']} ";
        span = TextSpan(style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: scale / 64), text: ident);
        tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
        tp.layout();
        canvas.save();
        canvas.translate(hx + offsetX, hy + offsetY);
        canvas.rotate(heHeading);
        tp.paint(canvas, Offset(-(tp.width / 2),0));
        canvas.restore();
        info += "$ident$pattern$lights$ils$vgsi\n";
        info += "  ${r['Length']}x${r['Width']} ${r['Surface']}\n\n";
      }
      catch(e) {}
    }
    TextSpan span = TextSpan(style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: scale / 64), text: info);
    TextPainter tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, Offset(10, scale.toInt() / 4))  ;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
  return false;
  }
}
