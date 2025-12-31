
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:avaremp/instruments/instrument_list.dart';
import 'package:avaremp/utils/path_utils.dart';
import 'package:avaremp/storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'gps.dart';

class GpsRecorder {
  TrackPoint _last;
  final List<TrackPoint> _points;

  GpsRecorder() :
    _last = TrackPoint(
      coordinate: LatLng(0,0),
      altitude: 0,
      heading: 0,
      speed: 0,
      time: DateTime.fromMillisecondsSinceEpoch(0),
    ),
    _points = [];

  static String _createKml({
    required List<TrackPoint> points,
    String name = 'AvareX Flight',
  }) {
    final buffer = StringBuffer();

    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
    buffer.writeln('<Document>');
    buffer.writeln('<name>$name</name>');

    // Path LineString
    buffer.writeln('<Placemark>');
    buffer.writeln('<name>$name Path</name>');
    buffer.writeln('<LineString>');
    buffer.writeln('<tessellate>1</tessellate>');
    buffer.writeln('<altitudeMode>absolute</altitudeMode>');
    buffer.writeln('<coordinates>');

    for (final p in points) {
      buffer.writeln(
        '${p.coordinate.longitude},${p.coordinate.latitude},${p.altitude}',
      );
    }

    buffer.writeln('</coordinates>');
    buffer.writeln('</LineString>');
    buffer.writeln('</Placemark>');

    // Individual points with timestamp
    for (int i = 0; i < points.length; i++) {
      final p = points[i];

      buffer.writeln('<Placemark>');
      buffer.writeln('<name>Point ${i + 1}</name>');

      // Time
      buffer.writeln('<TimeStamp>');
      buffer.writeln('<when>${p.time.toUtc().toIso8601String()}</when>');
      buffer.writeln('</TimeStamp>');

      // Location
      buffer.writeln('<Point>');
      buffer.writeln('<altitudeMode>absolute</altitudeMode>');
      buffer.writeln(
        '<coordinates>${p.coordinate.longitude},${p.coordinate.latitude},${p.altitude}</coordinates>',
      );
      buffer.writeln('</Point>');

      // Metadata
      buffer.writeln('<ExtendedData>');
      buffer.writeln(
          '<Data name="heading"><value>${p.heading}</value></Data>');
      buffer.writeln(
          '<Data name="speed"><value>${p.speed}</value></Data>');
      buffer.writeln('</ExtendedData>');

      buffer.writeln('</Placemark>');
    }

    buffer.writeln('</Document>');
    buffer.writeln('</kml>');

    return buffer.toString();
  }

  void add(Position position) {

    double speed = position.speed * Storage().units.mpsTo;
    double altitude = position.altitude;
    double heading = position.heading;
    bool recordPoint = false;
    LatLng coordinate = Gps.toLatLng(position);

    if(speed < 3) {
      // Not going fast enough yet to record
      return;
    }

    if(DateTime.now().difference(_last.time).abs() < const Duration(seconds: 1)) {
      return; // too fast if quicker than 1 second
    }

    // If the speed has changed more than 5 knots
    if ((speed - _last.speed).abs() > 5) {
      recordPoint = true;
    }

    // If the altitude is 30 meters or greater different
    if((altitude - _last.altitude).abs() > 30) {
      recordPoint = true;
    }

    // If the bearing is 15 degrees or more different - that's 24 samples per 360 turn
    if(InstrumentList.angularDifference(heading, _last.heading) > 15) {
      recordPoint = true;
    }

    // If the time of the last point and now is greater than 30 seconds
    if(DateTime.now().difference(_last.time).abs() > const Duration(seconds: 30)) {
      recordPoint = true;
    }

    // if distance has changed by 0.01 nm
    if(GeoCalculations().calculateDistance(_last.coordinate, coordinate) > 0.01) {
      recordPoint = true;
    }

    // After all those tests, if nothing says to record, then get out of here
    if (!recordPoint) {
      return;
    }

    _last = TrackPoint(coordinate: Gps.toLatLng(position), altitude: altitude, speed: speed, heading: heading, time: DateTime.now());
    _points.add(_last);
  }

  String getKml() {
    return _createKml(points: _points);
  }

  List<LatLng> getPoints() {
    if(_points.isEmpty) {
      return [LatLng(0, 0)];
    }
    return _points.map((e) => e.coordinate).toList();
  }

  Future<String?> saveKml() async {
    String data = getKml();
    return await PathUtils.writeTrack(Storage().dataDir, data);
  }
}

class TrackPoint {
  final LatLng coordinate;
  final double altitude; // meters
  final double heading;  // degrees
  final double speed;    // m/s, knots, etc.
  final DateTime time;   // UTC

  TrackPoint({
    required this.coordinate,
    required this.altitude,
    required this.heading,
    required this.speed,
    required this.time,
  });
}
