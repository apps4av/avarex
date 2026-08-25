import 'package:xml/xml.dart';

enum OfmProductType {
  ofmx,
  mbtiles,
  openair,
  cup,
  arinc424,
  chartPdf,
  slippyTiles,
  other,
}

class OfmCycle {
  final String id;
  final String label;
  final DateTime? startValidity;
  final DateTime? endValidity;

  const OfmCycle({
    required this.id,
    required this.label,
    this.startValidity,
    this.endValidity,
  });
}

class OfmPublicationProduct {
  final OfmProductType type;
  final String rawType;
  final String name;
  final String details;
  final Uri url;
  final DateTime? timestamp;
  final Map<String, String> variant;
  final String productTitle;

  const OfmPublicationProduct({
    required this.type,
    required this.rawType,
    required this.name,
    required this.details,
    required this.url,
    this.timestamp,
    this.variant = const {},
    this.productTitle = '',
  });

  bool get isDoubleResolution =>
      variant.values.any((v) => v.toLowerCase().contains('@2x') || v.toLowerCase().contains('double')) ||
      url.path.toLowerCase().contains('@2x');
}

class OfmPublication {
  final String region;
  final String cycle;
  final List<OfmCycle> nearCycles;
  final List<OfmPublicationProduct> products;

  const OfmPublication({
    required this.region,
    required this.cycle,
    required this.nearCycles,
    required this.products,
  });

  OfmPublicationProduct? get ofmx => _firstOfType(OfmProductType.ofmx);

  List<OfmPublicationProduct> get chartPdfs => products.where((p) => p.type == OfmProductType.chartPdf).toList(growable: false);
  List<OfmPublicationProduct> get slippyTileArchives => products.where((p) => p.type == OfmProductType.slippyTiles).toList(growable: false);

  OfmPublicationProduct? get normalMbtiles {
    final matches = products.where((p) => p.type == OfmProductType.mbtiles && !p.isDoubleResolution);
    return matches.isEmpty ? null : matches.first;
  }

  OfmPublicationProduct? get retinaMbtiles {
    final matches = products.where((p) => p.type == OfmProductType.mbtiles && p.isDoubleResolution);
    return matches.isEmpty ? null : matches.first;
  }

  OfmPublicationProduct? get preferredMbtiles {
    final mbtiles = products.where((p) => p.type == OfmProductType.mbtiles).toList();
    if (mbtiles.isEmpty) {
      return null;
    }
    return mbtiles.firstWhere(
      (p) => !p.isDoubleResolution,
      orElse: () => mbtiles.first,
    );
  }

  OfmPublicationProduct? _firstOfType(OfmProductType type) {
    for (final product in products) {
      if (product.type == type) {
        return product;
      }
    }
    return null;
  }

  static OfmPublication parse({
    required String region,
    required String cycle,
    required String xml,
  }) {
    final document = XmlDocument.parse(xml);
    final cycles = document.findAllElements('cycle').map((element) {
      return OfmCycle(
        id: element.getAttribute('id') ?? '',
        label: element.getAttribute('string') ?? '',
        startValidity: DateTime.tryParse(element.getAttribute('startValidity') ?? ''),
        endValidity: DateTime.tryParse(element.getAttribute('endValidity') ?? ''),
      );
    }).where((c) => c.id.isNotEmpty).toList(growable: false);

    final products = <OfmPublicationProduct>[];
    for (final productElement in document.findAllElements('product')) {
      final rawType = productElement.getAttribute('type') ?? '';
      final type = _productType(rawType);
      for (final download in productElement.findElements('download')) {
        final directUrl = download.getAttribute('URL');
        if (directUrl != null && directUrl.isNotEmpty) {
          products.add(_productFromElement(
            rawType: rawType,
            type: type,
            download: download,
            productTitle: productElement.getAttribute('title_english') ?? productElement.getAttribute('title_local') ?? '',
            variant: const {},
            url: directUrl,
          ));
        }
        for (final variantElement in download.findElements('variant')) {
          final variantUrl = variantElement.getAttribute('URL');
          if (variantUrl == null || variantUrl.isEmpty) {
            continue;
          }
          products.add(_productFromElement(
            rawType: rawType,
            type: type,
            download: download,
            productTitle: productElement.getAttribute('title_english') ?? productElement.getAttribute('title_local') ?? '',
            variant: Map<String, String>.fromEntries(
              variantElement.attributes.map((a) => MapEntry(a.name.local, a.value)),
            ),
            url: variantUrl,
          ));
        }
      }
    }

    return OfmPublication(
      region: region.toUpperCase(),
      cycle: cycle,
      nearCycles: cycles,
      products: products,
    );
  }

  static OfmPublicationProduct _productFromElement({
    required String rawType,
    required OfmProductType type,
    required XmlElement download,
    required String productTitle,
    required Map<String, String> variant,
    required String url,
  }) {
    return OfmPublicationProduct(
      type: type,
      rawType: rawType,
      name: download.getAttribute('name') ?? '',
      details: download.getAttribute('details_english') ?? download.getAttribute('details_local') ?? '',
      url: Uri.parse(url.replaceFirst('http://', 'https://')),
      timestamp: DateTime.tryParse(download.getAttribute('timestamp') ?? ''),
      variant: variant,
      productTitle: productTitle,
    );
  }

  static OfmProductType _productType(String rawType) {
    final normalized = rawType.toUpperCase();
    if (normalized == 'OFMX') {
      return OfmProductType.ofmx;
    }
    if (normalized.contains('MBTILES')) {
      return OfmProductType.mbtiles;
    }
    if (normalized.contains('SLIPPYTILES')) {
      return OfmProductType.slippyTiles;
    }
    if (normalized == 'OPENAIR') {
      return OfmProductType.openair;
    }
    if (normalized == 'CUP') {
      return OfmProductType.cup;
    }
    if (normalized == 'ARINC424') {
      return OfmProductType.arinc424;
    }
    if (normalized.contains('PDF')) {
      return OfmProductType.chartPdf;
    }
    return OfmProductType.other;
  }
}
