
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/instrument_list.dart';
import 'package:avaremp/path_utils.dart';
import 'package:avaremp/storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gpx/gpx.dart';
import 'package:latlong2/latlong.dart';
import 'gps.dart';

class GpsRecorder {

  TrackPosition _last;
  final Gpx _gpx;

  GpsRecorder() : _gpx = Gpx(),  _last = TrackPosition(LatLng(0,0), 0, 0, 0, DateTime.now()){
    _gpx.creator = 'AvareX';
    _gpx.metadata = Metadata();
    _gpx.metadata?.name = "AvareX Flight Path";
    _gpx.metadata?.desc = "3-D Flight Position Data";
    _gpx.metadata?.time = DateTime.now();
    _gpx.wpts = [];
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

    _last = TrackPosition(Gps.toLatLng(position), altitude, speed, heading, DateTime.now());
    _gpx.wpts.add(Wpt(lat: _last.coordinate.latitude, lon: _last.coordinate.longitude, ele: _last.altitude, desc: "speed=${_last.speed.round()}", time: DateTime.now()));
  }

  String getKml() {
    return KmlWriter().asString(_gpx, pretty: true);
  }

  String getGpx() {
    return GpxWriter().asString(_gpx, pretty: true);
  }

  List<LatLng> getPoints() {
    return _gpx.wpts.map((e) => LatLng(e.lat!, e.lon!)).toList();
  }

  Future<String?> saveKml() async {
    String data = getKml();
    return await PathUtils.writeTrack(Storage().dataDir, data);
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