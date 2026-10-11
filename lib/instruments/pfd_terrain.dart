import 'dart:math';

import 'package:avaremp/instruments/pfd_painter.dart';
import 'package:avaremp/instruments/pfd_runway.dart';
import 'package:avaremp/place/elevation_cache.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Builds [PfdData.terrain] at 1 Hz from the downloaded elevation tiles.
///
/// Along-track spacing is quadratic so the first mile is dense enough for
/// a 3D ground (a uniform 1 NM grid collapses onto the horizon).
class PfdTerrainSampler {
  static const int cols = 41;
  static const int rows = 48;
  static const double nearFt = 200;
  static const double aheadNm = 18;
  static const double halfCrossNm = 8;
  static const double minMoveNm = 0.15;
  static const double minTurnDeg = 12;

  LatLng? _last;
  double? _lastHdg;
  bool _busy = false;

  Future<void> update(Position position) async {
    if (_busy) return;
    final List<String> layers = Storage().settings.getLayers();
    final List<double> opacity = Storage().settings.getLayersOpacity();
    final int pfd = layers.indexOf('PFD');
    if (pfd < 0 || opacity[pfd] <= 0) {
      Storage().pfdData.terrain = null;
      return;
    }

    final LatLng here = LatLng(position.latitude, position.longitude);
    final PfdData pfdData = Storage().pfdData;
    final double hdg = pfdData.ahrsHeadingLive
        ? (pfdData.yaw + Storage().area.variation + 360) % 360
        : position.heading;

    if (_last != null && _lastHdg != null) {
      final double moved = const Distance(calculator: Haversine())
          .as(LengthUnit.Meter, _last!, here) / 1852.0;
      final double turn = _angle(hdg, _lastHdg!);
      if (moved < minMoveNm && turn < minTurnDeg) return;
    }

    _busy = true;
    try {
      final List<LatLng> pts = _grid(here, hdg);
      final List<double?> elev = await ElevationCache.getElevationOfPoints(pts);
      bool any = false;
      for (final e in elev) {
        if (e != null) {
          any = true;
          break;
        }
      }
      Storage().pfdData.terrain =
          any ? PfdTerrain(pts: pts, elevFt: elev, cols: cols, rows: rows) : null;
      _last = here;
      _lastHdg = hdg;
    } finally {
      _busy = false;
    }
  }

  static List<LatLng> _grid(LatLng origin, double headingTrue) {
    final double h = GeoCalculations.toRadians(headingTrue);
    final double cosH = cos(h);
    final double sinH = sin(h);
    final double lat0 = origin.latitude;
    final double lon0 = origin.longitude;
    final double cosLat = cos(GeoCalculations.toRadians(lat0));
    final List<LatLng> out = [];
    for (int r = 0; r < rows; r++) {
      final double t = r / (rows - 1);
      final double alongFt = nearFt + (aheadNm * 6076.12 - nearFt) * pow(t, 1.7);
      for (int c = 0; c < cols; c++) {
        final double u = (c / (cols - 1) - 0.5) * 2;
        final double crossNm = halfCrossNm * u * (0.55 + 0.45 * u.abs());
        final double crossFt = crossNm * 6076.12;
        final double n = alongFt * cosH - crossFt * sinH;
        final double e = alongFt * sinH + crossFt * cosH;
        out.add(LatLng(
          lat0 + n / PfdRunwayEnd.ftPerDegLat,
          lon0 + e / (PfdRunwayEnd.ftPerDegLat * cosLat),
        ));
      }
    }
    return out;
  }

  static double _angle(double a, double b) {
    double d = (a - b).abs() % 360;
    if (d > 180) d = 360 - d;
    return d;
  }
}
