import 'global_block_product.dart';

/// FIS-B icing forecast — product 70 (low) / 71 (high).
/// Two-byte RLE: length-1, then SLD(2) + severity(3) + probability(3).
class IcingProduct extends GlobalBlockProduct {
  IcingProduct(
    super.time,
    super.data,
    super.coordinate,
    super.productFileId,
    super.productFileLength,
    super.apduNumber,
    super.segFlag, {
    required bool high,
  }) : super(
          kind: "icing",
          label: high ? "Icing (high)" : "Icing (low)",
          highAltitude: high,
        );

  // Index by icing severity 0..7 (None..No Data). Probability drives runs;
  // we color by severity for map readability.
  static const List<int> _colors = [
    0x00000000, // none
    0x7FADD8E6, // trace — light blue
    0x7F87CEEB, // light
    0x7F1E90FF, // moderate
    0x7F0000CD, // severe
    0x7F4B0082, // heavy
    0x00000000, // reserved
    0x00000000, // no data
  ];

  @override
  List<int> intensityColors() => _colors;

  @override
  List<int> decodeRuns(List<int> bytes) {
    final List<int> bins = List<int>.filled(GlobalBlockProduct.binsPerBlock, 0);
    int j = 0;
    int i = 0;
    while (i + 1 < bytes.length && j < bins.length) {
      final int numberOfBins = (bytes[i] & 0xFF) + 1;
      final int b2 = bytes[i + 1] & 0xFF;
      final int severity = (b2 >> 3) & 0x07;
      final int probability = b2 & 0x07;
      // No-data probability → clear; else use severity (0 = none / empty-looking).
      final int intensity = (probability == 7) ? 7 : severity;
      for (int n = 0; n < numberOfBins; n++) {
        if (j >= bins.length) {
          return [];
        }
        bins[j++] = intensity;
      }
      i += 2;
    }
    return j == bins.length ? bins : [];
  }

  @override
  String shortName() => "Icing";
}
