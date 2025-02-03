
import 'package:avaremp/storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../geo_calculations.dart';

class Sounding {

  static (String?, double, double) _locateNearestStation(LatLng location) {

    // find distance
    GeoCalculations geo = GeoCalculations();
    double distanceMin = double.maxFinite;
    String? station;
    LatLng? stationLocation;
    for(MapEntry<String, LatLng> map in _stationMap.entries) {
      double distance = geo.calculateDistance(map.value, location);
      if(distance < distanceMin) {
        distanceMin = distance;
        station = map.key;
        stationLocation = map.value;
      }
    }
    double? bearing;
    if(stationLocation != null)
    {
      bearing = geo.calculateBearing(stationLocation, location);
    }
    return (station, distanceMin, bearing ?? 0);
  }

  static Widget? getSoundingImage(LatLng coordinate, BuildContext context) {

    Widget errorImage(BuildContext context, String url, Object error) {
      return const Center(child: Text('Error downloading the Sounding Analysis for this area.'));
    }

    var (station, dist, bearing) = _locateNearestStation(coordinate);
    if(null == station) {
      return null;
    }
    DateTime now = DateTime.timestamp();
    now = now.subtract(const Duration(hours: 1)); // 1 hour delayed on website
    DateTime obsTime = DateTime.utc(now.year, now.month, now.day,  (now.hour/ 12).floor() * 12);
    String hour = obsTime.hour.toString().padLeft(2, '0');
    String year = obsTime.year.toString().substring(2);
    String day = obsTime.day.toString().padLeft(2, '0');
    String month = obsTime.month.toString().padLeft(2, '0');
    String url = "https://www.spc.noaa.gov/exper/soundings/$year$month$day${hour}_OBS/$station.gif";
    Duration timeSinceObs = DateTime.timestamp().difference(obsTime);
    CachedNetworkImage image = CachedNetworkImage(imageUrl: url, cacheManager: FileCacheManager().networkCacheManager, errorWidget: errorImage,);
    return ListView(
      children: <Widget>[
        ListTile(title: Text("${dist.round()} ${Storage().units.distanceName} ${GeoCalculations.getGeneralDirectionFrom(bearing, 0)} @ ${station} (${timeSinceObs.inHours}:${(timeSinceObs.inMinutes % 60).toString().padLeft(2, '0')} ago)")),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: InteractiveViewer(
            child: Container(
              color: Colors.white,
              alignment: Alignment.center,
              child: image
            )
          )
        )
      ]
    );
  }

  // List of station codes from the HTML area elements
  // From NOAA's SPC Sounding Page
  // These are the supported stations
  static List<String> stationCodes = [
    'WPL', 'YQI', 'SGF', 'FWD', 'BRO', 'CRP', 'LCH', 'UNR', 'BIS', 'GGW',
    'DVN', 'ILX', 'LIX', 'DDC', 'AMA', 'MAF', 'SHV', 'BMX', 'DTX', 'APX',
    'GRB', 'IAD', 'INL', 'FFC', 'KEY', 'MFL', 'TBW', 'JAX', 'CHS', 'PIT',
    'WAL', 'OKX', 'ALB', 'GYX', 'CAR', 'TUS', 'FGZ', 'NKX', 'OAK', 'REV',
    'MFR', 'SLE', 'UIL', 'TOP', 'ABQ', 'EPZ', 'OAX', 'SLC', 'BOI', 'LKN',
    'RIW', 'GJT', 'DRT', 'VEF', 'OUN', 'OYU', 'ADN',
    // all entries after this not listed on website
    'YVP', 'YSM', 'YJT', 'YYR', 'YYQ', 'YZT', 'YYE', 'WSE',
    'PASN', 'PACD', 'PAKN', 'PAMC', 'PANC', 'PADQ', 'PABE'
    'PAOM', 'PAOT', 'PABR', 'PAFA', 'PAYA', 'PANT',
    'PHLI', 'PHTO', 'NSTU', 'TJSJ', 'MDSD', 'MKJP', 'TNCC'

  ];

  // from SHARPPY, except AK/HI, OYU
  static const Map<String, LatLng> _stationMap = {
    'WPL': LatLng(51.47, -90.2), // Pickle Lake, Ontario, Canada
    'WMW': LatLng(46.39, -75.96), // Maniwaki, Québec, Canada
    'YQI': LatLng(43.83, -66.09), // Yarmouth Airport, Canada
    'OYU': LatLng(48.56, -81.38), // Timmins, Ontario, Canada (?)
    'YZV': LatLng(50.23, -66.27), // Sept Isles, Québec, Canada
    'YAH': LatLng(53.76, -73.67), // La Grande IV Hydro Plant, Québec, Canada
    'YVP': LatLng(58.11, -68.42), // Kuujjuaq, Québec, Canada
    'YSM': LatLng(60.01, -112), // Ft. Smith, NW Territories, Canada
    'YJT': LatLng(48.54, -58.55), // Stephenville, Newfoundland, Canada
    'YYR': LatLng(53.33, -60.42), // Goose Bay, Newfoundland, Canada
    'YYQ': LatLng(58.73, -94.07), // Churchill, Manitoba, Canada
    'YZT': LatLng(50.69, -127.37), // Port Hardy, British Columbia, Canada
    'YYE': LatLng(58.54, -122.6), // Ft. Nelson, British Columbia, Canada
    'WSE': LatLng(53.53, -114.08), // Edmonton, Alberta, Canada
    '76225': LatLng(28.73, -105.93), // Chihuahua, Mexico
    '76526': LatLng(22.75, -102.51), // Zachatecas, Mexico
    '76458': LatLng(23.16, -106.27), // Mazatlán, Mexico
    'ADN': LatLng(25.87, -100.23), // Aeropuerto Del Norte, Monterrey, Mexico
    'SGF': LatLng(37.24, -93.38), // Springfield, Missouri, USA
    'LZK': LatLng(34.83, -92.25), // Little Rock, Arkansas, USA
    'FWD': LatLng(32.83, -97.30), // Fort Worth, Texas, USA
    'BRO': LatLng(25.91, -97.42), // Brownsville, Texas, USA
    'CRP': LatLng(27.77, -97.50), // Corpus Christi, Texas, USA
    'LCH': LatLng(30.12, -93.22), // Lake Charles, Louisiana, USA
    'UNR': LatLng(44.07, -103.21), // Rapid City, South Dakota, USA
    'ABR': LatLng(45.45, -98.41), // Aberdeen, South Dakota, USA
    'BIS': LatLng(46.77, -100.75), // Bismarck, North Dakota, USA
    'GGW': LatLng(48.21, -106.62), // Glasgow, Montana, USA
    'TFX': LatLng(47.46, -111.38), // Great Falls, Montana, USA
    'MPX': LatLng(44.85, -93.56), // Minneapolis, Minnesota, USA
    'DVN': LatLng(41.61, -90.58), // Davenport, Iowa, USA
    'ILX': LatLng(40.15, -89.33), // Lincoln, Illinois, USA
    'LIX': LatLng(30.33, -89.82), // Slidell, Louisiana, USA
    'DDC': LatLng(37.76, -99.96), // Dodge City, Kansas, USA
    'AMA': LatLng(35.22, -101.71), // Amarillo, Texas, USA
    'MAF': LatLng(31.94, -102.18), // Midland, Texas, USA
    'SHV': LatLng(32.45, -93.84), // Shreveport, Louisiana, USA
    'BMX': LatLng(33.17, -86.77), // Birmingham, Alabama, USA
    'BNA': LatLng(36.12, -86.68), // Nashville, Tennessee, USA
    'ILN': LatLng(39.42, -83.82), // Wilmington, Ohio, USA
    'DTX': LatLng(42.70, -83.47), // Detroit, Michigan, USA
    'APX': LatLng(44.91, -84.72), // Gaylord, Michigan, USA
    'GRB': LatLng(44.48, -88.13), // Green Bay, Wisconsin, USA
    'GSO': LatLng(36.10, -79.94), // Greensboro, North Carolina, USA
    'IAD': LatLng(38.95, -77.45), // Dulles, Virginia, USA
    'INL': LatLng(48.56, -93.40), // International Falls, Minnesota, USA
    'FFC': LatLng(33.36, -84.57), // Peachtree City, Georgia, USA
    'KEY': LatLng(24.56, -81.75), // Key West, Florida, USA
    'MFL': LatLng(25.75, -80.38), // Miami, Florida, USA
    'TBW': LatLng(27.70, -82.40), // Tampa Bay, Florida, USA
    'JAX': LatLng(30.49, -81.69), // Jacksonville, Florida, USA
    'CHS': LatLng(32.90, -80.03), // Charleston, South Carolina, USA
    'MHX': LatLng(34.72, -76.66), // Morehead City, North Carolina, USA
    'RNK': LatLng(37.20, -80.41), // Blacksburg, Virginia, USA
    'PIT': LatLng(40.49, -80.23), // Pittsburgh, Pennsylvania, USA
    'WAL': LatLng(37.94, -75.47), // Wallops Island, Virginia, USA
    'OKX': LatLng(40.86, -72.86), // Upton, New York, USA
    'ALB': LatLng(42.75, -73.80), // Albany, New York, USA
    'GYX': LatLng(43.89, -70.25), // Gray, Maine, USA
    'CAR': LatLng(46.87, -68.01), // Caribou, Maine, USA
    'TUS': LatLng(32.12, -110.93), // Tucson, Arizona, USA
    'FGZ': LatLng(35.14, -111.67), // Flagstaff, Arizona, USA
    'NKX': LatLng(32.87, -117.14), // San Diego, California, USA
    'VBG': LatLng(34.73, -120.58), // Vandenberg, California, USA
    'OAK': LatLng(37.72, -122.22), // Oakland, California, USA
    'REV': LatLng(39.56, -119.80), // Reno, Nevada, USA
    'MFR': LatLng(42.37, -122.87), // Medford, Oregon, USA
    'SLE': LatLng(44.91, -123.00), // Salem, Oregon, USA
    'OTX': LatLng(47.68, -117.63), // Spokane, Washington, USA
    'UIL': LatLng(47.94, -124.56), // Quillayute, Washington, USA
    'TOP': LatLng(39.07, -95.62), // Topeka, Kansas, USA
    'ABQ': LatLng(35.04, -106.62), // Albuquerque, New Mexico, USA
    'EPZ': LatLng(31.87, -106.70), // El Paso, Texas, USA
    'OAX': LatLng(41.30, -96.36), // Omaha, Nebraska, USA
    'SLC': LatLng(40.77, -111.97), // Salt Lake City, Utah, USA
    'BOI': LatLng(43.56, -116.22), // Boise, Idaho, USA
    'LKN': LatLng(40.87, -115.73), // Elko, Nevada, USA
    'RIW': LatLng(43.06, -108.47), // Riverton, Wyoming, USA
    'GJT': LatLng(39.12, -108.53), // Grand Junction, Colorado, USA
    'DRT': LatLng(29.37, -100.92), // Del Rio, Texas, USA
    'VEF': LatLng(36.08, -115.17), // Las Vegas, Nevada, USA
    'OUN': LatLng(35.18, -97.44), // Norman, Oklahoma, USA
    'PASN': LatLng(57.17, -170.22), // St. Paul Island, Alaska, USA
    'PACD': LatLng(55.21, -162.73), // Cold Bay, Alaska, USA
    'PAKN': LatLng(58.68, -156.65), // King Salmon, Alaska, USA
    'PAMC': LatLng(62.95, -155.60), // McGrath, Alaska, USA
    'PANC': LatLng(61.17, -150.00), // Anchorage, Alaska, USA
    'PADQ': LatLng(57.75, -152.49), // Kodiak, Alaska, USA
    'PABE': LatLng(60.78, -161.8), // Bethel, Alaska, USA
    'PAOM': LatLng(64.51, -165.44), // Nome, Alaska, USA
    'PAOT': LatLng(66.88, -162.60), // Kotzebue, Alaska, USA
    'PABR': LatLng(71.28, -156.77), // Utqiaġvik (Barrow), Alaska, USA
    'PAFA': LatLng(64.81, -147.85), // Fairbanks, Alaska, USA
    'PAYA': LatLng(59.50, -139.66), // Yakutat, Alaska, USA
    'PANT': LatLng(55.04, -131.57), // Annette Island (Ketchikan), Alaska, USA
    'PHLI': LatLng(21.98, -159.33), // Lihue, Hawaii, USA
    'PHTO': LatLng(19.72, -155.05), // Hilo, Hawaii, USA
    'NSTU': LatLng(-14.33, -170.71), // Pago Pago, American Samoa
    'TJSJ': LatLng(18.43, -66), // San Juan, Puerto Rico
    'MDSD': LatLng(18.43, -69.88), // Santo Domingo, Dominican Republic
    'MKJP': LatLng(17.93, -76.79), // Kingston, Jamaica
    'TNCC': LatLng(12.2, -68.97), // Willemstad, Curaçao
  };

}

