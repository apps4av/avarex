import 'package:avaremp/place/elevation_cache.dart';
import 'package:latlong2/latlong.dart';


class AltitudeProfile {

  // this creates a local cache
  static Future<List<double?>> getAltitudeProfile(List<LatLng> points) async {
    return await ElevationCache.getElevationOfPoints(points);
  }
}



