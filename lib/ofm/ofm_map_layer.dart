import 'package:universal_io/io.dart';

import 'package:flutter/widgets.dart';

import '../utils/mbtiles_layer.dart';
import 'ofm_manifest.dart';
import 'ofm_paths.dart';

class OfmMapLayer {
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);
  final List<MBTilesLayerManager> _managers = [];
  String? _loadedDataDir;

  bool get isLoaded => _managers.any((manager) => manager.isLoaded);

  static void notifyChanged() => changes.value++;

  Future<bool> loadInstalled(String dataDir, {bool force = false}) async {
    if (!force && _loadedDataDir == dataDir && isLoaded) {
      return true;
    }
    close();
    _loadedDataDir = dataDir;

    final manifestFile = File(OfmPaths(dataDir).manifestPath);
    if (!await manifestFile.exists()) {
      return false;
    }

    final OfmManifest manifest;
    try {
      manifest = OfmManifest.fromJsonString(await manifestFile.readAsString());
    } catch (_) {
      return false;
    }

    for (final install in manifest.installs) {
      final mbtilesPath = install.mbtilesPath;
      if (mbtilesPath == null || mbtilesPath.isEmpty) {
        continue;
      }
      final manager = MBTilesLayerManager();
      if (await manager.loadMBTiles(mbtilesPath)) {
        _managers.add(manager);
      }
    }

    return isLoaded;
  }

  List<Widget> buildLayers({required double opacity}) {
    final widgets = <Widget>[];
    for (final manager in _managers) {
      final widget = manager.isVector
          ? manager.buildVectorTileLayer(opacity: opacity)
          : manager.buildRasterTileLayer(opacity: opacity);
      if (widget != null) {
        widgets.add(widget);
      }
    }
    return widgets;
  }

  void close() {
    for (final manager in _managers) {
      manager.close();
    }
    _managers.clear();
  }
}
