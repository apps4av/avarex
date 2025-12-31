import 'dart:io';
import 'dart:typed_data';

import 'package:avaremp/chart.dart';
import 'package:avaremp/utils/epsg900913.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/elevation_tile_provider.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/glide_profile.dart';
import 'package:avaremp/weather/winds_aloft.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:flutter/cupertino.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'gps.dart';
import 'package:image/image.dart' as img;

class Area {

  double geoAltitude = 0;
  double? elevation;
  WindsAloft? windsAloft;
  Destination? closestAirport;
  List<LatLng> obstacles = [];
  double variation = 0;
  ValueNotifier<int> change = ValueNotifier(0);
  String elevationTile = "";
  img.Image? decodedImage;
  GlideProfile glideProfile = GlideProfile();

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

    // find elevation from tile
    Epsg900913 proj = Epsg900913.fromLatLon(position.latitude, position.longitude, 10);
    int x = proj.getTilex();
    int y = proj.getTiley();
    double pixelX = Epsg900913.getOffsetX(proj.getLonUpperLeft(), position.longitude, 10);
    double pixelY = Epsg900913.getOffsetY(proj.getLatUpperLeft(), position.latitude, 10);

    // cache elevation tile image at maximum zoom
    String tileName =
      "${Storage().dataDir}/tiles/"
      "${ChartCategory.chartTypeToIndex(ChartCategory.elevation)}/"
      "${ChartCategory.chartTypeToZoom(ChartCategory.elevation)}/"
      "$x/$y."
      "${ChartCategory.chartTypeToExtension(ChartCategory.elevation)}";
    if(elevationTile != tileName) {
      // new tile, clear decoded image
      decodedImage = null;
      elevationTile = tileName;
    }

    File tile = File(elevationTile);
    if (tile.existsSync()) {
      if(decodedImage == null) {
        // elevation tile exists
        final Uint8List inputImg = await tile.readAsBytes();

        // 2. Use the 'image' package to decode the compressed image data
        // The decodeImage function automatically detects the format (JPEG, PNG, etc.)
        decodedImage = img.decodeImage(inputImg);
      }

      if(decodedImage != null) {
        // 3. Get the raw pixel data in RGB format
        // The getBytes method returns a single-depth Uint8List of all pixel values
        // (R, G, B, R, G, B, ...)
        try {
          img.Pixel p = decodedImage!.getPixel(pixelX.toInt(), pixelY.toInt());
          elevation = (p.r as int) *
              ElevationImageProvider.altitudeFtElevationPerPixelSlopeBase +
              ElevationImageProvider.altitudeFtElevationPerPixelIntercept;
        }
        catch(e) {
          elevation = null;
        }
      }
    }
    else {
      elevation = null;
    }

    // change glide
    glideProfile.updateGlide();

    change.value++;
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