import 'package:avaremp/utils/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_material_design_icons/flutter_material_design_icons.dart';

/// Stadium / motor speedway "game" TFRs (14 CFR 99.7).
///
/// These TFRs apply (when the corresponding sporting event is in progress)
/// within a 3 NM radius and below 3000' AGL of any open-air stadium with a
/// seating capacity of 30,000+ that hosts MLB, NFL, NCAA Division I football,
/// or major motor speedway events.
///
/// Centers are stored here as a single self-contained list so adding/removing
/// venues only requires editing this file. The map screen references this
/// class to render the locations as orange circles plus a clustered icon
/// marker per venue.
class GameTfr {
  /// Layer name shown in the layer selector and in `AppSettings.getLayers()`.
  static const String layerName = 'Game TFR';

  /// 3 nautical miles in meters (per 14 CFR 99.7).
  static const double radiusMeters = 5556.0;

  /// Outline color for the circles (solid orange).
  static const Color borderColor = Color(0xFFFF8C00);

  /// Cluster configuration matched to the values used by other map clusters.
  static const int _maxClusterRadius = 160;
  static const int _disableClusteringAtZoom = 10;

  /// Geodesic helper used to position the label at the 12 o'clock point of
  /// the 3 NM ring (i.e. exactly on the ring, due north of the venue).
  static const Distance _distance = Distance();

