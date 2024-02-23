import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:avaremp/weather/weather.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:avaremp/data/weather_database_helper.dart';
import 'package:csv/csv.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../constants.dart';
import 'metar.dart';
import 'dart:ui' as ui;


class MetarCache extends WeatherCache {

  Uint8List? image;

  MetarCache(super.url, super.dbCall);

  @override
  Future<void> parse(Uint8List data) async {
    final List<int> decodedData = GZipCodec().decode(data);
    final List<Metar> metars = [];
    String decoded = utf8.decode(decodedData, allowMalformed: true);
    List<List<dynamic>> rows = const CsvToListConverter().convert(decoded, eol: "\n");
    for (List<dynamic> row in rows) {
      DateTime time = DateTime.now().toUtc();
      // observation time like 2024-01-27T18:26:00Z in row[2]
      time = time.add(const Duration(minutes: Constants.weatherUpdateTimeMin)); // they update every minute but that's too fast

      Metar m;
      try {
        m = Metar(row[1], time, row[0], row[30], LatLng(row[3], row[4]));
        metars.add(m);
      }
      catch(e) {
        continue;
      }
    }
    WeatherDatabaseHelper.db.addMetars(metars);
  }

  @override
  Future<void> initialize() async {
    super.initialize().then((value) => (change.value++)); //generateImage()); use this when needed to show Metars in image. Not needed yet.
  }

  generateImage() async {
    genImage().then((generatedImage) async {
      ByteData? img = await generatedImage.toByteData(format: ui.ImageByteFormat.png);
      if(img != null) {
        image = img.buffer.asUint8List();
        change.value++; // new map
      }
    });
  }

  // this will cover 48 states
  static const LatLng topLeft = LatLng(52, -130);
  static const LatLng bottomRight = LatLng(22, -60);
  static const double xSize = 700 * 1.3;
  static const double ySize = 300 * 1.3;

  Future<ui.Image> genImage() async {
    var recorder = ui.PictureRecorder();
    var canvas = ui.Canvas(recorder, const ui.Rect.fromLTWH(0, 0, xSize, ySize)); // this size is legacy avare
    SphericalMercator projection = const SphericalMercator();
    Point tl = projection.project(topLeft);
    Point br = projection.project(bottomRight);
    double px = xSize / (tl.x - br.x);
    double py = ySize / (tl.y - br.y);
    // draw
    for(Weather w in getAll()) {
      Metar m = w as Metar;
      LatLng ll = m.coordinate;
      Point p = projection.project(ll);
      double x = px * (tl.x - p.x);
      double y = py * (tl.y - p.y);
      if(x > xSize || y > ySize || x < 0 || y < 0) {
        continue;
      }
      Paint paint = Paint()..color = m.getColor();
      canvas.drawCircle(Offset(x, y), 1, paint);
    }
    var pic = recorder.endRecording();
    var img = await pic.toImage(xSize.toInt(), ySize.toInt());
    return img;
  }

}

