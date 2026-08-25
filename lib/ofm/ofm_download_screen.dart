import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_material_design_icons/flutter_material_design_icons.dart';
import 'package:universal_io/io.dart';

import 'ofm_constants.dart';
import 'ofm_database_helper.dart';
import 'ofm_download_manager.dart';
import 'ofm_manifest.dart';
import 'ofm_manifest_store.dart';
import 'ofm_map_layer.dart';
import 'ofm_paths.dart';
import 'ofm_publication.dart';
import 'ofm_publication_client.dart';
import 'ofm_region.dart';

class OfmDownloadScreen extends StatefulWidget {
  const OfmDownloadScreen({super.key});

  @override
  State<OfmDownloadScreen> createState() => _OfmDownloadScreenState();
}

class _OfmDownloadScreenState extends State<OfmDownloadScreen> {

  final OfmPublicationClient _client = OfmPublicationClient();
  final OfmDownloadManager _downloadManager = OfmDownloadManager();
  String _region = 'ED';
  String _cycle = OfmPublicationClient.currentAiracCycle();
  OfmPublication? _publication;
  String? _message;
  double? _progress;
  bool _busy = false;
  bool _includeMbtiles = true;
  bool _includeOfmx = true;
  bool _retinaMbtiles = false;
  final Set<String> _selectedPdfUrls = {};

  Future<void> _fetchPublication() async {
    setState(() {
      _busy = true;
      _message = 'Fetching OFM publication...';
      _progress = null;
    });
    try {
      final publication = await _client.fetch(region: _region, cycle: _cycle);
      setState(() {
        _publication = publication;
        _selectedPdfUrls.removeWhere((url) => !publication.chartPdfs.any((product) => product.url.toString() == url));
        _message = 'Found ${publication.products.length} products for $_region $_cycle.';
      });
    } catch (e) {
      setState(() {
        _message = 'Unable to fetch publication: $e';
      });
    } finally {
      setState(() {
        _busy = false;
      });
    }
  }


