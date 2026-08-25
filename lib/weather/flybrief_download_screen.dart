import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../storage.dart';
import 'flybrief_notams.dart';
import 'flybrief_store.dart';

// Download and store per-country NOTAMs (and obstacles) from FlyBrief for
// offline use. Fills the European NOTAM gap where the built-in FAA source is
// empty. Defaults to the country under the current GPS position.
class FlybriefDownloadScreen extends StatefulWidget {
  const FlybriefDownloadScreen({super.key});

  @override
  State<FlybriefDownloadScreen> createState() => _FlybriefDownloadScreenState();
}

class _FlybriefDownloadScreenState extends State<FlybriefDownloadScreen> {
  FbCountry? _country;
  bool _busy = false;
  double _progress = 0;
  String? _message;

  @override
  void initState() {
    super.initState();
    // Default to the country under the current position, else Germany.
    LatLng where;
    try {
      where = LatLng(Storage().position.latitude, Storage().position.longitude);
    } catch (_) {
      where = const LatLng(50.03, 8.55);
    }
    _country = FlybriefNotams.forPoint(where.latitude, where.longitude) ??
        FlybriefNotams.byIso('DE');
  }

  Future<void> _download() async {
    final c = _country;
    if (c == null) return;
    setState(() {
      _busy = true;
      _progress = 0;
      _message = 'Starting...';
    });
    final count = await FlybriefStore.downloadCountry(c,
        onProgress: (p, m) {
      if (mounted) setState(() { _progress = p; _message = m; });
    });
    if (mounted) {
      setState(() {
        _busy = false;
        _message = count != null
            ? 'Stored $count NOTAMs for ${c.path} (offline).'
            : 'Download failed. Check your connection and try again.';
      });
    }
  }

  Future<void> _remove() async {
    final c = _country;
    if (c == null) return;
    await FlybriefStore.removeCountry(c);
    if (mounted) setState(() => _message = 'Removed offline data for ${c.path}.');
  }

  @override
  Widget build(BuildContext context) {
    final c = _country;
    final bool offline = c != null && FlybriefStore.hasOffline(c);
    return Scaffold(
      appBar: AppBar(title: const Text('NOTAMs (FlyBrief)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('European NOTAMs for offline use',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
              'Downloads per-country, georeferenced NOTAMs so they are available '
              'offline on the airport NOTAM tab. Used automatically where the '
              'built-in (US) NOTAM source has no coverage.'),
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
          if (offline)
            Text('Offline data present for ${c.path}.',
                style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _download,
                icon: const Icon(Icons.download),
                label: const Text('Download for Offline'),
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
          Text(FlybriefNotams.attribution,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
              'NOTAM data is community/AIS-sourced via FlyBrief and is advisory '
              'only. Always confirm against the official national briefing '
              'before flight.'),
        ],
      ),
    );
  }
}
