/*
Copyright (c) 2015, Apps4Av Inc. (apps4av.com)
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
    *     * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the[...]
    *
    *     THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AN[...]
*/

import 'dart:math' as math;

/// A class that finds tile at a given location and zooms
/// See gdal2tiles.py.
/// Optimized to use tables at run time, and avoid divisions
class Epsg900913 {

  /// To get tile info.
  static final double _size = 512; // tile size in pixels
  static final double _sizeInverse = 1.0 / _size;
  static final double _originShift = 2 * math.pi * 6378137.0 / 2.0;
  static final double _initialResolution = 2 * math.pi * 6378137.0 / _size;
  static final double _pi180 = math.pi / 180.0;
  static final double _pi2 = math.pi / 2.0;
  static final double _pi360 = math.pi / 360.0;
  static final double _pi180Inverse = 1.0 / _pi180;
  static final double _originShift180 = _originShift / 180.0;
  static final double _originShift180Inverse = 1.0 / _originShift180;

  // Make a zoom table for resolution so we don't have to compute it often
  static final List<double> _zoomTable = List<double>.generate(
      20, (i) => _initialResolution / math.pow(2, i).toDouble(),
      growable: false);

  // Make a zoom table for inverse resolution so we don't have to compute it often
  static final List<double> _zoomTableInv = List<double>.generate(
      _zoomTable.length, (i) => 1.0 / _zoomTable[i],
      growable: false);

  int _mTx = 0;
  int _mTy = 0;
  double _mLonL = 0.0;
  double _mLatU = 0.0;
  double _mLonR = 0.0;
  double _mLatD = 0.0;

  void _findBounds(double zoom) {
    _mLonL = metersToLon(xPixelsToMeters(zoom, _mTx * _size));
    _mLonR = metersToLon(xPixelsToMeters(zoom, (_mTx + 1) * _size));

    _mLatD = metersToLat(yPixelsToMeters(zoom, _mTy * _size));
    _mLatU = metersToLat(yPixelsToMeters(zoom, (_mTy + 1) * _size));
  }

  /// Construct from latitude, longitude and zoom
  Epsg900913.fromLatLon(double lat, double lon, double zoom) {
    final double mx = lonToMeters(lon);
    final double my = latToMeters(lat);

    final double px = xMetersToPixels(zoom, mx);
    final double py = yMetersToPixels(zoom, my);

    // tile number
    _mTx = xPixelsToTile(px);
    _mTy = yPixelsToTile(py);

    _findBounds(zoom);
  }

  /// Construct from tile coordinates (tx, ty) and zoom
  Epsg900913.fromTile(int tx, int ty, double zoom) {
    _mTx = tx;
    _mTy = ty;

    _findBounds(zoom);
  }

  /*
   * Misc. calls
   */
  static double getResolution(double zoom) {
    return _zoomTable[zoom.toInt()];
  }

  static double getInvResolution(double zoom) {
    return _zoomTableInv[zoom.toInt()];
  }

  static double latToMeters(double lat) {
    final double my = math.log(math.tan((90.0 + lat) * _pi360)) * _pi180Inverse;
    return my * _originShift180;
  }

  static double lonToMeters(double lon) {
    return lon * _originShift180;
  }

  static double metersToLat(double my) {
    double lat = my * _originShift180Inverse;
    lat = _pi180Inverse * (2.0 * math.atan(math.exp(lat * _pi180)) - _pi2);
    return lat;
  }

  static double metersToLon(double mx) {
    return (mx * _originShift180Inverse);
  }

  static double xPixelsToMeters(double zoom, double px) {
    return px * getResolution(zoom) - _originShift;
  }

  static double yPixelsToMeters(double zoom, double py) {
    return py * getResolution(zoom) - _originShift;
  }

  static double xMetersToPixels(double zoom, double mx) {
    return (mx + _originShift) * getInvResolution(zoom);
  }

  static double yMetersToPixels(double zoom, double my) {
    return (my + _originShift) * getInvResolution(zoom);
  }

  static int xPixelsToTile(double px) {
    return (px * _sizeInverse).ceil() - 1;
  }

  static int yPixelsToTile(double py) {
    return (py * _sizeInverse).ceil() - 1;
  }

  static int xMetersToTile(double zoom, double mx) {
    final double px = xMetersToPixels(zoom, mx);
    return xPixelsToTile(px);
  }

  static int yMetersToTile(double zoom, double my) {
    final double py = yMetersToPixels(zoom, my);
    return yPixelsToTile(py);
  }

  /*
   * Tile col/rows
   */
  int getTilex() => _mTx;

  int getTiley() => _mTy;

  double getLonUpperLeft() => _mLonL;

  double getLonLowerLeft() => _mLonL;

  double getLonLowerRight() => _mLonR;

  double getLonUpperRight() => _mLonR;

  double getLonCenter() => (_mLonR + _mLonL) / 2.0;

  double getLatUpperLeft() => _mLatU;

  double getLatUpperRight() => _mLatU;

  double getLatLowerRight() => _mLatD;

  double getLatLowerLeft() => _mLatD;

  double getLatCenter() => (_mLatU + _mLatD) / 2.0;

  /*
   * Find longitude of offset from this tile projection
   */
  static double getLongitudeOf(double ofs, double lon, double zoom) {
    double px = xMetersToPixels(zoom, lonToMeters(lon));
    px += ofs;
    double mx = xPixelsToMeters(zoom, px);
    return metersToLon(mx);
  }

  /*
   * Find latitude of offset from this tile projection
   */
  static double getLatitudeOf(double ofs, double lat, double zoom) {
    double py = yMetersToPixels(zoom, latToMeters(lat));
    py -= ofs;
    double my = yPixelsToMeters(zoom, py);
    return metersToLat(my);
  }

  /*
   * Find offset X of this given longitude
   */
  static double getOffsetX(double lon, double lon2, double zoom) {
    double px0 = xMetersToPixels(zoom, lonToMeters(lon2));
    double px1 = xMetersToPixels(zoom, lonToMeters(lon));
    return px0 - px1;
  }

  /*
   * Find offset Y of this given latitude
   */
  static double getOffsetY(double lat, double lat2, double zoom) {
    double py0 = yMetersToPixels(zoom, latToMeters(lat2));
    double py1 = yMetersToPixels(zoom, latToMeters(lat));
    return py1 - py0;
  }
}