import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/instruments/gpws_alerts.dart';
import 'package:avaremp/io/gps.dart';
import 'package:avaremp/place/elevation_cache.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/instruments/glide_profile.dart';
import 'package:avaremp/weather/winds_aloft.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:flutter/cupertino.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class Area {

  double geoAltitude = 0;
  double? elevation;
  WindsAloft? windsAloft;
  Destination? closestAirport;
  List<LatLng> obstacles = [];
  double variation = 0;
  ValueNotifier<int> change = ValueNotifier(0);
  GlideProfile glideProfile = GlideProfile();
  GpwsAlerts? _gpwsAlerts;

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
    final List<double> layersOpacity = Storage().settings.getLayersOpacity();
    int lIndex = layers.indexOf('Obstacles');
    if(layersOpacity[lIndex] > 0) {
      obstacles = await MainDatabaseHelper.db.findObstacles(Gps.toLatLng(position), GeoCalculations.convertAltitude(position.altitude));
    }
    // get surface wind from nearest airport
    String wind = WindsCache.getWind0kFromMetar(Gps.toLatLng(position));
    // get aloft wind from nearest station
    String? station = WindsCache.locateNearestStation(Gps.toLatLng(position));
    WindsAloft? wa = Storage().winds.get("${station}06H") as WindsAloft?;
    if(null != wa) {
      // combine surface and aloft wind
      windsAloft = WindsAloft(wa.station, wa.expires, wa.received, wa.source, wind, wa.w3k, wa.w6k, wa.w9k, wa.w12k, wa.w18k, wa.w24k, wa.w30k, wa.w34k, wa.w39k);
    }

    elevation = await ElevationCache.getElevation(Gps.toLatLng(position));

    // change glide
    glideProfile.updateGlide();

    change.value++;

    if(Storage().settings.isAudibleAlertsEnabled()) {
      _gpwsAlerts ??= await GpwsAlerts.getAndStartGpwsAlerts();
      if(null != _gpwsAlerts && elevation != null) {
        _gpwsAlerts!.checkAltitude(
          gpsAltitudeFeet: GeoCalculations.convertAltitude(Storage().position.altitude),
          groundElevationFeet: elevation,
          groundSpeed: GeoCalculations.convertSpeed(Storage().position.speed),
        );
      }
    }
    else {
      if(null != _gpwsAlerts) {
        await GpwsAlerts.stopGpwsAlerts();
        _gpwsAlerts = null;
      }
    }
  }

  (double?, double?) getWind(double altitude) {
    double? direction = 0;
    double? speed = 0;
    if(null != windsAloft) {
      (direction, speed) = windsAloft!.getWindAtAltitude(altitude);
    }
    return (direction, speed);
  }
}