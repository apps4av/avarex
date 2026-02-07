import 'package:avaremp/weather/metar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class CeilingLayer {
  static const double _cellSizeDeg = 0.5;
  static const double _opacity = 0.45;
  static const double _radiusMiles = 500;
  static const double _milesToMeters = 1609.34;
  static const int _cellKeyShift = 12;

  PolygonLayer? _cachedLayer;
  int? _cachedAltitudeFt;
  int _cachedMetarRevision = -1;
  LatLng? _cachedCenterRounded;

  PolygonLayer build({
    required int altitudeFt,
    required int metarRevision,
    required LatLng current,
    required List<Metar> metars,
  }) {
    final LatLng currentRounded = LatLng(
      (current.latitude * 100).roundToDouble() / 100,
      (current.longitude * 100).roundToDouble() / 100,
    );
    if(_cachedLayer != null &&
        _cachedAltitudeFt == altitudeFt &&
        _cachedMetarRevision == metarRevision &&
        _cachedCenterRounded != null &&
        _cachedCenterRounded!.latitude == currentRounded.latitude &&
        _cachedCenterRounded!.longitude == currentRounded.longitude) {
      return _cachedLayer!;
    }
    _cachedAltitudeFt = altitudeFt;
    _cachedMetarRevision = metarRevision;
    _cachedCenterRounded = currentRounded;

    final int latCells = (180 / _cellSizeDeg).ceil();
    final int lonCells = (360 / _cellSizeDeg).ceil();
    final int maxLatIndex = latCells - 1;
    final int maxLonIndex = lonCells - 1;
    final Map<int, int> cellCeilings = {};
    final double radiusMeters = _radiusMiles * _milesToMeters;
    final Distance distanceCalc = const Distance();

    for(Metar m in metars) {
      int? ceilingFt = m.getCeilingFt();
      if(ceilingFt == null) {
        continue;
      }
      double distanceMeters = distanceCalc.as(LengthUnit.Meter, current, m.coordinate);
      if(distanceMeters > radiusMeters) {
        continue;
      }
      int cellX = ((m.coordinate.longitude + 180) / _cellSizeDeg).floor();
      int cellY = ((m.coordinate.latitude + 90) / _cellSizeDeg).floor();
      if(cellX < 0) {
        cellX = 0;
      }
      else if(cellX > maxLonIndex) {
        cellX = maxLonIndex;
      }
      if(cellY < 0) {
        cellY = 0;
      }
      else if(cellY > maxLatIndex) {
        cellY = maxLatIndex;
      }
      int key = (cellY << _cellKeyShift) + cellX;
      int? existing = cellCeilings[key];
      if(existing == null || ceilingFt < existing) {
        cellCeilings[key] = ceilingFt;
      }
    }

    List<Polygon> polygons = [];
    for(MapEntry<int, int> entry in cellCeilings.entries) {
      if(altitudeFt <= entry.value) {
        continue;
      }
      int cellY = entry.key >> _cellKeyShift;
      int cellX = entry.key & ((1 << _cellKeyShift) - 1);
      double south = -90 + cellY * _cellSizeDeg;
      double west = -180 + cellX * _cellSizeDeg;
      double north = south + _cellSizeDeg;
      double east = west + _cellSizeDeg;
      south = _clampLatitude(south);
      north = _clampLatitude(north);
      west = _clampLongitude(west);
      east = _clampLongitude(east);
      if(south >= north || west >= east) {
        continue;
      }
      LatLng center = LatLng(
        (south + north) / 2,
        (west + east) / 2,
      );
      double distanceMeters = distanceCalc.as(LengthUnit.Meter, current, center);
      if(distanceMeters > radiusMeters) {
        continue;
      }
      polygons.add(Polygon(
        points: [
          LatLng(south, west),
          LatLng(south, east),
          LatLng(north, east),
          LatLng(north, west),
        ],
        color: Colors.black.withValues(alpha: _opacity),
        borderColor: Colors.transparent,
        borderStrokeWidth: 0,
      ));
    }

    _cachedLayer = PolygonLayer(polygons: polygons);
    return _cachedLayer!;
  }

  double _clampLatitude(double value) {
    if(value > 90) {
      return 90;
    }
    if(value < -90) {
      return -90;
    }
    return value;
  }

  double _clampLongitude(double value) {
    if(value > 180) {
      return 180;
    }
    if(value < -180) {
      return -180;
    }
    return value;
  }
}
