import 'dart:async';
import 'dart:math';

import 'package:avaremp/geo_calculations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';


class Gps {

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

  static Position clone(Position position, double geoidHeight) {
    // apply geoid correction to the non corrected data
    return Position(longitude: position.longitude, latitude: position.latitude, accuracy: position.accuracy, altitude: position.altitude - geoidHeight, altitudeAccuracy: position.altitudeAccuracy, heading: position.heading, headingAccuracy: position.headingAccuracy, speed: position.speed, speedAccuracy: position.speedAccuracy, timestamp: position.timestamp);
  }

  Future<void> requestPermissions() async {
    final GeolocatorPlatform platform = GeolocatorPlatform.instance;
    await platform.requestPermission();
  }


  Future<bool> isPermissionDenied() async {
    final GeolocatorPlatform platform = GeolocatorPlatform.instance;
    LocationPermission permission = await platform.checkPermission();
    return (LocationPermission.denied == permission ||
        LocationPermission.deniedForever == permission ||
        LocationPermission.unableToDetermine == permission);
  }

  Future<bool> isDisabled() async {
    final GeolocatorPlatform platform = GeolocatorPlatform.instance;
    return !(await platform.isLocationServiceEnabled());
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

  // for testing
  StreamSubscription<Position> getStreamMock() {
    final List<LatLng> mockPositions = GeoCalculations().findPoints(const LatLng(42.584, -70.916), const LatLng(42.584 + 0.75, -70.916), 1);
    mockPositions.addAll(mockPositions.reversed.toList()); // come back
    return Stream.periodic(const Duration(seconds: 1), (_) {
      double count = DateTime.now().second.toDouble();
      // change speed to simulate takeoff and landing, to 50 m/s, and one cycle in 180 seconds
      double speed = sin(((count * 2) % 360) * pi / 180) * 50;
      if(speed < 0) {
        speed = 0;
      }

      // change altitude to simulate takeoff and landing, to 1000 meters, and one cycle in 180 seconds
      double altitude = sin(((count * 2) % 360) * pi / 180) * 1000;
      if(altitude < 0) {
        altitude = 0;
      }

      // Code returning a value every 1 seconds.
      return Position(
        longitude: mockPositions[count.toInt() % mockPositions.length].longitude,
        latitude: mockPositions[count.toInt() % mockPositions.length].latitude,
        accuracy: 0,
        altitude: altitude,
        altitudeAccuracy: 0,
        heading: count % 90,
        headingAccuracy: 0,
        speed: speed,
        speedAccuracy: 0,
        timestamp: DateTime.now(),
      );
    }).listen((Position position) {});
  }

  StreamSubscription<Position> getStream() {

    StreamSubscription<Position> positionStream;

    const LocationSettings locationSettings = LocationSettings(accuracy: LocationAccuracy.high,);

    positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position? position) {});

    return positionStream;
  }

  static LatLng toLatLng(Position position) {
    return LatLng(position.latitude, position.longitude);
  }

}

