import 'dart:convert';

class OfmManifest {
  final List<OfmInstall> installs;
  final List<OfmInstalledProduct> products;

  const OfmManifest({this.installs = const [], this.products = const []});

  factory OfmManifest.empty() => const OfmManifest();

  factory OfmManifest.fromJson(Map<String, dynamic> json) {
    final rawInstalls = json['installs'];
    final rawProducts = json['products'];
    return OfmManifest(
      installs: rawInstalls is List
          ? rawInstalls.whereType<Map>().map((m) => OfmInstall.fromJson(Map<String, dynamic>.from(m))).toList(growable: false)
          : const [],
      products: rawProducts is List
          ? rawProducts.whereType<Map>().map((m) => OfmInstalledProduct.fromJson(Map<String, dynamic>.from(m))).toList(growable: false)
          : const [],
    );
  }

  factory OfmManifest.fromJsonString(String jsonString) {
    return OfmManifest.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  Map<String, dynamic> toJson() => {
        'installs': installs.map((i) => i.toJson()).toList(growable: false),
        'products': products.map((i) => i.toJson()).toList(growable: false),
      };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}

class OfmInstalledProduct {
  final String region;
  final String publicationCode;
  final String cycle;
  final String type;
  final String name;
  final String details;
  final Uri sourceUrl;
  final String localPath;
  final DateTime? timestamp;
  final int? byteSize;
  final String? resolution;

  const OfmInstalledProduct({
    required this.region,
    required this.publicationCode,
    required this.cycle,
    required this.type,
    required this.name,
    required this.details,
    required this.sourceUrl,
    required this.localPath,
    this.timestamp,
    this.byteSize,
    this.resolution,
  });

  factory OfmInstalledProduct.fromJson(Map<String, dynamic> json) => OfmInstalledProduct(
        region: json['region'] as String,
        publicationCode: json['publicationCode'] as String,
        cycle: json['cycle'] as String,
        type: json['type'] as String,
        name: json['name'] as String,
        details: (json['details'] ?? '').toString(),
        sourceUrl: Uri.parse(json['sourceUrl'] as String),
        localPath: json['localPath'] as String,
        timestamp: DateTime.tryParse((json['timestamp'] ?? '').toString()),
        byteSize: json['byteSize'] as int?,
        resolution: json['resolution'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'region': region,
        'publicationCode': publicationCode,
        'cycle': cycle,
        'type': type,
        'name': name,
        'details': details,
        'sourceUrl': sourceUrl.toString(),
        'localPath': localPath,
        if (timestamp != null) 'timestamp': timestamp!.toUtc().toIso8601String(),
        if (byteSize != null) 'byteSize': byteSize,
        if (resolution != null) 'resolution': resolution,
      };
}

class OfmInstall {
  final String region;
  final String cycle;
  final DateTime installedAt;
  final Uri publicationUrl;
  final String? mbtilesPath;
  final String? ofmxPath;

  const OfmInstall({
    required this.region,
    required this.cycle,
    required this.installedAt,
    required this.publicationUrl,
    this.mbtilesPath,
    this.ofmxPath,
  });

  factory OfmInstall.fromJson(Map<String, dynamic> json) {
    return OfmInstall(
      region: json['region'] as String,
      cycle: json['cycle'] as String,
      installedAt: DateTime.parse(json['installedAt'] as String),
      publicationUrl: Uri.parse(json['publicationUrl'] as String),
      mbtilesPath: json['mbtilesPath'] as String?,
      ofmxPath: json['ofmxPath'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'region': region,
        'cycle': cycle,
        'installedAt': installedAt.toUtc().toIso8601String(),
        'publicationUrl': publicationUrl.toString(),
        if (mbtilesPath != null) 'mbtilesPath': mbtilesPath,
        if (ofmxPath != null) 'ofmxPath': ofmxPath,
      };
}