  /// All known stadium / speedway centers used as game TFRs.
  ///
  /// Coordinates are approximate venue centers in WGS-84.
  static const List<GameTfrLocation> locations = [
    // ---------------- NFL ----------------
    GameTfrLocation('Lambeau Field', 44.5013, -88.0622),
    GameTfrLocation('Soldier Field', 41.8623, -87.6167),
    GameTfrLocation('AT&T Stadium', 32.7473, -97.0945),
    GameTfrLocation('Lumen Field', 47.5952, -122.3316),
    GameTfrLocation('MetLife Stadium', 40.8128, -74.0742),
    GameTfrLocation("Levi's Stadium", 37.4030, -121.9700),
    GameTfrLocation('SoFi Stadium', 33.9534, -118.3387),
    GameTfrLocation('Allegiant Stadium', 36.0908, -115.1830),
    GameTfrLocation('Gillette Stadium', 42.0909, -71.2643),
    GameTfrLocation('Hard Rock Stadium', 25.9580, -80.2389),
    GameTfrLocation('Lincoln Financial Field', 39.9008, -75.1675),
    GameTfrLocation('M&T Bank Stadium', 39.2780, -76.6227),
    GameTfrLocation('Acrisure Stadium', 40.4467, -80.0158),
    GameTfrLocation('Bank of America Stadium', 35.2258, -80.8528),
    GameTfrLocation('Caesars Superdome', 29.9509, -90.0815),
    GameTfrLocation('EverBank Stadium', 30.3239, -81.6373),
    GameTfrLocation('Northwest Stadium', 38.9078, -76.8645),
    GameTfrLocation('Ford Field', 42.3400, -83.0456),
    GameTfrLocation('GEHA Field at Arrowhead Stadium', 39.0489, -94.4839),
    GameTfrLocation('Highmark Stadium', 42.7738, -78.7870),
    GameTfrLocation('Huntington Bank Field', 41.5061, -81.6995),
    GameTfrLocation('Lucas Oil Stadium', 39.7601, -86.1639),
    GameTfrLocation('Mercedes-Benz Stadium', 33.7553, -84.4006),
    GameTfrLocation('NRG Stadium', 29.6847, -95.4107),
    GameTfrLocation('Nissan Stadium', 36.1665, -86.7713),
    GameTfrLocation('Paycor Stadium', 39.0954, -84.5160),
    GameTfrLocation('Raymond James Stadium', 27.9759, -82.5033),
    GameTfrLocation('State Farm Stadium', 33.5276, -112.2626),
    GameTfrLocation('Empower Field at Mile High', 39.7439, -105.0201),
    GameTfrLocation('U.S. Bank Stadium', 44.9737, -93.2581),

    // ---------------- MLB ----------------
    GameTfrLocation('Yankee Stadium', 40.8296, -73.9262),
    GameTfrLocation('Fenway Park', 42.3467, -71.0972),
    GameTfrLocation('Wrigley Field', 41.9484, -87.6553),
    GameTfrLocation('Dodger Stadium', 34.0739, -118.2400),
    GameTfrLocation('Oracle Park', 37.7786, -122.3893),
    GameTfrLocation('Citi Field', 40.7571, -73.8458),
    GameTfrLocation('Citizens Bank Park', 39.9061, -75.1665),
    GameTfrLocation('PNC Park', 40.4469, -80.0057),
    GameTfrLocation('Truist Park', 33.8908, -84.4678),
    GameTfrLocation('Petco Park', 32.7077, -117.1573),
    GameTfrLocation('Minute Maid Park', 29.7572, -95.3556),
    GameTfrLocation('Busch Stadium', 38.6226, -90.1928),
    GameTfrLocation('Comerica Park', 42.3390, -83.0485),
    GameTfrLocation('Progressive Field', 41.4962, -81.6852),
    GameTfrLocation('Globe Life Field', 32.7473, -97.0837),
    GameTfrLocation('Coors Field', 39.7559, -104.9942),
    GameTfrLocation('Chase Field', 33.4453, -112.0667),
    GameTfrLocation('T-Mobile Park', 47.5914, -122.3325),
    GameTfrLocation('Kauffman Stadium', 39.0517, -94.4803),
    GameTfrLocation('Great American Ball Park', 39.0975, -84.5077),
    GameTfrLocation('Target Field', 44.9817, -93.2776),
    GameTfrLocation('Rogers Centre', 43.6414, -79.3894),
    GameTfrLocation('Angel Stadium', 33.8003, -117.8827),
    GameTfrLocation('Sutter Health Park', 38.5800, -121.5135),
    GameTfrLocation('LoanDepot Park', 25.7781, -80.2196),
    GameTfrLocation('Tropicana Field', 27.7682, -82.6534),
    GameTfrLocation('Nationals Park', 38.8730, -77.0074),
    GameTfrLocation('Guaranteed Rate Field', 41.8300, -87.6338),
    GameTfrLocation('Oriole Park at Camden Yards', 39.2839, -76.6217),
    GameTfrLocation('American Family Field', 43.0280, -87.9712),

    // ---------------- NCAA D1 Football (selected 30k+ venues) ----------------
    GameTfrLocation('Michigan Stadium', 42.2658, -83.7487),
    GameTfrLocation('Beaver Stadium', 40.8121, -77.8563),
    GameTfrLocation('Ohio Stadium', 40.0017, -83.0197),
    GameTfrLocation('Kyle Field', 30.6097, -96.3399),
    GameTfrLocation('Neyland Stadium', 35.9550, -83.9251),
    GameTfrLocation('Tiger Stadium (LSU)', 30.4119, -91.1839),
    GameTfrLocation('Bryant-Denny Stadium', 33.2080, -87.5503),
    GameTfrLocation('Sanford Stadium', 33.9498, -83.3737),
    GameTfrLocation('Jordan-Hare Stadium', 32.6024, -85.4894),
    GameTfrLocation('Memorial Stadium (Clemson)', 34.6788, -82.8434),
    GameTfrLocation('Notre Dame Stadium', 41.6986, -86.2336),
    GameTfrLocation('Camp Randall Stadium', 43.0700, -89.4128),
    GameTfrLocation('Spartan Stadium', 42.7283, -84.4848),
    GameTfrLocation('Memorial Stadium (Nebraska)', 40.8208, -96.7058),
    GameTfrLocation('Doak Campbell Stadium', 30.4380, -84.3043),
    GameTfrLocation('Ben Hill Griffin Stadium', 29.6499, -82.3486),
    GameTfrLocation('Williams-Brice Stadium', 33.9728, -81.0193),
    GameTfrLocation('LA Memorial Coliseum', 34.0141, -118.2879),
    GameTfrLocation('Rose Bowl', 34.1611, -118.1675),
    GameTfrLocation('Stanford Stadium', 37.4348, -122.1611),
    GameTfrLocation('Husky Stadium', 47.6502, -122.3017),
    GameTfrLocation('Autzen Stadium', 44.0584, -123.0683),
    GameTfrLocation('Reser Stadium', 44.5594, -123.2818),
    GameTfrLocation('Sun Devil Stadium', 33.4264, -111.9325),
    GameTfrLocation('Arizona Stadium', 32.2287, -110.9486),
    GameTfrLocation('Folsom Field', 40.0093, -105.2660),
    GameTfrLocation('Rice-Eccles Stadium', 40.7607, -111.8488),
    GameTfrLocation('LaVell Edwards Stadium', 40.2575, -111.6547),
    GameTfrLocation('Memorial Stadium (Oklahoma)', 35.2058, -97.4423),
    GameTfrLocation('Boone Pickens Stadium', 36.1267, -97.0669),
    GameTfrLocation('Amon G. Carter Stadium', 32.7095, -97.3681),
    GameTfrLocation('Razorback Stadium', 36.0686, -94.1786),
    GameTfrLocation('Davis Wade Stadium', 33.4564, -88.7935),
    GameTfrLocation('Vaught-Hemingway Stadium', 34.3618, -89.5345),
    GameTfrLocation('Faurot Field', 38.9356, -92.3331),
    GameTfrLocation('Kroger Field', 38.0220, -84.5052),
    GameTfrLocation('Vanderbilt Stadium', 36.1444, -86.8053),
    GameTfrLocation('Kenan Memorial Stadium', 35.9078, -79.0476),
    GameTfrLocation('Wallace Wade Stadium', 36.0024, -78.9410),
    GameTfrLocation('Lane Stadium', 37.2200, -80.4181),
    GameTfrLocation('Scott Stadium', 38.0307, -78.5145),
    GameTfrLocation('Carter-Finley Stadium', 35.8002, -78.7196),
    GameTfrLocation('Memorial Stadium (Cal)', 37.8709, -122.2509),
    GameTfrLocation('Bill Snyder Family Stadium', 39.2020, -96.5928),

    // ---------------- Major Motor Speedways ----------------
    GameTfrLocation('Daytona International Speedway', 29.1850, -81.0700),
    GameTfrLocation('Talladega Superspeedway', 33.5664, -86.0681),
    GameTfrLocation('Indianapolis Motor Speedway', 39.7950, -86.2348),
    GameTfrLocation('Charlotte Motor Speedway', 35.3528, -80.6831),
    GameTfrLocation('Bristol Motor Speedway', 36.5158, -82.2569),
    GameTfrLocation('Pocono Raceway', 41.0552, -75.5172),
    GameTfrLocation('Watkins Glen International', 42.3372, -76.9275),
    GameTfrLocation('Texas Motor Speedway', 33.0375, -97.2825),
    GameTfrLocation('Las Vegas Motor Speedway', 36.2728, -115.0144),
    GameTfrLocation('Phoenix Raceway', 33.3756, -112.3081),
    GameTfrLocation('Sonoma Raceway', 38.1611, -122.4544),
    GameTfrLocation('Atlanta Motor Speedway', 33.3853, -84.3147),
    GameTfrLocation('Dover Motor Speedway', 39.1894, -75.5286),
    GameTfrLocation('Homestead-Miami Speedway', 25.4519, -80.4101),
    GameTfrLocation('Kansas Speedway', 39.1147, -94.8311),
    GameTfrLocation('Martinsville Speedway', 36.6328, -79.8533),
    GameTfrLocation('Michigan International Speedway', 42.0648, -84.2419),
    GameTfrLocation('Nashville Superspeedway', 36.0519, -86.4139),
    GameTfrLocation('New Hampshire Motor Speedway', 43.3633, -71.4625),
    GameTfrLocation('Richmond Raceway', 37.5917, -77.4203),
    GameTfrLocation('World Wide Technology Raceway', 38.6505, -90.1428),
    GameTfrLocation('Iowa Speedway', 41.5947, -93.0633),
  ];

