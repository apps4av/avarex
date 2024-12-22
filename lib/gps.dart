import 'dart:async';

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

