import 'dart:convert';
import 'package:universal_io/io.dart';
import 'dart:typed_data';
import 'package:avaremp/constants.dart';
import 'package:avaremp/data/weather_database_helper.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';
import 'metar.dart';
import 'weather.dart';


class MetarCache extends WeatherCache {

  Uint8List? image;

  MetarCache(super.url, super.dbCall);

  @override
  Future<void> parse(List<Uint8List> data, [String? argument]) async {
    if(data.isEmpty) {
      return;
    }
    final List<int> decodedData;
    String decoded;
    final XmlDocument document;
    final Iterable<XmlElement> textual;
    final List<Metar> metars = [];

    try {
      decodedData = GZipCodec().decode(data[0]);
      decoded = utf8.decode(decodedData, allowMalformed: true);
      document = XmlDocument.parse(decoded);
      textual = document.findAllElements("METAR");
    }
    catch(e) {
      // not gzipped
      Storage().setException("METAR: unable to decode data.");
      return;
    }

    if(decoded.startsWith("<?xml")) {
      for (var metar in textual) {
        try {
          String rt = metar.getElement("raw_text")!.innerText;
          double latitude = double.parse(metar.getElement("latitude")!.innerText);
          double longitude = double.parse(metar.getElement("longitude")!.innerText);
          String station = metar.getElement("station_id")!.innerText;
          String category = metar.getElement("flight_category")!.innerText;
          LatLng? pv = WeatherCache.parseAndValidateCoordinate(latitude.toString(), longitude.toString());
          if(pv == null) {
            continue;
          }
          Metar m = Metar(station,
              DateTime.now().toUtc().add(const Duration(minutes: Constants.weatherUpdateTimeMin)),
              DateTime.now().toUtc(),
              Weather.sourceInternet, rt, category, pv);
          metars.add(m);
        }
        catch(e) {
          continue;
        }
      }
    }
    await WeatherDatabaseHelper.db.addMetars(metars);
 }

  // Get Closets Metar of this coordinate
  Metar? getClosestMetar(LatLng coordinate) {
    GeoCalculations geo = GeoCalculations();
    double distance = 25; // do not use metars more than 25 miles away
    Metar? selected;
    List<Metar> metars = Storage().metar.getAll().map((e) => e as Metar).toList();
    for(Metar m in metars) {
      double d = geo.calculateDistance(m.coordinate, coordinate);
      if(d < distance) {
        selected = m;
        distance = d;
      }
    }
    return selected;
  }

}

