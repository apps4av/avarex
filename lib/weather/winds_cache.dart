import 'dart:convert';
import 'dart:typed_data';

import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/weather_cache.dart';
import 'package:avaremp/weather/winds_aloft.dart';
import 'package:latlong2/latlong.dart';

import 'metar.dart';


class WindsCache extends WeatherCache {

  WindsCache(super.url, super.dbCall);

  // metar if winds from ground need to be used
  static (double?, double?) getWindsAt(LatLng coordinate, double altitude) {
    double? ws;
    double? wd;
    String? station = WindsCache.locateNearestStation(coordinate);
    WindsAloft? wa = Storage().winds.get(station) != null ? Storage().winds.get(station) as WindsAloft : null;
    (wd, ws) = WindsCache.getWindAtAltitude(altitude, wa);
    return (wd, ws);
  }

  @override
  Future<void> parse(Uint8List data, [String? argument]) async {

    List<WindsAloft> winds = [];
    String dataString = utf8.decode(data);

    // parse winds, set expire time
    RegExp exp1 = RegExp("VALID\\s*([0-9]*)Z\\s*FOR USE\\s*([0-9]*)-([0-9]*)Z");
    DateTime? expires;

    List<String> lines = dataString.split('\n');
    for (String line in lines) {
      line = line.trim();
      RegExpMatch? match = exp1.firstMatch(line);
      if (match != null) {
        DateTime now = DateTime.now().toUtc();
        expires = DateTime.utc(
            now.year,
            now.month,
            now.day, //day
            0,
            0);
        int from = int.parse(match[2]!);
        int to = int.parse(match[3]!);
        // if from > to then its next day
        expires = expires.add(Duration(days: to < from ? 1 : 0, hours: int.parse(match[3]!.substring(0, 2))));
        break;
      }
    }

    bool start = false;
    // parse winds, first check if a new download is needed
    RegExp exp2 = RegExp("FT.*39000");
    for (String line in lines) {
      line = line.trim();
      RegExpMatch? match = exp2.firstMatch(line);
      if(match != null) {
        start = true;
        continue;
      }
      if(!start) {
        continue;
      }
      try {
        String station = line.substring(0, 3).trim();
        String k3 = line.substring(4, 8).trim();
        String k6 = line.substring(9, 16).trim();
        String k9 = line.substring(17, 24).trim();
        String k12 = line.substring(25, 32).trim();
        String k18 = line.substring(33, 40).trim();
        String k24 = line.substring(41, 48).trim();
        String k30 = line.substring(49, 55).trim();
        String k34 = line.substring(56, 62).trim();
        String k39 = line.substring(63, 69).trim();
        LatLng? coordinate = _stationMap[station];
        if(coordinate == null) {
          continue; // not recognized need this
        }
        if(expires == null) {
          continue;
        }

        WindsAloft w = WindsAloft(station, expires, await getWind0kFromMetar(coordinate), k3, k6, k9, k12, k18, k24, k30, k34, k39);
        winds.add(w);
      }
      catch (e) {}
      Storage().realmHelper.addWindsAlofts(winds); // add to database
    }
  }

  static String? locateNearestStation(LatLng location) {
    // find distance
    GeoCalculations geo = GeoCalculations();
    double distanceMin = double.maxFinite;
    String? station;
    for(MapEntry<String, LatLng> map in _stationMap.entries) {
      double distance = geo.calculateDistance(map.value, location);
      if(distance < distanceMin) {
        distanceMin = distance;
        station = map.key;
      }
    }
    return station;
  }

  // dir, speed
  static (double?, double?) getWindAtAltitude(double altitude, WindsAloft? w) {
    // find distance
    if(w == null) {
      return(null, null);
    }
    return(w.getWindAtAltitude(altitude));
  }

