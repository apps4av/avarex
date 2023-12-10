import 'dart:async';

import 'package:geolocator/geolocator.dart';


class Gps {

  static Future<LocationPermission> checkPermissions() async {
    final GeolocatorPlatform geolocatorPlatform = GeolocatorPlatform.instance;
    LocationPermission permission = await geolocatorPlatform.checkPermission();
    if(permission != LocationPermission.always) {
      permission = await geolocatorPlatform.requestPermission();
    }
    return permission;
  }


  static void getUpdates() {
    final LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
    StreamSubscription<Position> positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
            (Position? position) {
          print(position == null ? 'Unknown' : '${position.latitude.toString()}, ${position.longitude.toString()}');
        });
  }

}