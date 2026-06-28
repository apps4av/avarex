import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ImageUtils {
  static Future<ui.Image> loadImageFromAssets(String imageName) async {
    final data = await rootBundle.load('assets/images/$imageName');
    return decodeImageFromList(data.buffer.asUint8List());
  }

}

/// [ImageProvider] that serves an already-decoded [ui.Image] without
/// re-decoding any encoded bytes. The framework receives a [ui.Image.clone]
/// so it can manage/dispose its own handle while the caller keeps ownership of
/// the original image. The clone shares the underlying pixel buffer, so this
/// adds no extra bitmap memory (unlike wrapping the encoded bytes in a
/// [MemoryImage], which decodes a second full-size copy).
class UiImageProvider extends ImageProvider<UiImageProvider> {
  final ui.Image image;

  UiImageProvider(this.image);

  @override
  Future<UiImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<UiImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(UiImageProvider key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(
      Future<ImageInfo>.value(ImageInfo(image: image.clone(), scale: 1.0)),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is UiImageProvider && other.image.isCloneOf(image);

  @override
  int get hashCode => image.hashCode;
}