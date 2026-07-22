import 'global_block_product.dart';

/// FIS-B lightning — product 103.
/// Single-byte RLE: length-1 (4), polarity (1), strike count (3).
class LightningProduct extends GlobalBlockProduct {
  LightningProduct(
    super.time,
    super.data,
    super.coordinate,
    super.productFileId,
    super.productFileLength,
    super.apduNumber,
    super.segFlag,
  ) : super(kind: "lightning", label: "Lightning");

  // Index 0..7 by strike count; polarity ignored for color (yellow flashes).
  static const List<int> _colors = [
    0x00000000, // 0 strikes
    0x7FFFFF00, // yellow
    0x7FFFFF66,
    0x7FFFFFF0,
    0x7FFFFFFF,
    0x7FFFFFCC,
    0x7FFFFF99,
    0x7FFFFF33,
  ];

  @override
  List<int> intensityColors() => _colors;

  @override
  List<int> decodeRuns(List<int> bytes) {
    final List<int> bins = List<int>.filled(GlobalBlockProduct.binsPerBlock, 0);
    int j = 0;
    int i = 0;
    while (i < bytes.length && j < bins.length) {
      final int b0 = bytes[i] & 0xFF;
      final int numberOfBins = ((b0 >> 4) & 0x0F) + 1;
      final int strikes = b0 & 0x07;
      for (int n = 0; n < numberOfBins; n++) {
        if (j >= bins.length) {
          return [];
        }
        bins[j++] = strikes;
      }
      i += 1;
    }
    return j == bins.length ? bins : [];
  }

  @override
  String shortName() => "Lightning";
}
