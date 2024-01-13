import 'dart:async';

import 'package:avaremp/constants.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';


class Gps {

  bool useSim = false;

  static Position centerUSAPosition() {
    return Position(longitude: -97, latitude: 38, accuracy: 0, altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0, timestamp: DateTime.now());
  }

  // if position is null, return lat/lon to center of USA, otherwise return same position back
  static Position _orCenterOfUsa(Position? position) {
    if(null == position) {
      return centerUSAPosition();
    }
    return(position);
  }


  Future<void> requestPermissions() async {
    final GeolocatorPlatform platform = GeolocatorPlatform.instance;
    await platform.requestPermission();
  }


  Future<bool> checkPermissions() async {
    final GeolocatorPlatform platform = GeolocatorPlatform.instance;
    LocationPermission permission = await platform.checkPermission();
    return (LocationPermission.denied == permission ||
        LocationPermission.deniedForever == permission ||
        LocationPermission.unableToDetermine == permission);
  }

  Future<bool> checkEnabled() async {
    final GeolocatorPlatform platform = GeolocatorPlatform.instance;
    return await platform.isLocationServiceEnabled();
  }

  Future<Position> getCurrentPosition() async {
    try {
      return Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
    }
    catch(e) {
      return getLastPosition();
    }
  }

  Future<Position> getLastPosition() async {
    try {
      Position? p = await Geolocator.getLastKnownPosition();
      return(_orCenterOfUsa(p));
    }
    catch(e) {
      return (_orCenterOfUsa(null));
    }
  }

  static int num = 0;

  StreamSubscription<Position> getStream() {

    StreamSubscription<Position> positionStream;

    if(useSim) {
      // always fly to destination
      final Stream<Position> stream = Stream<Position>.periodic(const Duration(seconds: 1), (count) {

        List<LatLng> points = Storage().route.getPathCurrent();

        if(points.isNotEmpty) {
          if (num >= points.length - 1) {
            Storage().route.advance();
            points = Storage().route.getPathCurrent();
            num = 0;
          }
        }

        double latitude = points.isNotEmpty ? points[num].latitude : 0;
        double longitude = points.isNotEmpty ? points[num].longitude : 0;

        double heading = points.isNotEmpty ? GeoCalculations().calculateBearing(points[num], points[num + 1]) : 0;

        num++;

        Position p = Position(
            longitude: longitude,
            latitude: latitude,
            timestamp: DateTime.timestamp(),
            accuracy: 0,
            altitude: count.toDouble(),
            altitudeAccuracy: 0,
            heading: heading,
            headingAccuracy: 0,
            speed: Constants.nmToM(1),
            speedAccuracy: 0);
        return p;
      });

      positionStream = stream.listen((Position? position) {});
    }
    else {
      const LocationSettings locationSettings = LocationSettings(accuracy: LocationAccuracy.high,);

      positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position? position) {
      });
    }

    return positionStream;
  }

  static LatLng toLatLng(Position position) {
    return LatLng(position.latitude, position.longitude);
  }
}

