import 'dart:typed_data';

import 'package:avaremp/visual_traffic/luma_frame.dart';
import 'package:image/image.dart' as img;

/// A small grayscale JPEG of the upright picture, for a viewer on Link.
class PreviewPicture {
  const PreviewPicture(this.jpeg, this.width, this.height);

  final Uint8List jpeg;
  final int width;
  final int height;
}

class PreviewEncoder {
  /// Largest JPEG that, base64 encoded with its JSON wrapper, still fits one
  /// UDP datagram that every platform can send (about 9 KB on iOS).
  static const int maxBytes = 5800;
  static const int defaultWidth = 240;

  static const List<int> _qualities = [55, 40, 30, 20, 12];

  /// Returns null when even the lowest quality is too large.
  static PreviewPicture? encode(LumaFrame frame, {int width = defaultWidth}) {
    int height = (width * frame.height / frame.width).round();
    if (height < 1) {
      height = 1;
    }
    final GrayImage small = frame.resize(width, height);
    final img.Image image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: small.data.buffer,
      numChannels: 1,
    );
    for (final int quality in _qualities) {
      final Uint8List jpeg = img.encodeJpg(image, quality: quality);
      if (jpeg.length <= maxBytes) {
        return PreviewPicture(jpeg, width, height);
      }
    }
    return null;
  }
}
