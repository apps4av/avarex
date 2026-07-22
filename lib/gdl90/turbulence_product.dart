import 'global_block_product.dart';

/// FIS-B turbulence forecast — product 90 (low) / 91 (high).
/// Same 1/2-byte RLE as cloud tops (4-bit length-1, 4-bit EDR value).
class TurbulenceProduct extends GlobalBlockProduct {
  TurbulenceProduct(
    super.time,
    super.data,
    super.coordinate,
    super.productFileId,
    super.productFileLength,
    super.apduNumber,
    super.segFlag, {
    required bool high,
  }) : super(
          kind: "turbulence",
          label: high ? "Turbulence (high)" : "Turbulence (low)",
          highAltitude: high,
        );

  // EDR encodings 0..14 plus 15 = no data. Warm colors for stronger turb.
  static const List<int> _colors = [
    0x00000000, // <7 — empty / no turb shown
    0x7FFFFF99, // light yellow
    0x7FFFFF66,
    0x7FFFFF00,
    0x7FFFFF00,
    0x7FFFFC00,
    0x7FFFF800,
    0x7FFFF400,
    0x7FFFF000,
    0x7FFFC000,
    0x7FFF8000,
    0x7FFF4000,
    0x7FFF0000,
    0x7FCC0000,
    0x7F990000,
    0x00000000, // no data
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
      final int lengthMinus1 = (b0 >> 4) & 0x0F;
      final int value = b0 & 0x0F;
      int numberOfBins;
      if (lengthMinus1 == 14) {
        // Two-byte run: next byte is length-1 (15..127).
        if (i + 1 >= bytes.length) {
          return [];
        }
        numberOfBins = (bytes[i + 1] & 0xFF) + 1;
        i += 2;
      } else {
        numberOfBins = lengthMinus1 + 1;
        i += 1;
      }
      for (int n = 0; n < numberOfBins; n++) {
        if (j >= bins.length) {
          return [];
        }
        bins[j++] = value;
      }
    }
    return j == bins.length ? bins : [];
  }

  @override
  String shortName() => "Turbulence";
}
