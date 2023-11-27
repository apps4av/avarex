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

}