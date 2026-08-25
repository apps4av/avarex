import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../storage.dart';
import 'flybrief_notams.dart' show FbCountry, FlybriefNotams;
import 'terrain_download_manager.dart';

// Download and transcode terrain (elevation) tiles for a country so the terrain
// profile, elevation readout and GPWS work offline outside the US. Tiles are
// built on device from open AWS Terrain Tiles; nothing is bundled in the app.
class TerrainDownloadScreen extends StatefulWidget {
  const TerrainDownloadScreen({super.key});

  @override
  State<TerrainDownloadScreen> createState() => _TerrainDownloadScreenState();
}

class _TerrainDownloadScreenState extends State<TerrainDownloadScreen> {
  FbCountry? _country;
  TerrainDownloadManager? _manager;
  bool _busy = false;
  double _progress = 0;
  String? _message;

  @override
  void initState() {
    super.initState();
    LatLng where;
    try {
      where = LatLng(Storage().position.latitude, Storage().position.longitude);
    } catch (_) {
      where = const LatLng(50.03, 8.55);
    }
    _country = FlybriefNotams.forPoint(where.latitude, where.longitude) ??
        FlybriefNotams.byIso('DE');
  }

  String _estimate(FbCountry c) {
    final tiles = TerrainDownloadManager.tileCount(c);
    final mb = TerrainDownloadManager.estimatedBytes(c) / (1024 * 1024);
    return '$tiles tiles, ~${mb.toStringAsFixed(0)} MB download';
  }

  Future<void> _download() async {
    final c = _country;
    if (c == null) return;
    _manager = TerrainDownloadManager();
    setState(() {
      _busy = true;
      _progress = 0;
      _message = 'Starting...';
    });
    final count = await _manager!.download(c, onProgress: (p, m) {
      if (mounted) setState(() { _progress = p; _message = m; });
    });
    if (mounted) {
      setState(() {
        _busy = false;
        _message = count != null
            ? 'Installed $count terrain tiles for ${c.path} (offline).'
            : (_message ?? 'Cancelled.');
      });
    }
  }

  void _cancel() {
    _manager?.cancel();
  }

  Future<void> _remove() async {
    final c = _country;
    if (c == null) return;
    setState(() { _busy = true; _message = 'Removing...'; });
    final n = await TerrainDownloadManager.remove(c);
    if (mounted) {
      setState(() { _busy = false; _message = 'Removed $n terrain tiles for ${c.path}.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _country;
    return Scaffold(
      appBar: AppBar(title: const Text('Terrain (Elevation)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Terrain elevation for offline use',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
              'Builds elevation tiles on this device for the chosen country so '
              'the terrain profile, elevation readout and GPWS work offline '
              'outside the US. Larger countries take longer and use more space; '
              'you can cancel any time.'),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: c?.iso2,
            decoration: const InputDecoration(labelText: 'Country'),
            items: FlybriefNotams.countries
                .map((x) => DropdownMenuItem(
                    value: x.iso2, child: Text('${x.path} (${x.iso2})')))
                .toList(),
            onChanged: _busy
                ? null
                : (v) => setState(() =>
                    _country = v == null ? null : FlybriefNotams.byIso(v)),
          ),
          const SizedBox(height: 8),
          if (c != null)
            Text(_estimate(c),
                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _download,
                icon: const Icon(Icons.download),
                label: const Text('Download for Offline'),
              ),
              if (_busy)
                OutlinedButton.icon(
                  onPressed: _cancel,
                  icon: const Icon(Icons.stop),
                  label: const Text('Cancel'),
                ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _remove,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove'),
              ),
            ],
          ),
          if (_busy) Padding(
            padding: const EdgeInsets.only(top: 16),
            child: LinearProgressIndicator(value: _progress > 0 ? _progress : null),
          ),
          if (_message != null) Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_message!),
          ),
          const SizedBox(height: 24),
          const Text('Terrain © AWS Terrain Tiles / Mapzen contributors',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
              'Elevation data is compiled from open public-domain and '
              'permissively licensed sources (SRTM, and others) via AWS Terrain '
              'Tiles. It is advisory only and not certified for terrain '
              'clearance; always maintain safe altitudes.'),
        ],
      ),
    );
  }
}
