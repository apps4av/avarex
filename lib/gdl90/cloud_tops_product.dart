import 'global_block_product.dart';

/// FIS-B cloud tops forecast — product 84.
/// Same RLE as turbulence; values are cloud-top height bands.
class CloudTopsProduct extends GlobalBlockProduct {
  CloudTopsProduct(
    super.time,
    super.data,
    super.coordinate,
    super.productFileId,
    super.productFileLength,
    super.apduNumber,
    super.segFlag,
  ) : super(kind: "cloudTops", label: "Cloud tops");

  // 0 = no clouds, 1..14 height bands, 15 = no data.
  static const List<int> colors = [
    0x00000000, // no clouds
    0x7FE0FFFF, // cyan → gray as tops rise
    0x7FC0EEEE,
    0x7FA0DDDD,
    0x7F80CCCC,
    0x7F60BBBB,
    0x7F40AAAA,
    0x7F209999,
    0x7F008888,
    0x7F007777,
    0x7F006666,
    0x7F005555,
    0x7F004444,
    0x7F003333,
    0x7F002222,
    0x00000000, // no data
  ];

  @override
  List<int> intensityColors() => colors;

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
  String shortName() => "Cloud tops";
}
