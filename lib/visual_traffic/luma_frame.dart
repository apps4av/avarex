import 'dart:typed_data';

/// A small 8-bit grayscale picture. Row `y` starts at `y * width`.
class GrayImage {
  GrayImage(this.width, this.height, this.data);

  GrayImage.blank(this.width, this.height) : data = Uint8List(width * height);

  final int width;
  final int height;
  final Uint8List data;

  int at(int x, int y) => data[y * width + x];

  /// Shrinks by a whole number [factor], averaging each block.
  GrayImage shrink(int factor) {
    final int f = factor < 1 ? 1 : factor;
    final int outW = width ~/ f;
    final int outH = height ~/ f;
    final Uint8List out = Uint8List(outW * outH);
    final int area = f * f;
    for (int oy = 0; oy < outH; oy++) {
      for (int ox = 0; ox < outW; ox++) {
        int sum = 0;
        for (int dy = 0; dy < f; dy++) {
          final int row = (oy * f + dy) * width + ox * f;
          for (int dx = 0; dx < f; dx++) {
            sum += data[row + dx];
          }
        }
        out[oy * outW + ox] = sum ~/ area;
      }
    }
    return GrayImage(outW, outH, out);
  }
}

/// The brightness plane of a camera frame, seen through a rotation.
///
/// Phone cameras deliver frames in the sensor's own orientation. The pilot
/// sees the picture upright. [quarterTurns] is how many clockwise quarter
/// turns turn the sensor frame upright. [width] and [height] and every `x`,
/// `y` this class takes are in the upright picture.
///
/// The rotation is not performed on the bytes. Each upright pixel is found
/// with one linear index: `base + x * stepX + y * stepY`.
class LumaFrame {
  LumaFrame({
    required this.bytes,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.rowStride,
    required this.quarterTurns,
  })  : assert(quarterTurns >= 0 && quarterTurns < 4),
        assert(rowStride >= sourceWidth),
        assert(bytes.length >= rowStride * (sourceHeight - 1) + sourceWidth) {
    switch (quarterTurns) {
      case 0:
        _base = 0;
        _stepX = 1;
        _stepY = rowStride;
      case 1:
        _base = (sourceHeight - 1) * rowStride;
        _stepX = -rowStride;
        _stepY = 1;
      case 2:
        _base = (sourceHeight - 1) * rowStride + sourceWidth - 1;
        _stepX = -1;
        _stepY = -rowStride;
      default:
        _base = sourceWidth - 1;
        _stepX = rowStride;
        _stepY = -1;
    }
  }

  /// Builds a frame from an upright [GrayImage] (no rotation, no padding).
  factory LumaFrame.fromGray(GrayImage image) {
    return LumaFrame(
      bytes: image.data,
      sourceWidth: image.width,
      sourceHeight: image.height,
      rowStride: image.width,
      quarterTurns: 0,
    );
  }

  final Uint8List bytes;
  final int sourceWidth;
  final int sourceHeight;
  final int rowStride;
  final int quarterTurns;

  late final int _base;
  late final int _stepX;
  late final int _stepY;

  int get width => quarterTurns.isEven ? sourceWidth : sourceHeight;
  int get height => quarterTurns.isEven ? sourceHeight : sourceWidth;

  /// Brightness at upright (x, y), clamped to the picture.
  int at(int x, int y) {
    final int cx = x < 0 ? 0 : (x >= width ? width - 1 : x);
    final int cy = y < 0 ? 0 : (y >= height ? height - 1 : y);
    return bytes[_base + cx * _stepX + cy * _stepY];
  }

  /// Brightness at a fractional upright position, bilinear.
  double sample(double x, double y) {
    final double fx = x < 0 ? 0 : (x > width - 1 ? (width - 1).toDouble() : x);
    final double fy = y < 0 ? 0 : (y > height - 1 ? (height - 1).toDouble() : y);
    final int x0 = fx.floor();
    final int y0 = fy.floor();
    final int x1 = x0 + 1 < width ? x0 + 1 : x0;
    final int y1 = y0 + 1 < height ? y0 + 1 : y0;
    final double tx = fx - x0;
    final double ty = fy - y0;
    final double top = at(x0, y0) * (1 - tx) + at(x1, y0) * tx;
    final double bottom = at(x0, y1) * (1 - tx) + at(x1, y1) * tx;
    return top * (1 - ty) + bottom * ty;
  }

  /// Shrinks the upright picture by a whole number [factor], averaging each
  /// factor-by-factor block.
  GrayImage downscale(int factor) {
    final int f = factor < 1 ? 1 : factor;
    final int outW = width ~/ f;
    final int outH = height ~/ f;
    final Uint8List out = Uint8List(outW * outH);
    final int area = f * f;
    for (int oy = 0; oy < outH; oy++) {
      for (int ox = 0; ox < outW; ox++) {
        int sum = 0;
        final int baseIndex = _base + (ox * f) * _stepX + (oy * f) * _stepY;
        for (int dy = 0; dy < f; dy++) {
          int index = baseIndex + dy * _stepY;
          for (int dx = 0; dx < f; dx++) {
            sum += bytes[index];
            index += _stepX;
          }
        }
        out[oy * outW + ox] = sum ~/ area;
      }
    }
    return GrayImage(outW, outH, out);
  }

  /// Resamples the whole upright picture to [outWidth] by [outHeight].
  /// Used for the small picture sent to a viewer.
  GrayImage resize(int outWidth, int outHeight) {
    final Uint8List out = Uint8List(outWidth * outHeight);
    final double sx = width / outWidth;
    final double sy = height / outHeight;
    // Average a block this wide so a thin dark dot is not skipped.
    final int bx = sx.floor() < 1 ? 1 : sx.floor();
    final int by = sy.floor() < 1 ? 1 : sy.floor();
    for (int oy = 0; oy < outHeight; oy++) {
      final int y0 = (oy * sy).floor();
      for (int ox = 0; ox < outWidth; ox++) {
        final int x0 = (ox * sx).floor();
        int sum = 0;
        int count = 0;
        for (int dy = 0; dy < by; dy += by > 3 ? 2 : 1) {
          for (int dx = 0; dx < bx; dx += bx > 3 ? 2 : 1) {
            sum += at(x0 + dx, y0 + dy);
            count++;
          }
        }
        out[oy * outWidth + ox] = count == 0 ? 0 : sum ~/ count;
      }
    }
    return GrayImage(outWidth, outHeight, out);
  }
}
