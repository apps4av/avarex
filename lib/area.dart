import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/winds_aloft.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'gps.dart';

class Area {

  double geoAltitude = 0;
  WindsAloft? _windsAloft;
  Destination? closestAirport;
  List<LatLng> obstacles = [];
  double variation = 0;

  Future<void> update(Position position) async {
    double geo = 0;
    double declination = 0;
    (geo, declination) = await MainDatabaseHelper.db.getGeoInfo(Gps.toLatLng(position));
    geoAltitude = geo;
    variation = declination;
    List<Destination> d = await MainDatabaseHelper.db.findNearestAirportsWithRunways(Gps.toLatLng(position), 1000);
    if(d.isNotEmpty) {
      closestAirport = d[0];
    }

    final List<String> layers = Storage().settings.getLayers();
    final List<bool> layersState = Storage().settings.getLayersState();
    int lIndex = layers.indexOf('Obstacles');
    if(layersState[lIndex]) {
      obstacles = await MainDatabaseHelper.db.findObstacles(Gps.toLatLng(position), GeoCalculations.convertAltitude(position.altitude));
    }
    // get surface wind from nearest airport
    String wind = WindsCache.getWind0kFromMetar(Gps.toLatLng(position));
    // get aloft wind from nearest station
    String? station = WindsCache.locateNearestStation(Gps.toLatLng(position));
    WindsAloft? wa = Storage().winds.get(station) as WindsAloft?;
    if(null != wa) {
      // combine surface and aloft wind
      _windsAloft = WindsAloft(wa.station, wa.expires, wind, wa.w3k, wa.w6k, wa.w9k, wa.w12k, wa.w18k, wa.w24k, wa.w30k, wa.w34k, wa.w39k);
    }
  }

  (double?, double?) getWind(double altitude) {
    double? direction = 0;
    double? speed = 0;
    if(null != _windsAloft) {
      (direction, speed) = _windsAloft!.getWindAtAltitude(altitude);
    }
    return (direction, speed);
  }
}