  /// Build the orange-outline circles layer for the map. Returns a
  /// [CircleLayer] containing one 3 NM unfilled ring per venue.
  static Widget buildLayer({double opacity = 1.0}) {
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: CircleLayer(
          circles: [
            for (final GameTfrLocation l in locations)
              CircleMarker(
                point: LatLng(l.latitude, l.longitude),
                radius: radiusMeters,
                useRadiusInMeter: true,
                color: Colors.transparent,
                borderColor: borderColor,
                borderStrokeWidth: 4,
              ),
          ],
        ),
      ),
    );
  }

  /// Build a clustered marker layer that labels each venue with a stadium
  /// icon and shows the venue name in a toast when tapped. Marker clustering
  /// keeps the map readable when many venues are visible at once, mirroring
  /// the behavior of the METAR/TFR clusters.
  static Widget buildCluster(BuildContext context, {double opacity = 1.0}) {
    return Opacity(
      opacity: opacity,
      child: MarkerClusterLayerWidget(
        options: MarkerClusterLayerOptions(
          showPolygon: false,
          spiderfyCluster: false,
          maxClusterRadius: _maxClusterRadius,
          disableClusteringAtZoom: _disableClusteringAtZoom,
          animationsOptions: const AnimationsOptions(
            zoom: Duration.zero,
            fitBound: Duration.zero,
            centerMarker: Duration.zero,
            spiderfy: Duration.zero,
          ),
          builder: (context, markers) =>
              Container(color: Colors.transparent),
          markers: [
            for (final GameTfrLocation l in locations)
              Marker(
                // 12 o'clock on the 3 NM ring (due north of venue center)
                point: _distance.offset(
                    LatLng(l.latitude, l.longitude), radiusMeters, 0),
                alignment: Alignment.center,
                child: GestureDetector(
                  onTap: () {
                    Toast.showToast(
                      context,
                      "${l.name}\nGame TFR (3 NM, SFC-3000' AGL when active)",
                      Icon(MdiIcons.stadium, color: Colors.black),
                      30,
                    );
                  },
                  child: Icon(MdiIcons.stadium, color: Colors.black),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single game-TFR venue location.
class GameTfrLocation {
  final String name;
  final double latitude;
  final double longitude;

  const GameTfrLocation(this.name, this.latitude, this.longitude);
}