  Future<void> _downloadSelected() async {
    if (kIsWeb) {
      setState(() => _message = 'OFM regional downloads are available on mobile/desktop only.');
      return;
    }
    if (!_includeMbtiles && !_includeOfmx && _selectedPdfUrls.isEmpty) {
      setState(() => _message = 'Select at least one OFM product.');
      return;
    }
    if (_publication == null) await _fetchPublication();
    final pub = _publication;
    if (pub == null) return;
    setState(() { _busy = true; _progress = 0; _message = 'Installing OFM data...'; });
    try {
      OfmInstall? install;
      if (_includeMbtiles) {
        install = await _downloadManager.downloadMbtiles(
          dataDir: Storage().dataDir,
          publication: pub,
          publicationUrl: _client.publicationUri(region: _region, cycle: _cycle),
          onProgress: (value) { if (mounted) setState(() => _progress = value * (_includeOfmx ? 0.45 : 1)); },
          selectedProduct: _retinaMbtiles ? pub.retinaMbtiles : pub.normalMbtiles,
        );
      }
      if (_includeOfmx) {
        final (ofmxInstall, result) = await _downloadManager.downloadOfmx(
          dataDir: Storage().dataDir,
          publication: pub,
          publicationUrl: _client.publicationUri(region: _region, cycle: _cycle),
          onProgress: (value) { if (mounted) setState(() => _progress = (_includeMbtiles ? 0.45 : 0) + value * (_includeMbtiles ? 0.55 : 1)); },
        );
        await OfmDatabaseHelper.db.importResult(dataDir: Storage().dataDir, result: result, region: pub.region, cycle: pub.cycle);
        install = OfmInstall(
          region: ofmxInstall.region,
          cycle: ofmxInstall.cycle,
          installedAt: ofmxInstall.installedAt,
          publicationUrl: ofmxInstall.publicationUrl,
          mbtilesPath: install?.mbtilesPath,
          ofmxPath: ofmxInstall.ofmxPath,
        );
      }
      if (install != null) {
        await _writeManifest(install);
        await OfmDatabaseHelper.db.recordInstall(
          dataDir: Storage().dataDir,
          install: install,
          effective: pub.nearCycles.isNotEmpty ? pub.nearCycles.first.startValidity?.toIso8601String() : null,
          expiration: pub.nearCycles.isNotEmpty ? pub.nearCycles.first.endValidity?.toIso8601String() : null,
          ofmxUrl: pub.ofmx?.url.toString(),
          mbtilesUrl: pub.preferredMbtiles?.url.toString(),
        );
        OfmMapLayer.notifyChanged();
      }
      final publicationCode = OfmRegions.publicationCode(pub.region);
      for (final product in pub.chartPdfs) {
        if (!_selectedPdfUrls.contains(product.url.toString())) continue;
        final chart = await _downloadManager.downloadPdf(
          dataDir: Storage().dataDir,
          region: pub.region,
          publicationCode: publicationCode,
          cycle: pub.cycle,
          product: product,
          onProgress: (value) { if (mounted) setState(() => _progress = value); },
        );
        await OfmManifestStore(Storage().dataDir).mergeProduct(chart);
      }
      setState(() => _message = 'Installed selected ${pub.region} ${pub.cycle} OFM products.');
    } catch (e) {
      setState(() => _message = 'Unable to install OFM data: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSelectedRegion() async {
    setState(() { _busy = true; _message = 'Removing OFM region...'; });
    try {
      final paths = OfmPaths(Storage().dataDir);
      final manifestFile = File(paths.manifestPath);
      var manifest = OfmManifest.empty();
      if (await manifestFile.exists()) manifest = OfmManifest.fromJsonString(await manifestFile.readAsString());
      final removing = manifest.installs.where((item) => item.region == _region && item.cycle == _cycle).toList();
      for (final item in removing) {
        for (final filePath in [item.mbtilesPath, item.ofmxPath]) {
          if (filePath != null && await File(filePath).exists()) await File(filePath).delete();
        }
      }
      final productRemoving = manifest.products.where((item) => item.region == _region && item.cycle == _cycle).toList();
      for (final item in productRemoving) {
        if (await File(item.localPath).exists()) await File(item.localPath).delete();
      }
      await OfmDatabaseHelper.db.deleteRegion(dataDir: Storage().dataDir, region: _region, cycle: _cycle);
      await OfmManifestStore(Storage().dataDir).save(OfmManifest(
        installs: manifest.installs.where((item) => !(item.region == _region && item.cycle == _cycle)).toList(),
        products: manifest.products.where((item) => !(item.region == _region && item.cycle == _cycle)).toList(),
      ));
      OfmMapLayer.notifyChanged();
      setState(() => _message = 'Removed $_region $_cycle OFM data.');
    } catch (e) {
      setState(() => _message = 'Unable to remove OFM data: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _writeManifest(OfmInstall install) async {
    final store = OfmManifestStore(Storage().dataDir);
    final manifest = await store.load();
    final installs = manifest.installs
        .where((i) => !(i.region == install.region && i.cycle == install.cycle))
        .toList();
    installs.add(install);
    await store.save(OfmManifest(installs: installs, products: manifest.products));
  }

  @override
  Widget build(BuildContext context) {
    final publication = _publication;
    return Scaffold(
      appBar: AppBar(
        title: const Text('OpenFlightMaps'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(MdiIcons.mapOutline),
                      SizedBox(width: 8),
                      Text(OfmConstants.sourceName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(OfmConstants.disclaimer),
                  const SizedBox(height: 8),
                  const Text(OfmConstants.attribution),
                  const SizedBox(height: 8),
                  const Text(OfmConstants.corrections),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _region,
            decoration: const InputDecoration(labelText: 'OFM Region'),
            items: [
              for (final region in OfmRegions.all.where((region) => region.enabled))
                DropdownMenuItem(value: region.code, child: Text('${region.code} - ${region.name}')),
            ],
            onChanged: _busy
                ? null
                : (value) {
                    if (value != null) {
                      setState(() {
                        _region = value;
                        _publication = null;
                      });
                    }
                  },
          ),
          const SizedBox(height: 12),
          if (publication != null && publication.nearCycles.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: publication.nearCycles.any((item) => item.id == _cycle) ? _cycle : publication.nearCycles.first.id,
              decoration: const InputDecoration(labelText: 'AIRAC Cycle'),
              items: [for (final cycle in publication.nearCycles) DropdownMenuItem(value: cycle.id, child: Text('${cycle.id} — ${cycle.label}'))],
              onChanged: _busy ? null : (value) {
                if (value != null && value != _cycle) {
                  setState(() { _cycle = value; _publication = null; });
                  _fetchPublication();
                }
              },
            )
          else
            TextFormField(
              initialValue: _cycle,
              decoration: const InputDecoration(labelText: 'AIRAC Cycle'),
              enabled: !_busy,
              onChanged: (value) => setState(() { _cycle = value.trim(); _publication = null; }),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _fetchPublication,
            icon: const Icon(Icons.search),
            label: const Text('Fetch OFM Products'),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _includeMbtiles,
            onChanged: _busy ? null : (value) => setState(() => _includeMbtiles = value ?? false),
            title: const Text('VFR map layer (MBTiles)'),
            contentPadding: EdgeInsets.zero,
          ),
          if (publication?.retinaMbtiles != null)
            SwitchListTile(
              value: _retinaMbtiles,
              onChanged: _busy ? null : (value) => setState(() => _retinaMbtiles = value),
              title: const Text('High-resolution VFR map'),
              subtitle: const Text('Uses the larger @2x MBTiles download'),
              contentPadding: EdgeInsets.zero,
            ),
          CheckboxListTile(
            value: _includeOfmx,
            onChanged: _busy ? null : (value) => setState(() => _includeOfmx = value ?? false),
            title: const Text('Search/details data (OFMX)'),
            contentPadding: EdgeInsets.zero,
          ),
          if (publication != null && publication.chartPdfs.isNotEmpty) ...[
            Row(children: [
              Expanded(child: Text('Published VFR chart sheets', style: Theme.of(context).textTheme.titleMedium)),
              TextButton(
                onPressed: _busy ? null : () => setState(() => _selectedPdfUrls
                  ..clear()
                  ..addAll(publication.chartPdfs.map((product) => product.url.toString()))),
                child: const Text('Select all'),
              ),
              TextButton(onPressed: _busy ? null : () => setState(_selectedPdfUrls.clear), child: const Text('Clear')),
            ]),
            for (final product in publication.chartPdfs)
              CheckboxListTile(
                value: _selectedPdfUrls.contains(product.url.toString()),
                onChanged: _busy ? null : (selected) => setState(() {
                  selected == true ? _selectedPdfUrls.add(product.url.toString()) : _selectedPdfUrls.remove(product.url.toString());
                }),
                title: Text(product.name),
                subtitle: Text(product.details),
                contentPadding: EdgeInsets.zero,
              ),
          ],
          FilledButton.icon(
            onPressed: _busy ? null : _downloadSelected,
            icon: const Icon(Icons.download),
            label: const Text('Install Selected OFM Data'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy || kIsWeb ? null : _deleteSelectedRegion,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove Selected Region/Cycle'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/ofm_charts'),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Open Installed VFR Chart Sheets'),
          ),
          if (_busy)
            TextButton.icon(
              onPressed: _downloadManager.cancel,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel Download'),
            ),
          if (_progress != null) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
          ],
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(_message!),
          ],
          if (publication != null) ...[
            const SizedBox(height: 16),
            Text('Products', style: Theme.of(context).textTheme.titleMedium),
            for (final product in publication.products)
              ListTile(
                dense: true,
                title: Text(product.name.isEmpty ? product.rawType : product.name),
                subtitle: Text(product.url.toString()),
                trailing: Text(product.type.name),
              ),
          ],
        ],
      ),
    );
  }
}
