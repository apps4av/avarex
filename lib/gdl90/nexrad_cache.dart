import 'package:avaremp/constants.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image/image.dart';
import 'nexrad_medium_product.dart';
import 'nexrad_product.dart';
import 'dart:typed_data';
import 'package:latlong2/latlong.dart';
import 'package:image/image.dart' as img;

class NexradCache {

  /*
   * Northern hemisphere only
   * Cover 0 to 60 degrees latitude
   * With each box of 4 minutes = 60 * 60 / 4 = 900 rows
   *
   * Cover -180 to 180, longitude
   * With each box 48 minutes = 360 * 60 / 48 = 450 columns
   *
   * For practical purposes, only cover an area of 7.2 degree (lon) by 12 degree (lat). This
   * should be sufficient to have an area of about 350 miles by 350 miles at 60 latitude, more lower
   * Given regional nexrad is 250 miles by 250 miles, apply this limit
   *
   * = 12 * 60 / 4 = 180 rows
   * = 7.2 * 60 / 48 = 9 columns
   * = 1620 entries
   */

  /*
   * Northern hemisphere only
   * Cover 0 to 60 degrees latitude
   * With each box of 20 minutes = 60 * 60 / 20 = 180 rows
   *
   * Cover -180 to 180, longitude
   * With each box 240 minutes = 360 * 60 / 240 = 90 columns
   *
   * For practical purposes, only cover an area of 60 degree (lon) by 30 degree (lat). This
   * should be sufficient to have an area of entire USA 48 states
   *
   * = 30 * 60 / 20 = 90 rows
   * = 60 * 60 / 240 = 15 columns
   * = 1350 entries
   */

  final Map<int, NexradImage> _cacheNexrad = {};
  final Map<int, NexradImage> _cacheNexradConus = {};

  void putImg(NexradProduct product) {

    Map<int, NexradImage> map = (product is NexradMediumProduct ? _cacheNexrad : _cacheNexradConus);

    if (product.empty.isNotEmpty) {
      // Empty, make dummy bitmaps of all.
      for (int i = 0; i < product.empty.length; i++) {
        int block = product.empty[i];
        NexradImage? img = map.remove(block);
        img?.discard();
      }
    }
    if (product.full.isNotEmpty) {
      if (map[product.block] != null) {
        //Replace same block
        NexradImage? img = map.remove(product.block);
        img?.discard();
      }
      // put
      map[product.block] = NexradImage(product.full, product.block, product is NexradMediumProduct);
    }

    // remove expired
    map.removeWhere((block, image) {
      DateTime time = image.time;
      DateTime now = DateTime.now();
      Duration diff = now.difference(time);
      if(diff.inMinutes > Constants.weatherUpdateTimeMin) {
        return true;
      }
      return false;
    });
  }

  List<NexradImage> getNexrad() {
    // get only drawable images
    List<NexradImage> ret = [];
    for(NexradImage img in _cacheNexrad.values) {
      Uint8List? imgLocal = img.getImage();
      if(imgLocal != null) {
        // filter out that dont have images
        ret.add(img);
      }
    }
    return ret;
  }

  List<NexradImage> getNexradConus() {
    // get only drawable images
    List<NexradImage> ret = [];
    for(NexradImage img in _cacheNexradConus.values) {
      Uint8List? imgLocal = img.getImage();
      if(imgLocal != null) {
        // filter out that dont have images
        ret.add(img);
      }
    }
    return ret;
  }

}

class NexradImage {

  final DateTime time;
  final int _block;
  final bool _conus;
  final List<int>? _data;
  double _scaleX = 1;
  double _scaleY = 1;
  LatLng _coordinate = const LatLng(0, 0);
  Uint8List? _image;

  NexradImage(this._data, this._block, this._conus) : time = DateTime.now() {

    double scale;
    LatLng c;
    int rows = NexradProduct.numRows;
    int cols = NexradProduct.numCols;
    (c, scale) = _convertBlockNumberToLatLon(_block);
    _coordinate = c;

    //CONUS times 5
    _scaleX = _conus ? scale * 5 : scale;
    _scaleY = _conus ? 5 : 1;

    //If empty block, do not waste bitmap memory
    if((null == _data) || (_data.length < cols * rows)) {
      return;
    }

    // make bitmap
    int haveData = 0;
    final image = img.Image(width: cols, height: rows, numChannels: 4);
    // Iterate over its pixels
    for(int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        Pixel pixel = image.getPixel(col, row);
        int value = _data[col + row * cols];
        pixel.setRgba((value >> 16) & 0xFF, (value >> 8) & 0xFF, (value >> 0) & 0xFF, (value >> 24 & 0xFF));
        haveData += value != 0 ? 1 : 0;
      }
    }

    if(haveData == 0) {
      //waste of bitmap space
      return;
    }

    // Encode the resulting image to the PNG image format.
    _image = img.encodePng(image);
  }

  void discard() {
    _image = null;
  }

  LatLngBounds getBounds() {
    return LatLngBounds(
        LatLng(_coordinate.latitude, _coordinate.longitude),
        LatLng(_coordinate.latitude - _scaleY * NexradProduct.numRows / 60.0,
          _coordinate.longitude + _scaleX * NexradProduct.numCols / 60.0,));
  }

  Uint8List? getImage() {
    return _image;
  }

  (LatLng, double) _convertBlockNumberToLatLon(int blockNumber) {

    double lon;
    double lat;
    double scale;

    if (blockNumber < 405000) {
      int col = blockNumber % 450;
      int row = blockNumber ~/ 450;

      lat = (row.toDouble() + 1.0) *  4.0 / 60.0; // row + 1 as need top left lat
      lon = (col.toDouble() + 0.0) * 48.0 / 60.0;
      scale = 1.5; // each lon bin is 1.5 min below 60 deg
    }
    else {
      blockNumber -= 405000;
      blockNumber = blockNumber ~/ 2; // blocks inc by 2

      int col = blockNumber % 225;
      int row = blockNumber ~/ 225;

      lat = 60.0 + (row.toDouble() + 1.0) *  4.0 / 60.0; // row + 1 as need top left lat
      lon =  0.0 + (col.toDouble() + 0.0) * 96.0 / 60.0;
      scale = 3.0; // each lon bin is 3 min above 60 deg
    }

    if (lon > 180) {
      lon = lon - 360;
    }
    return (LatLng(lat, lon), scale);
  }
}