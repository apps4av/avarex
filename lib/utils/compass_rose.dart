import 'package:avaremp/constants.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Magnetic compass rose drawn on the 10 NM range ring.
class CompassRose {
  static const double ringNm = 10;
  static const double _labelNm = 11.6;

  static const Map<int, String> _labels = {
    0: "N",
    45: "NE",
    90: "E",
    135: "SE",
    180: "S",
    225: "SW",
    270: "W",
    315: "NW",
  };

  /// Outward ticks every 5° magnetic (longer/thicker at 15° and 45°).
  static List<Polyline> ticks(LatLng center, double variation) {
    final GeoCalculations geo = GeoCalculations();
    return [
      for (int mag = 0; mag < 360; mag += 5)
        Polyline(
          points: [
            geo.calculateOffset(center, ringNm, mag + variation),
            geo.calculateOffset(
                center,
                mag % 45 == 0
                    ? 11.15
                    : (mag % 15 == 0 ? 10.9 : 10.4),
                mag + variation),
          ],
          color: Constants.distanceCircleColor,
          strokeWidth: mag % 45 == 0
              ? 4.5
              : (mag % 15 == 0 ? 3.5 : 3.0),
        ),
    ];
  }

  /// Cardinal / intercardinal labels just outside the major ticks.
  /// [labelAngle] keeps text upright in track-up mode.
  static List<Marker> labelMarkers(
      LatLng center, double variation, double labelAngle) {
    final GeoCalculations geo = GeoCalculations();
    return [
      for (final entry in _labels.entries)
        Marker(
          point: geo.calculateOffset(
              center, _labelNm, entry.key + variation),
          width: 36,
          height: 22,
          child: Transform.rotate(
            angle: labelAngle,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Constants.bottomNavBarBackgroundColor
                      .withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  entry.value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: entry.key % 90 == 0 ? 13 : 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }
}
