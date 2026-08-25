import 'package:universal_io/io.dart';

import 'ofm_manifest.dart';
import 'ofm_paths.dart';

class OfmManifestStore {
  final OfmPaths paths;

  OfmManifestStore(String dataDir) : paths = OfmPaths(dataDir);

  Future<OfmManifest> load() async {
    final file = File(paths.manifestPath);
    if (!await file.exists()) return OfmManifest.empty();
    try {
      final manifest = OfmManifest.fromJsonString(await file.readAsString());
      return OfmManifest(
        installs: manifest.installs.where((item) => _safeNullable(item.mbtilesPath) && _safeNullable(item.ofmxPath)).toList(),
        products: manifest.products.where((item) => _isInsideRoot(item.localPath)).toList(),
      );
    } catch (_) {
      return OfmManifest.empty();
    }
  }

  Future<void> save(OfmManifest manifest) async {
    final file = File(paths.manifestPath);
    final temporary = File('${paths.manifestPath}.part');
    await file.parent.create(recursive: true);
    await temporary.writeAsString(manifest.toJsonString(), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<OfmManifest> mergeProduct(OfmInstalledProduct product) async {
    if (!_isInsideRoot(product.localPath)) throw ArgumentError.value(product.localPath, 'localPath');
    final current = await load();
    final products = current.products.where((item) => !(item.region == product.region && item.cycle == product.cycle && item.type == product.type && item.name == product.name)).toList()..add(product);
    final next = OfmManifest(installs: current.installs, products: products);
    await save(next);
    return next;
  }

  Future<OfmManifest> removeProduct(OfmInstalledProduct product) async {
    final current = await load();
    if (_isInsideRoot(product.localPath)) {
      final file = File(product.localPath);
      if (await file.exists()) await file.delete();
    }
    final next = OfmManifest(
      installs: current.installs,
      products: current.products.where((item) => !(item.region == product.region && item.cycle == product.cycle && item.type == product.type && item.name == product.name)).toList(),
    );
    await save(next);
    return next;
  }

  bool _safeNullable(String? value) => value == null || _isInsideRoot(value);

  bool _isInsideRoot(String candidate) {
    final root = Directory(paths.root).absolute.path;
    final resolved = File(candidate).absolute.path;
    return resolved == root || resolved.startsWith('$root${Platform.pathSeparator}');
  }
}
