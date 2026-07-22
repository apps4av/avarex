import 'package:avaremp/gdl90/nexrad_product.dart';
import 'package:avaremp/gdl90/product.dart';
import 'package:avaremp/storage.dart';

/// Shared FIS-B Global Block Representation parser (SBS Description Doc App. G).
///
/// Used by icing, turbulence, cloud tops, and lightning. Same 4×32 bin block
/// geometry as NEXRAD; RLE schemes differ per product.
class GlobalBlockProduct extends Product {
  GlobalBlockProduct(
    super.time,
    super.data,
    super.coordinate,
    super.productFileId,
    super.productFileLength,
    super.apduNumber,
    super.segFlag, {
    required this.kind,
    required this.label,
    this.highAltitude = false,
  });

  /// Cache / map key: icing, turbulence, cloudTops, lightning.
  final String kind;
  final String label;
  /// For icing/turbulence: product ID high band (18000–24000 ft).
  final bool highAltitude;

  static const int numRows = NexradProduct.numRows;
  static const int numCols = NexradProduct.numCols;
  static const int binsPerBlock = numRows * numCols; // 128

  static const List<int> _lowAltsFt = [
    2000, 4000, 6000, 8000, 10000, 12000, 14000, 16000,
  ];
  static const List<int> _highAltsFt = [
    18000, 20000, 22000, 24000,
  ];

  int block = -1;
  int productSpecific = 0;
  int altitudeFt = 0;
  /// 0 = high (regional), 1 = medium (CONUS), 2 = low.
  int scale = 1;
  bool southernHemisphere = false;
  List<int> full = [];
  List<int> empty = [];
  /// Raw intensity indices (0..n) before ARGB mapping. Used by cloud tops so
  /// the altitude slider can filter bins by top height.
  List<int> intensities = [];

  /// RGBA colors for intensity index 0..n (product-specific).
  List<int> intensityColors() => const [0x00000000];

  /// Decode one RLE stream into [binsPerBlock] intensity indices.
  /// Returns empty list on failure.
  List<int> decodeRuns(List<int> bytes) => [];

  /// True when [full] holds intensity indices (not ARGB) for altitude filtering.
  bool get keepsIntensities => kind == "cloudTops";

  @override
  void parse() {
    if (data.length < 3) {
      return;
    }

    final bool elementIdentifier = (data[0].toInt() & 0x80) != 0;
    productSpecific = (data[0].toInt() >> 4) & 0x07;
    block = (data[0].toInt() & 0x0F) << 16;
    block += (data[1].toInt() & 0xFF) << 8;
    block += data[2].toInt() & 0xFF;

    _applyProductSpecificBits();

    final int index = 3;
    final int len = data.lengthInBytes;

    if (elementIdentifier) {
      intensities = decodeRuns(data.sublist(index).map((e) => e.toInt() & 0xFF).toList());
      empty = [];
      if (intensities.length != binsPerBlock) {
        intensities = [];
        full = [];
        return;
      }
      if (keepsIntensities) {
        // Cache stores indices; FisBlockCache colors per altitude slider.
        full = List<int>.from(intensities);
      } else {
        final List<int> colors = intensityColors();
        full = List<int>.generate(intensities.length, (i) {
          final int idx = intensities[i];
          return (idx >= 0 && idx < colors.length) ? colors[idx] : 0;
        });
      }
    } else {
      // Empty Element bitmap — same layout as NEXRAD (App. G.1.1.2.3).
      full = [];
      empty = [];
      empty.add(block);

      if (index >= len) {
        Storage().fisBlockCache.putImg(this);
        return;
      }

      final int incr = _blockIncrement();
      final int header = data[index].toInt();
      final int bitmapLen = header & 0x0F;

      if ((header & 0x10) != 0) empty.add(block + 1 * incr);
      if ((header & 0x20) != 0) empty.add(block + 2 * incr);
      if ((header & 0x40) != 0) empty.add(block + 3 * incr);
      if ((header & 0x80) != 0) empty.add(block + 4 * incr);

      for (int i = 1; i <= bitmapLen; i++) {
        if (index + i >= len) {
          break;
        }
        final int b = data[index + i].toInt();
        if ((b & 0x01) != 0) empty.add(block + (i * 8 - 3) * incr);
        if ((b & 0x02) != 0) empty.add(block + (i * 8 - 2) * incr);
        if ((b & 0x04) != 0) empty.add(block + (i * 8 - 1) * incr);
        if ((b & 0x08) != 0) empty.add(block + (i * 8) * incr);
        if ((b & 0x10) != 0) empty.add(block + (i * 8 + 1) * incr);
        if ((b & 0x20) != 0) empty.add(block + (i * 8 + 2) * incr);
        if ((b & 0x40) != 0) empty.add(block + (i * 8 + 3) * incr);
        if ((b & 0x80) != 0) empty.add(block + (i * 8 + 4) * incr);
      }
    }

    Storage().fisBlockCache.putImg(this);
  }

  void _applyProductSpecificBits() {
    if (kind == "icing" || kind == "turbulence") {
      // Type 2: three bits = altitude level. Always northern, medium scale.
      scale = 1;
      southernHemisphere = false;
      final List<int> alts = highAltitude ? _highAltsFt : _lowAltsFt;
      altitudeFt = (productSpecific < alts.length) ? alts[productSpecific] : 0;
    } else {
      // Type 1: N/S + scale (lightning, cloud tops).
      southernHemisphere = (productSpecific & 0x04) != 0;
      scale = productSpecific & 0x03;
      altitudeFt = 0;
    }
  }

  int _blockIncrement() {
    if (scale == 1) return 5;
    if (scale == 2) return 9;
    // High resolution: 1 below 60°, 2 above (block numbering).
    return block >= 405000 ? 2 : 1;
  }

  /// Medium / CONUS-sized blocks use the same geometry as CONUS NEXRAD.
  bool get isConusScale => scale == 1;

  @override
  String decode() {
    final String kindLabel = full.isNotEmpty
        ? "data (${full.length} bins)"
        : "empty (${empty.length} block(s))";
    final String alt = altitudeFt > 0 ? "Altitude: $altitudeFt ft\n" : "";
    return "$label\n"
        "Block: $block\n"
        "$alt"
        "Scale: $scale\n"
        "Data: $kindLabel";
  }

  @override
  String shortName() => label;
}
