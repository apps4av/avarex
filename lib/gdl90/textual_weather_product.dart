import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/data/weather_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/utils/app_log.dart';
import 'package:avaremp/gdl90/product.dart';
import 'package:avaremp/weather/metar.dart';
import 'package:avaremp/weather/winds_aloft.dart';
import 'package:avaremp/weather/winds_cache.dart';

import '../constants.dart';
import '../storage.dart';
import '../weather/airep.dart';
import '../weather/taf.dart';
import '../weather/weather.dart';
import 'dlac.dart';

class TextualWeatherProduct extends Product {
  TextualWeatherProduct(super.time, super.data, super.coordinate, super.productFileId, super.productFileLength, super.apduNumber, super.segFlag);

  String _text = "";

  @override
  void parse() {

    int len = data.length;

    // Decode text: begins with @METAR, @TAF, @SPECI, @PIREP, @WINDS
    for (int i = 0; i < (len - 3); i += 3) {
      _text += Dlac.decode(data[i + 0], data[i + 1], data[i + 2]);
    }

    _text = Dlac.format(_text);
    List<String> parts = _text.split(" ");
    if(parts.length < 3) {
      return;
    }
    String type = parts[0];
    String place = parts[1];
    String report = parts.sublist(1).join(" ");

    switch(type) {
      case "TAF":
      case "TAF.AMD":
        _parseTaf(place, report);
        break;
      case "METAR":
      case "SPECI":
        _parseMetarSpeci(place, report);
        break;
      case "PIREP":
        _parsePirep(place, report);
        break;
      case "WINDS":
        _parseWinds(place, report);
        break;
    }
  }

  void _parseTaf(String place, String report) {

    MainDatabaseHelper.db.findAirport(place).then((AirportDestination? result) {
      if(result != null) {
        Taf taf = Taf(place,
            time.add(const Duration(minutes: Constants.weatherUpdateTimeMin)),
            DateTime.now(), Weather.sourceADSB,
            report, result.coordinate);
        Storage().taf.put(taf);
        WeatherDatabaseHelper.db.addTaf(taf);
      }
    });
  }

  // This is a lot of ugly code because marker cluster has issues with changing coordinates
  void _parseMetarSpeci(String place, String report) {
    // FAA bug, some airports come with wrong ID like K6b6, hence try both
    for(String pp in [place, place.substring(1)]) {
      MainDatabaseHelper.db.findAirport(pp).then((AirportDestination? result) {
        if (result != null) {
          Metar metar = Metar(pp, time.add(const Duration(minutes: Constants.weatherUpdateTimeMin)),
              DateTime.now(), Weather.sourceADSB,
              report, Metar.getCategory(report),
              result.coordinate);
          Storage().metar.put(metar);
          WeatherDatabaseHelper.db.addMetar(metar);
        }
      });
    }
  }

  void _parsePirep(String place, String report) {
    if(null != coordinate) {
      Airep airep = Airep(place,
          time.add(const Duration(minutes: Constants.weatherUpdateTimeMin)),
          DateTime.now(), Weather.sourceADSB, report, coordinate!);
      Storage().airep.put(airep);
      WeatherDatabaseHelper.db.addAirep(airep);

    }
  }

  void _parseWinds(String place, String report) {
    List<String> tokens = report.split("\n");
    if (tokens.length < 2) {
      /*
       * Must have line like
       * MSY 230000Z  FT 3000 6000    F9000   C12000  G18000  C24000  C30000  D34000  39000   Y
       * and second line like
       * 1410 2508+10 2521+07 2620+01 3037-12 3041-26 304843 295251 29765
       */
      return;
    }

    try {
      // this is lots of parsing with chances of exceptions
      tokens[0] = tokens[0].replaceAll("\\s+", " ");
      tokens[1] = tokens[1].replaceAll("\\s+", " ");
      List<String> winds = tokens[1].split(" ");
      List<String> alts = tokens[0].split(" ");
      String w0k = "";
      String w3k = "";
      String w6k = "";
      String w9k = "";
      String w12k = "";
      String w18k = "";
      String w24k = "";
      String w30k = "";
      String w34k = "";
      String w39k = "";

      /*
       * Start from 3rd entry - alts
       */
      for (int i = 2; i < alts.length; i++) {
        if (alts[i].contains("3000") && !alts[i].contains("30000")) {
          w3k = winds[i - 2];
        }
      }
      for (int i = 2; i < alts.length; i++) {
        if (alts[i].contains("6000")) {
          w6k = winds[i - 2];
        }
      }
      for (int i = 2; i < alts.length; i++) {
        if (alts[i].contains("9000") && !alts[i].contains("39000")) {
          w9k = winds[i - 2];
        }
      }
      for (int i = 2; i < alts.length; i++) {
        if (alts[i].contains("12000")) {
          w12k = winds[i - 2];
        }
      }
      for (int i = 2; i < alts.length; i++) {
        if (alts[i].contains("18000")) {
          w18k = winds[i - 2];
        }
      }
      for (int i = 2; i < alts.length; i++) {
        if (alts[i].contains("24000")) {
          w24k = winds[i - 2];
        }
      }
      for (int i = 2; i < alts.length; i++) {
        if (alts[i].contains("30000")) {
          w30k = winds[i - 2];
        }
      }
      for (int i = 2; i < alts.length; i++) {
        if (alts[i].contains("34000")) {
          w34k = winds[i - 2];
        }
      }
      for (int i = 2; i < alts.length; i++) {
        if (alts[i].contains("39000")) {
          w39k = winds[i - 2];
        }
      }
      if(coordinate != null) {
        w0k = WindsCache.getWind0kFromMetar(coordinate!);
      }
      WindsAloft wa = WindsAloft("${place}06H", time.add(const Duration(minutes: Constants.weatherUpdateTimeMin)), DateTime.now(), Weather.sourceADSB,
          w0k, w3k, w6k, w9k, w12k, w18k, w24k, w30k, w34k, w39k);
      Storage().winds.put(wa);
      WeatherDatabaseHelper.db.addWindsAloft(wa);
    }
    catch (e) {
      AppLog.logMessage("Exception parsing winds aloft ADS-B: $e");
    }
  }

}

