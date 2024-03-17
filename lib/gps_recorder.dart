
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/instrument_list.dart';
import 'package:avaremp/path_utils.dart';
import 'package:avaremp/storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gpx/gpx.dart';
import 'package:latlong2/latlong.dart';

import 'gps.dart';

class GpsRecorder {

  TrackPosition? _last;
  Gpx gpx = newGpx();

  static Gpx newGpx() {
    Gpx gpx = Gpx();
    gpx.creator = 'AvareX';
    gpx.metadata = Metadata();
    gpx.metadata?.name = "AvareX Flight Path";
    gpx.metadata?.desc = "3-D Flight Position Data";
    gpx.metadata?.time = DateTime.now();
    gpx.wpts = [];
    return gpx;
  }

  void add(Position position) {

    double speed = position.speed * 1.94384;
    double altitude = position.altitude * 3.28084;
    double heading = position.heading;
    bool recordPoint = false;
    LatLng coordinate = Gps.toLatLng(position);

    _last ??= TrackPosition(coordinate, altitude, speed, heading, DateTime.now());

    TrackPosition last = _last!;

    if(speed < 3) {
      // Not going fast enough yet to record
      return;
    }

    if(DateTime.now().difference(last.time) < const Duration(seconds: 1)) {
      return; // too fast if quicker than 1 second
    }

    // If the speed has changed more than 5 knots
    if ((speed - last.speed) > 5) {
      recordPoint = true;
    }

    // If the altitude is 100' or greater different
    if((altitude - last.altitude) > 100) {
      recordPoint = true;
    }

    // If the bearing is 15 degrees or more different - that's 24 samples per 360 turn
    if(InstrumentList.angularDifference(heading, last.heading) > 15) {
      recordPoint = true;
    }

    // If the time of the last point and now is greater than 30 seconds
    if(DateTime.now().difference(last.time) > const Duration(seconds: 30)) {
      recordPoint = true;
    }

    // if distance has changed by 0.01 nm
    if(GeoCalculations().calculateDistance(last.coordinate, coordinate) > 0.01) {
      recordPoint = true;
    }

    // After all those tests, if nothing says to record, then get out of here
    if (!recordPoint) {
      return;
    }

    _last = TrackPosition(Gps.toLatLng(position), altitude, speed, heading, DateTime.now());

    gpx.wpts.add(Wpt(lat: last.coordinate.latitude, lon: last.coordinate.longitude, ele: last.altitude, time: DateTime.now()));
  }

  void reset() {
    gpx = newGpx();
  }

  String getKml() {
    return KmlWriter().asString(gpx, pretty: true);
  }

  String getGpx() {
    return GpxWriter().asString(gpx, pretty: true);
  }

  List<LatLng> getPoints() {
    return gpx.wpts.map((e) => LatLng(e.lat!, e.lon!)).toList();
  }

  Future<void> saveKml() async {
    String data = getKml();
    await PathUtils.writeTrack(Storage().dataDir, data);
  }

}

class TrackPosition {
  LatLng coordinate;
  double altitude;
  double speed;
  double heading;
  DateTime time;

  TrackPosition(this.coordinate, this.altitude, this.speed, this.heading, this.time);
}