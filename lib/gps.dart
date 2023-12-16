import 'dart:async';

import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';


class Gps {

  Future<LocationPermission> checkPermissions() async {
    final GeolocatorPlatform platform = GeolocatorPlatform.instance;
    LocationPermission permission = await platform.checkPermission();
    if(permission != LocationPermission.always) {
      permission = await platform.requestPermission();
    }
    return permission;
  }


  void getUpdates(Function(Position? position) gpsUpdate) {
    const LocationSettings locationSettings = LocationSettings(accuracy: LocationAccuracy.high);

    StreamSubscription<Position> positionStream = Geolocator.getPositionStream(
        locationSettings: locationSettings).listen((Position? position) {
          gpsUpdate(position);
        });
  }

  Future<Position?> getLastPosition() async {
    return await Geolocator.getLastKnownPosition();
  }

  Future<Position?> getCurrentPosition() async {
    return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  static LatLng positionToLatLong(Position? p) {
    LatLng l;
    if(p != null) {
      l = LatLng(p.latitude, p.longitude);
    }
    else {
      l = const LatLng(37, 95);
    }
    return(l);
  }
}

