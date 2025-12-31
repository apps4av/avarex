import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ImageUtils {
  static Future<ui.Image> loadImageFromAssets(String imageName) async {
    final data = await rootBundle.load('assets/images/$imageName');
    return decodeImageFromList(data.buffer.asUint8List());
  }

}