import 'dart:math';

import 'package:avaremp/app_log.dart';
import 'package:avaremp/twilight_calculator.dart';

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
        AppLog.logMessage("Error parsing runway data for $name: $e");
      }
    }
    return ll;
  }

  static ListView parse(AirportDestination airport) {

    List<Map<String, dynamic>> frequencies = airport.frequencies;
    List<Map<String, dynamic>> awos = airport.awos;
    List<Map<String, dynamic>> runways = airport.runways;

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
        if (type.startsWith('LCL')) {
          tower.add("$freq $type");
        }
        else if (type.startsWith('GND')) {
          ground.add("$freq $type");
        }
        else if (type.contains('ATIS')) {
          atis.add(freq);
        }
        else if (type.startsWith('CD') || type.contains('CLNC')) {
          clearance.add("$freq $type");
        }
        else {
          continue;
        }
      }
      catch(e) {
        AppLog.logMessage("Error parsing frequency data: $e");
      }
    }

    for(Map<String, dynamic> f in awos) {
      try {
        // Type, Freq
        automated.add("${f['Type']} ${f['Frequency1']} ${f['Telephone1']}");
      }
      catch(e) {
        AppLog.logMessage("Error parsing AWOS data: $e");
      }
    }

    // runways

    String format(List<String> input) {
      if(input.isEmpty) {
        return "\n";
      }
      if(input.length > 1) {
        return input.join("\n");
      }
      return input[0];
    }

    String getRunwayInfo(Map<String, dynamic> r, String side, [MapRunway? mr]) {
      // process both ends of the runway separately, add pattern, ils, vgsi, lights, displaced threshold, length, and surface type
      String pattern = r['${side}Pattern'] == 'Y' ? 'Pattern: Right\n' : 'Pattern: Left\n';
      String elevation = r['${side}Elevation'].isEmpty ? "" : "Elevation: ${r['${side}Elevation']}\n";
      String ils = r['${side}ILS'].isEmpty ? "" : "ILS: ${r['${side}ILS']}\n";
      String vgsi = r['${side}VGSI'].isEmpty ? "" : "VGSI: ${r['${side}VGSI']}\n";
      String lights = r['${side}Lights'].isEmpty ? "" : "Lights: ${r['${side}Lights']}\n";
      String dt = r['${side}DT'].isEmpty ? "" : "Threshold: ${r['${side}DT']}\n";
      String info = "$pattern$elevation$ils$vgsi$lights$dt";
      if(mr != null) {
        // add head and cross wind components
        if(mr.headWind != null && mr.crossWind != null) {
          info += "Head Wind: ${mr.headWind!.toStringAsFixed(0)}\nCross Wind: ${mr.crossWind!.toStringAsFixed(0)}";
        }
      }

      return info;
    }

    String getRunwayInfoCommon(Map<String, dynamic> r) {
      // process both ends of the runway separately, add pattern, ils, vgsi, lights, displaced threshold, length, and surface type
      String length = r['Length'].isEmpty ? "" : "${r['Length']}x${r['Width']}";
      String surface = r['Surface'].isEmpty ? "" : "${r['Surface']}";
      String info = "$length $surface";
      return info;
    }

    String getRunwayIdent(Map<String, dynamic> r, String side) {
      String ident = r['${side}Ident'].isEmpty ? "" : "${r['${side}Ident']}";
      return ident;
    }

    DateTime? sunset;
    DateTime? sunrise;
    (sunrise, sunset) = TwilightCalculator.calculateTwilight(airport.coordinate.latitude, airport.coordinate.longitude);

    List<ListTile> rs = [];
    List<MapRunway> mr = Airport.getRunwaysForMap(airport);

    for(Map<String, dynamic> r in runways) {
      String identLE = getRunwayIdent(r, 'LE');
      String identHE = getRunwayIdent(r, 'HE');
      MapRunway? le;
      MapRunway? he;
      try {
        le = mr.reduce((value, element) =>
        value.name == identLE
            ? value
            : element);
        he = mr.reduce((value, element) =>
        value.name == identHE
            ? value
            : element);
      }
      catch(e) {
        AppLog.logMessage("No runway map for $identLE or $identHE: $e");
      }
      if(identLE.isNotEmpty) {
        rs.add(ListTile(
          leading: SizedBox(width: 64,
              child: CircleAvatar(backgroundColor: le != null && le.best ? Colors.green : Colors.purple,
                  child: Text(identLE,
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,))),
          title: Text(getRunwayInfoCommon(r)),
          subtitle: Text(getRunwayInfo(r, 'LE', le)),
        ));
      }
      if(identHE.isNotEmpty) {
        rs.add(ListTile(
          leading: SizedBox(width: 64,
              child: CircleAvatar(backgroundColor: he != null && he.best ? Colors.green : Colors.purple,
                  child: Text(identHE,
                    style: TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,))),
          title: Text(getRunwayInfoCommon(r)),
          subtitle: Text(getRunwayInfo(r, 'HE', he)),
        ));
      }
    }

    ListView view = ListView(children: [
      if(atis.isNotEmpty) ListTile(leading:           const SizedBox(width: 64, child: Text("ATIS", style: TextStyle(fontSize: 16))), title: Text(format(atis))),
      if(ground.isNotEmpty) ListTile(leading:         const SizedBox(width: 64, child: Text("TWR", style: TextStyle(fontSize: 16))), title: Text(format(tower))),
      if(ground.isNotEmpty) ListTile(leading:         const SizedBox(width: 64, child: Text("GND", style: TextStyle(fontSize: 16))),   title: Text(format(ground))),
      if(clearance.isNotEmpty) ListTile(leading:      const SizedBox(width: 64, child: Text("CLNC", style: TextStyle(fontSize: 16))), title: Text(format(clearance))),
      if(airport.ctaf.isNotEmpty) ListTile(leading:   const SizedBox(width: 64, child: Text("CTAF", style: TextStyle(fontSize: 16))), title: Text(format([airport.ctaf]))),
      if(airport.unicom.isNotEmpty) ListTile(leading: const SizedBox(width: 64, child: Text("UCOM", style: TextStyle(fontSize: 16))), title: Text(format([airport.unicom]))),
      if(automated.isNotEmpty) ListTile(leading:      const SizedBox(width: 64, child: Text("AUTO", style: TextStyle(fontSize: 16))), title: Text(format(automated))),
      for(ListTile t in rs) t,
      if(sunrise != null) ListTile(leading:           const SizedBox(width: 64, child: Text("SRISE", style: TextStyle(fontSize: 16))), title: Text("${sunrise.hour.toString().padLeft(2, '0')}:${sunrise.minute.toString().padLeft(2, '0')}Z")),
      if(sunset != null) ListTile(leading:            const SizedBox(width: 64, child: Text("SSET", style: TextStyle(fontSize: 16))), title: Text("${sunset.hour.toString().padLeft(2, '0')}:${sunset.minute.toString().padLeft(2, '0')}Z")),

    ]);
    return view;
  }

  static Widget runwaysWidget(AirportDestination airport, double width, double height, BuildContext context) {
    return CustomPaint(size: Size(width, height), painter: RunwayPainter(airport, context));
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
              double.parse(r['LEIdent'].replaceAll(RegExp(r'[LCRW]'), '')) * 10 + (destination.geoVariation?? 0); // remove L, R, C, W from it
        }
        catch (e) {
          AppLog.logMessage("Tried everything to find a runway heading: $e"); // give up, as we tried everything possible to find a runway
          continue; // give up, as we tried everything possible to find a runway
        }
      }
      headingH = (headingL + 180) % 360;

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

    // calculate best runways based on wind direction, also add speed components
    double? windDirection;
    double? windSpeed;
    Metar? metar = Storage().metar.get(destination.locationID) as Metar?;
    double minWind = 0;
    int index = -1;
    if(metar != null) {
      windDirection = metar.getWindDirection();
      windSpeed = metar.getWindSpeed();
      if(windDirection != null && windSpeed != null) {
        for(MapRunway runway in runways) {
          double angle = ((runway.heading + 180) % 360 - windDirection) * pi / 180;
          double headWind = cos(angle) * windSpeed;
          double crossWind = sin(angle) * windSpeed;
          if(headWind > minWind) {
            minWind = headWind;
            index = runways.indexOf(runway);
          }
          runway.headWind = headWind.roundToDouble();
          runway.crossWind = crossWind.roundToDouble();
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
  double? crossWind;
  double? headWind;
  MapRunway(this.start, this.end, this.endNotch, this.name, this.heading);
}

class RunwayPainter extends CustomPainter {

  AirportDestination airport;
  BuildContext context;

  RunwayPainter(this.airport, this.context);

  // Returns "E" for positive variations and "W" for negative ones, or nothing for 0/null
  static String getAirportVariationDirection(double? variation)
  {
      if(variation == null || variation == 0) {
        return '';
      }

      return variation > 0 ? 'E' : 'W';
  }

  //For a given runway identifier (e.g. 16) returns the expected runway heading (e.g. 160)
  //Rotates this expected runway heading by the runway's reported magnetic variation,
  //since the display of airport diagrams is always wrt true coordinates
  static double getRunwayHeadingFromIdent(String ident, double? variation)
  {
    if(ident.length > 2) {
      ident = ident.substring(0,2);
    }
    double runwayNumber = 0;
    try{
      runwayNumber = double.parse(ident);
    }
    on FormatException {
    //handle non-numeric runway identifiers
      switch(ident) {
        case 'N':
          runwayNumber = 0;
        case 'NE':
          runwayNumber = 4.5;
        case 'E':
          runwayNumber = 9;
        case 'SE':
          runwayNumber = 13.5;
        case 'S':
          runwayNumber = 18;
        case 'SW':
          runwayNumber = 22.5;
        case 'W':
          runwayNumber = 27;
        case 'NW':
          runwayNumber = 31.5;
      }
    }
    double runwayHeading = runwayNumber * 10 + (variation ?? 0);
    return runwayHeading;
  }

  //Attempts to query the appropriate runway color for the given runway object.
  //Returns grey if no surface is defined.
  static Color runwayColorFromSurface(Map<String, dynamic> r)
  {
    Color surfcolor = Colors.grey;
    try {
      String surf = r['Surface'];

      if(surf.length >= 5 && surf.substring(0,5) == 'WATER') {
        surfcolor = Colors.blue;
      }
      else {
        switch(surf.substring(0,4)) {
          case 'ASPH':
            surfcolor = Colors.grey.shade700;
          case 'CONC':
            surfcolor = Colors.grey;
          case 'TURF':
            surfcolor = Colors.green;
          case 'DIRT':
            surfcolor = Colors.brown;
          case 'SAND':
            surfcolor = Colors.amber.shade200;
        }
      }
    }
    catch (e) {
      AppLog.logMessage("Error parsing runway surface color: $e");
    }
    return surfcolor;
  }

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
      catch (e) {
        AppLog.logMessage("Error parsing runway data for diagram (lat, lon): $e");
      }
    }

    Rect bounds = Rect.fromLTRB(minLon, maxLat, maxLon, minLat);
    double avg = max(bounds.width.abs(), bounds.height.abs());

    String info = "";

    double apLat = airport.coordinate.latitude;
    double apLon = airport.coordinate.longitude;

    try {
      info = '${Destination.toSexagesimal(airport.coordinate)}\n'; // lat,lon uniformity with all other areas of the app.
      //report magnetic variation if provided, pad end with two line breaks either way (for runway printout)
      if(airport.geoVariation != null) {
        int mag = (airport.geoVariation ?? 0).abs().toInt();
        String dir = getAirportVariationDirection(airport.geoVariation);
        info += 'VAR $mag° $dir\n\n';
      }
      else {
        info += '\n';
      }
    }
    catch (e) {
      AppLog.logMessage("Error parsing airport data for diagram (var): $e");
    }

    //for each runway at this airport, draw the physical shape and then the data for each runway identifier
    for(Map<String, dynamic> r in runways) {

      double labelPosition = 0.5;
      final intersections = <double>[0];
      double leLat = 0;
      double heLat = 0;
      double leLon = 0;
      double heLon = 0;

      try {
        double y1 = leLat = double.parse(r['LELatitude']);
        double y2 = heLat = double.parse(r['HELatitude']);
        double x1 = leLon = double.parse(r['LELongitude']);
        double x2 = heLon = double.parse(r['HELongitude']);

        for(Map<String, dynamic> i in runways) {
          try {
          //get the endpoints of the potential intersecting runway
            double y3 = double.parse(i['LELatitude']);
            double y4 = double.parse(i['HELatitude']);
            double x3 = double.parse(i['LELongitude']);
            double x4 = double.parse(i['HELongitude']);


            double denominator = (x1 - x2)*(y3 - y4) - (y1 - y2)*(x3 - x4);
            if(denominator == 0) //the two runways are parallel, so they can't intersect (also rejects self)
            {
              continue;
            }
            double dividendT = (x1 - x3)*(y3 - y4) - (y1 - y3)*(x3 - x4);
            double dividendU = (x1 - x2)*(y1 - y3) - (y1 - y2)*(x1 - x3);
            double t = dividendT / denominator;
            double u = -dividendU / denominator;

            if((t >= 0 && t <= 1) && (u >=0 && u <= 1))
            {
              intersections.add(t);
            }
          }
          catch (e) {
            AppLog.logMessage("Error parsing runway data for diagram (intersection): $e");
          }
        }
      }
      catch (e) {
        AppLog.logMessage("Error parsing runway data for diagram (lat, lon): $e");
      }

      intersections.add(1);
      //sort intersections along low end -> high end, intersection order is not necessarily in runway listed order
      intersections.sort();

      //the start and end of the longest segment of the runway between intersections
      double l1 = intersections[0];
      double l2 = intersections[1];
      for(int i = 1; i < intersections.length - 1; i++) {
        if(intersections[i+1] - intersections[i] > l2-l1){
          l1 = intersections[i];
          l2 = intersections[i+1];
        }
      }
      labelPosition = 1 - (l1 + l2)/2;

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
        if(r['Length'] == "0") { // odd stuff like 0 length runways
          continue;
        }

        Color surfColor = runwayColorFromSurface(r);
        final paintLine = Paint()
          ..strokeWidth = width
          ..color = surfColor.withValues(alpha: 0.8);

        //runways with no runway position information and only one runway (can't guess the position of multiple runways)
        // (most private or small airports don't provide this information)
        if(leLat == 0 && heLat == 0 && leLon == 0 && heLon == 0 && runways.length == 1)
        {
          try {
              String runwayLength = r['Length'];
              String runwayID = r['LEIdent'];
              double heading = getRunwayHeadingFromIdent(runwayID, airport.geoVariation);
              avg = double.parse(runwayLength) / 6076 / 60; //ft -> minutes of lat/long (rounding up)
              leLon = -sin(heading * pi / 180) * avg/2;
              heLon = apLon - leLon;
              leLon = apLon + leLon;
              leLat = -cos(heading * pi / 180) * avg/2;
              heLat = apLat - leLat;
              leLat = apLat + leLat;
          }
          catch (e) {
            AppLog.logMessage("Error parsing runway data for diagram (runway length): $e");
          }
        }
        else if(leLat == 0 && heLat == 0 && leLon == 0 && heLon == 0 && runways.length > 1)
        {
          continue;
        }

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

        double offsetX = 0;
        double offsetY = 0;

        canvas.drawLine(Offset(lx + offsetX, ly + offsetY), Offset(hx + offsetX, hy + offsetY), paintLine);


        //calculate actual runway identifier headings
        double heHeading = pi/2 - atan2((leLat-heLat),(leLon-heLon));
        double leHeading = heHeading - pi;

        //create info string for low end runway identifier (1-17)
        String ident = "${r['LEIdent']} ";

        TextSpan span = TextSpan(style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: scale / 64), text: ident);
        TextPainter tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
        tp.layout();
        canvas.save();
        canvas.translate(lx + offsetX, ly + offsetY);
        canvas.rotate(leHeading);
        tp.paint(canvas, Offset(-(tp.width / 2),0));
        canvas.restore();

        String pattern = r['LEPattern'] == 'Y' ? 'RP ' : '';
        String lights = r['LELights'].isEmpty ? "" : "${r['LELights']} ";
        String ils = r['LEILS'].isEmpty ? "" : "${r['LEILS']} ";
        String vgsi = r['LEVGSI'].isEmpty ? "" : "${r['LEVGSI']} ";
        info += "\u25cf$ident$pattern$lights$ils$vgsi\n";

        //create info string for high end runway identifier (18...36)
        ident = "${r['HEIdent']} ";

        span = TextSpan(style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: scale / 64), text: ident);
        tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
        tp.layout();
        canvas.save();
        canvas.translate(hx + offsetX, hy + offsetY);
        canvas.rotate(heHeading);
        tp.paint(canvas, Offset(-(tp.width / 2),0));

        //runway length text
        canvas.rotate(pi/2); //rotate 90 degrees for runway length text
        canvas.translate(-sqrt(pow((ly-hy)*labelPosition, 2) + pow((lx-hx)*labelPosition, 2)), 0); //move canvas to center of runway

        String dimensions = "${r['Length']}x${r['Width']}\n";

        span = TextSpan(style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: scale / 96), text: dimensions);
        tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
        tp.layout();
        tp.paint(canvas, Offset(-tp.width/2,(-width-tp.height) / 2));
        canvas.restore();

        pattern = r['HEPattern'] == 'Y' ? 'RP ' : '';
        lights = r['HELights'].isEmpty ? "" : "${r['HELights']} ";
        ils = r['HEILS'].isEmpty ? "" : "${r['HEILS']} ";
        vgsi = r['HEVGSI'].isEmpty ? "" : "${r['HEVGSI']} ";

        info += "\u25cf$ident$pattern$lights$ils$vgsi\n";
        info += "  ${r['Length']}x${r['Width']} ${r['Surface']}\n\n";
      }
      catch(e) {
        AppLog.logMessage("Error parsing runway data for diagram (draw): $e");
      }
    }
    TextSpan span = TextSpan(style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: scale / 64), text: info);
    TextPainter tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, Offset(10, scale.toInt() / 4));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
  return false;
  }
}
