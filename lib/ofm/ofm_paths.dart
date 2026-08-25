import 'package:path/path.dart' as path;

class OfmPaths {
  final String dataDir;

  const OfmPaths(this.dataDir);

  String get root => path.join(dataDir, 'ofm');
  String get manifestPath => path.join(root, 'manifest.json');
  String get ofmDatabasePath => path.join(root, 'ofm.db');
  String get rawRoot => path.join(root, 'raw');
  String get mapsRoot => path.join(root, 'maps');
  String get chartsRoot => path.join(root, 'charts');

  String mbtilesPath({required String region, required String cycle}) {
    final safeRegion = _safeCode(region, 'region').toLowerCase();
    final safeCycle = _safeCode(cycle, 'cycle');
    return path.join(mapsRoot, safeCycle, '$safeRegion.mbtiles');
  }

  String rawRegionDir({required String region, required String cycle}) {
    final safeRegion = _safeCode(region, 'region').toLowerCase();
    final safeCycle = _safeCode(cycle, 'cycle');
    return path.join(rawRoot, safeCycle, safeRegion);
  }

  String pdfRegionDir({required String region, required String cycle}) {
    return path.join(chartsRoot, _safeCode(cycle, 'cycle'), _safeCode(region, 'region').toLowerCase());
  }

  String pdfPath({required String region, required String cycle, required String filename}) {
    final safeFilename = filename.trim();
    if (safeFilename.isEmpty || path.basename(safeFilename) != safeFilename || !safeFilename.toLowerCase().endsWith('.pdf')) {
      throw ArgumentError.value(filename, 'filename', 'must be a simple PDF filename');
    }
    return path.join(pdfRegionDir(region: region, cycle: cycle), safeFilename);
  }

  static String _safeCode(String value, String fieldName) {
    final normalized = value.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(normalized)) {
      throw ArgumentError.value(value, fieldName, 'must contain only letters, numbers, underscore, or dash');
    }
    return normalized;
  }
}