  static String getWind0kFromMetar(LatLng coordinate) {
    Metar? m = Storage().metar.getClosestMetar(coordinate);
    String k0 = "";
    if(m != null) {
      String? wd;
      String? ws;
      (wd, ws) = Metar.getWind(m.text);
      if(wd != null && ws != null) {
        try {
          int wdInt = int.parse(wd) ~/ 10;
          int wsInt = int.parse(ws);
          if(wsInt > 99) {
            wsInt = 99; // this is crazy.
          }
          k0 = wdInt.toString().padLeft(2, "0") + wsInt.toString().padLeft(2, "0");
        }
        catch (e) {}
      }
    }
    return k0;
  }

  static const Map<String, LatLng> _stationMap = {
    "BHM": LatLng(33.55, -86.73333333333333),
    "HSV": LatLng(34.55, -86.76666666666667),
    "MGM": LatLng(32.21666666666667, -86.31666666666666),
    "MOB": LatLng(30.683333333333334, -88.23333333333333),
    "ADK": LatLng(51.93333333333333, -176.41666666666666),
    "ADQ": LatLng(57.766666666666666, -152.58333333333334),
    "AKN": LatLng(58.733333333333334, -156.75),
    "ANC": LatLng(61.233333333333334, -149.55),
    "ANN": LatLng(55.05, -131.61666666666667),
    "BET": LatLng(60.583333333333336, -161.58333333333334),
    "BRW": LatLng(71.28333333333333, -156.51666666666668),
    "BTI": LatLng(70.16666666666667, -143.91666666666666),
    "BTT": LatLng(66.9, -151.5),
    "CDB": LatLng(55.18333333333333, -162.36666666666667),
    "CZF": LatLng(61.78333333333333, -166.03333333333333),
    "EHM": LatLng(58.65, -162.06666666666666),
    "FAI": LatLng(64.71666666666667, -148.18333333333334),
    "FYU": LatLng(66.58333333333333, -145.08333333333334),
    "GAL": LatLng(64.73333333333333, -156.93333333333334),
    "GKN": LatLng(62.15, -145.45),
    "HOM": LatLng(59.65, -151.48333333333332),
    "JNU": LatLng(58.43333333333333, -134.68333333333334),
    "LUR": LatLng(68.88333333333334, -166.11666666666667),
    "MCG": LatLng(62.81666666666667, -155.4),
    "MDO": LatLng(59.5, -146.3),
    "OME": LatLng(64.61666666666666, -165.08333333333334),
    "ORT": LatLng(63.06666666666667, -142.06666666666666),
    "OTZ": LatLng(66.65, -162.9),
    "SNP": LatLng(57.15, -170.61666666666667),
    "TKA": LatLng(62.31666666666667, -150.1),
    "UNK": LatLng(63.88333333333333, -160.8),
    "YAK": LatLng(59.61666666666667, -139.5),
    "IKO": LatLng(52.95, -168.85),
    "AFM": LatLng(67.1, -157.85),
    "5AB": LatLng(52.416666666666664, 176.0),
    "5AC": LatLng(52.0, -135.0),
    "5AD": LatLng(54.0, -145.0),
    "5AE": LatLng(55.0, -155.0),
    "5AF": LatLng(56.0, -137.0),
    "5AG": LatLng(58.0, -142.0),
    "FSM": LatLng(35.38333333333333, -94.26666666666667),
    "LIT": LatLng(34.666666666666664, -92.16666666666667),
    "PHX": LatLng(33.416666666666664, -111.88333333333334),
    "PRC": LatLng(34.7, -112.46666666666667),
    "TUS": LatLng(32.11666666666667, -110.81666666666666),
    "BIH": LatLng(37.36666666666667, -118.35),
    "BLH": LatLng(33.583333333333336, -114.75),
    "FAT": LatLng(36.88333333333333, -119.8),
    "FOT": LatLng(40.666666666666664, -124.23333333333333),
    "ONT": LatLng(34.05, -117.6),
    "RBL": LatLng(40.083333333333336, -122.23333333333333),
    "SAC": LatLng(38.43333333333333, -121.55),
    "SAN": LatLng(32.733333333333334, -117.18333333333334),
    "SBA": LatLng(34.5, -119.76666666666667),
    "SFO": LatLng(37.61666666666667, -122.36666666666666),
    "SIY": LatLng(41.78333333333333, -122.45),
    "WJF": LatLng(34.733333333333334, -118.21666666666667),
    "ALS": LatLng(37.333333333333336, -105.8),
    "DEN": LatLng(39.8, -104.88333333333334),
    "GJT": LatLng(39.05, -108.78333333333333),
    "PUB": LatLng(38.28333333333333, -104.41666666666667),
    "BDL": LatLng(41.93333333333333, -72.68333333333334),
    "EYW": LatLng(24.583333333333332, -81.8),
    "JAX": LatLng(30.433333333333334, -81.55),
    "MIA": LatLng(25.95, -80.45),
    "MLB": LatLng(28.1, -80.63333333333334),
    "PFN": LatLng(30.2, -85.66666666666667),
    "PIE": LatLng(27.9, -82.68333333333334),
    "TLH": LatLng(30.55, -84.36666666666666),
    "ATL": LatLng(33.61666666666667, -84.43333333333334),
    "CSG": LatLng(32.6, -85.01666666666667),
    "SAV": LatLng(32.15, -81.1),
    "ITO": LatLng(19.716666666666665, -155.05),
    "HNL": LatLng(21.316666666666666, -157.91666666666666),
    "LIH": LatLng(21.983333333333334, -159.33333333333334),
    "OGG": LatLng(20.9, -156.43333333333334),
    "BOI": LatLng(43.56666666666667, -116.23333333333333),
    "LWS": LatLng(46.36666666666667, -116.86666666666666),
    "PIH": LatLng(42.86666666666667, -112.65),
    "JOT": LatLng(41.53333333333333, -88.31666666666666),
    "SPI": LatLng(39.833333333333336, -89.66666666666667),
    "EVV": LatLng(38.03333333333333, -87.51666666666667),
    "FWA": LatLng(40.96666666666667, -85.18333333333334),
    "IND": LatLng(39.8, -86.36666666666666),
    "BRL": LatLng(40.71666666666667, -90.91666666666667),
    "DBQ": LatLng(42.4, -90.7),
    "DSM": LatLng(41.43333333333333, -93.63333333333334),
    "MCW": LatLng(43.083333333333336, -93.31666666666666),
    "GCK": LatLng(37.916666666666664, -100.71666666666667),
    "GLD": LatLng(39.38333333333333, -101.68333333333334),
    "ICT": LatLng(37.71666666666667, -97.45),
    "SLN": LatLng(38.86666666666667, -97.61666666666666),
    "LOU": LatLng(38.1, -85.56666666666666),
    "LCH": LatLng(30.133333333333333, -93.1),
    "MSY": LatLng(30.016666666666666, -90.16666666666667),
    "SHV": LatLng(32.766666666666666, -93.8),
    "BGR": LatLng(44.833333333333336, -68.86666666666666),
    "CAR": LatLng(46.86666666666667, -68.01666666666667),
    "PWM": LatLng(43.63333333333333, -70.3),
    "EMI": LatLng(39.483333333333334, -76.96666666666667),
    "ACK": LatLng(41.266666666666666, -70.01666666666667),
    "BOS": LatLng(42.35, -70.98333333333333),
    "ECK": LatLng(43.25, -82.71666666666667),
    "MKG": LatLng(43.166666666666664, -86.03333333333333),
    "MQT": LatLng(46.516666666666666, -87.58333333333333),
    "SSM": LatLng(46.4, -84.3),
    "TVC": LatLng(44.666666666666664, -85.53333333333333),
    "AXN": LatLng(45.95, -95.21666666666667),
    "DLH": LatLng(46.8, -92.2),
    "INL": LatLng(48.55, -93.4),
    "MSP": LatLng(45.13333333333333, -93.36666666666666),
    "CGI": LatLng(37.21666666666667, -89.56666666666666),
    "COU": LatLng(38.8, -92.21666666666667),
    "MKC": LatLng(39.266666666666666, -94.58333333333333),
    "SGF": LatLng(37.35, -93.33333333333333),
    "STL": LatLng(38.85, -90.46666666666667),
    "JAN": LatLng(32.5, -90.16666666666667),
    "BIL": LatLng(45.8, -108.61666666666666),
    "DLN": LatLng(45.233333333333334, -112.53333333333333),
    "GPI": LatLng(48.2, -114.16666666666667),
    "GGW": LatLng(48.2, -106.61666666666666),
    "GTF": LatLng(47.45, -111.4),
    "MLS": LatLng(46.36666666666667, -105.95),
    "HAT": LatLng(35.266666666666666, -75.55),
    "ILM": LatLng(34.35, -77.86666666666666),
    "RDU": LatLng(35.86666666666667, -78.78333333333333),
    "DIK": LatLng(46.85, -102.76666666666667),
    "GFK": LatLng(47.95, -97.18333333333334),
    "MOT": LatLng(48.25, -101.28333333333333),
    "BFF": LatLng(41.88333333333333, -103.46666666666667),
    "GRI": LatLng(40.983333333333334, -98.3),
    "OMA": LatLng(41.166666666666664, -95.73333333333333),
    "ONL": LatLng(42.46666666666667, -98.68333333333334),
    "BML": LatLng(44.63333333333333, -71.18333333333334),
    "ACY": LatLng(39.45, -74.56666666666666),
    "ABQ": LatLng(35.03333333333333, -106.8),
    "FMN": LatLng(36.733333333333334, -108.08333333333333),
    "ROW": LatLng(33.333333333333336, -104.61666666666666),
    "TCC": LatLng(35.166666666666664, -103.58333333333333),
    "ZUN": LatLng(34.95, -109.15),
    "BAM": LatLng(40.56666666666667, -116.91666666666667),
    "ELY": LatLng(39.28333333333333, -114.83333333333333),
    "LAS": LatLng(36.06666666666667, -115.15),
    "RNO": LatLng(39.516666666666666, -119.65),
    "ALB": LatLng(42.733333333333334, -73.8),
    "BUF": LatLng(42.916666666666664, -78.63333333333334),
    "JFK": LatLng(40.61666666666667, -73.76666666666667),
    "PLB": LatLng(44.8, -73.4),
    "SYR": LatLng(43.15, -76.2),
    "CLE": LatLng(41.35, -82.15),
    "CMH": LatLng(39.983333333333334, -82.91666666666667),
    "CVG": LatLng(39.0, -84.7),
    "GAG": LatLng(36.333333333333336, -99.86666666666666),
    "OKC": LatLng(35.4, -97.63333333333334),
    "TUL": LatLng(36.18333333333333, -95.78333333333333),
    "AST": LatLng(46.15, -123.86666666666666),
    "IMB": LatLng(44.63333333333333, -119.7),
    "LKV": LatLng(42.483333333333334, -120.5),
    "OTH": LatLng(43.4, -124.16666666666667),
    "PDX": LatLng(45.733333333333334, -122.58333333333333),
    "RDM": LatLng(44.25, -121.3),
    "AGC": LatLng(40.266666666666666, -80.03333333333333),
    "AVP": LatLng(41.266666666666666, -75.68333333333334),
    "PSB": LatLng(40.9, -77.98333333333333),
    "CAE": LatLng(33.85, -81.05),
    "CHS": LatLng(32.88333333333333, -80.03333333333333),
    "FLO": LatLng(34.21666666666667, -79.65),
    "GSP": LatLng(34.88333333333333, -82.21666666666667),
    "ABR": LatLng(45.416666666666664, -98.36666666666666),
    "FSD": LatLng(43.63333333333333, -96.76666666666667),
    "PIR": LatLng(44.38333333333333, -100.15),
    "RAP": LatLng(43.96666666666667, -103.0),
    "BNA": LatLng(36.11666666666667, -86.66666666666667),
    "MEM": LatLng(35.05, -89.96666666666667),
    "TRI": LatLng(36.46666666666667, -82.4),
    "TYS": LatLng(35.9, -83.88333333333334),
    "ABI": LatLng(32.46666666666667, -99.85),
    "AMA": LatLng(35.28333333333333, -101.63333333333334),
    "BRO": LatLng(25.916666666666668, -97.36666666666666),
    "CLL": LatLng(30.6, -96.41666666666667),
    "CRP": LatLng(27.9, -97.43333333333334),
    "DAL": LatLng(32.833333333333336, -96.85),
    "DRT": LatLng(29.366666666666667, -100.91666666666667),
    "ELP": LatLng(31.8, -106.26666666666667),
    "HOU": LatLng(29.633333333333333, -95.26666666666667),
    "INK": LatLng(31.866666666666667, -103.23333333333333),
    "LBB": LatLng(33.7, -101.9),
    "LRD": LatLng(27.466666666666665, -99.41666666666667),
    "MRF": LatLng(30.283333333333335, -103.61666666666666),
    "PSX": LatLng(28.75, -96.3),
    "SAT": LatLng(28.633333333333333, -98.45),
    "SPS": LatLng(33.983333333333334, -98.58333333333333),
    "BCE": LatLng(37.68333333333333, -112.3),
    "SLC": LatLng(40.85, -111.96666666666667),
    "ORF": LatLng(36.88333333333333, -76.2),
    "RIC": LatLng(37.5, -77.31666666666666),
    "ROA": LatLng(37.333333333333336, -80.06666666666666),
    "GEG": LatLng(47.55, -117.61666666666666),
    "SEA": LatLng(47.43333333333333, -122.3),
    "YKM": LatLng(46.56666666666667, -120.43333333333334),
    "GRB": LatLng(44.55, -88.18333333333334),
    "LSE": LatLng(43.86666666666667, -91.25),
    "CRW": LatLng(38.333333333333336, -81.76666666666667),
    "EKN": LatLng(38.9, -80.08333333333333),
    "CZI": LatLng(43.983333333333334, -106.43333333333334),
    "LND": LatLng(42.8, -108.71666666666667),
    "MBW": LatLng(41.833333333333336, -106.0),
    "RKS": LatLng(41.583333333333336, -109.0),
    "2XG": LatLng(30.333333333333332, -78.5),
    "T01": LatLng(28.5, -93.5),
    "T06": LatLng(28.5, -91.0),
    "T07": LatLng(28.5, -88.0),
    "4J3": LatLng(28.5, -85.0),
    "H51": LatLng(26.5, -95.0),
    "H52": LatLng(26.0, -89.5),
    "H61": LatLng(26.5, -84.0),
    "JON": LatLng(16.733333333333334, -169.53333333333333),
    "MAJ": LatLng(7.066666666666666, 171.26666666666668),
    "KWA": LatLng(8.716666666666667, 167.73333333333332),
    "MDY": LatLng(28.2, -177.38333333333333),
    "PPG": LatLng(-14.333333333333334, -170.71666666666667),
    "TTK": LatLng(5.35, 162.96666666666667),
    "AWK": LatLng(19.283333333333335, 166.65),
    "GRO": LatLng(14.183333333333334, 145.23333333333332),
    "GSN": LatLng(15.116666666666667, 145.73333333333332),
    "TNI": LatLng(15.0, 145.61666666666667),
    "GUM": LatLng(13.483333333333333, 144.8),
    "TKK": LatLng(7.466666666666667, 151.85),
    "PNI": LatLng(6.983333333333333, 158.21666666666667),
    "ROR": LatLng(7.366666666666666, 134.55),
    "T11": LatLng(9.5, 138.08333333333334),
    "LNY": LatLng(20 + 47 / 60, -156 - 57 / 60),
    "KOA": LatLng(19 + 44 / 60, -156 - 3 / 60),
  };

}

