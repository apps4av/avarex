import 'package:flutter/material.dart';

import '../storage.dart';
import 'open_meteo_credentials.dart';
import 'open_meteo_winds.dart';
import 'package:latlong2/latlong.dart';

// Optional Open-Meteo API key management.
//
// Open-Meteo powers global winds-aloft outside US FB coverage. The free,
// non-commercial endpoint is used by default; a user may enter a personal
// Open-Meteo API key for commercial-compliant access. The key is stored in
// platform secure storage and never embedded in the app.
class OpenMeteoSettingsScreen extends StatefulWidget {
  const OpenMeteoSettingsScreen({super.key});

  @override
  State<OpenMeteoSettingsScreen> createState() => _OpenMeteoSettingsScreenState();
}

class _OpenMeteoSettingsScreenState extends State<OpenMeteoSettingsScreen> {
  final _credentials = const OpenMeteoCredentials();
  final _keyController = TextEditingController();
  bool _busy = false;
  bool _hideKey = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _credentials.read().then((value) {
      if (mounted && value != null) setState(() => _keyController.text = value);
    });
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    await _credentials.write(_keyController.text);
    if (mounted) {
      setState(() => _message = _keyController.text.trim().isEmpty
          ? 'Using the free Open-Meteo endpoint (non-commercial).'
          : 'API key saved securely on this device.');
    }
  }

  Future<void> _clearKey() async {
    await _credentials.clear();
    _keyController.clear();
    if (mounted) {
      setState(() => _message = 'API key cleared. Using the free endpoint.');
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _busy = true;
      _message = 'Testing Open-Meteo connection...';
    });
    final key = _keyController.text.trim();
    // Test at the current map center; falls back to a well-covered point.
    LatLng where;
    try {
      where = LatLng(Storage().settings.getCenterLatitude(),
          Storage().settings.getCenterLongitude());
    } catch (_) {
      where = const LatLng(50.03, 8.55); // Frankfurt
    }
    final winds = await OpenMeteoWinds.fetch(where, apiKey: key.isEmpty ? null : key);
    if (mounted) {
      setState(() {
        _busy = false;
        _message = winds != null
            ? 'Connection successful; winds aloft retrieved.'
            : 'No winds returned. Check the key or try again later.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Open-Meteo Winds')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Open-Meteo winds aloft',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
              'Winds aloft outside US coverage are retrieved from Open-Meteo '
              'using its pressure-level forecast. The free endpoint is used by '
              'default and requires no key.'),
          const SizedBox(height: 16),
          TextField(
            controller: _keyController,
            obscureText: _hideKey,
            decoration: InputDecoration(
              labelText: 'Optional Open-Meteo API key',
              helperText: 'Only needed for commercial-compliant use',
              suffixIcon: IconButton(
                icon: Icon(_hideKey ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _hideKey = !_hideKey),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _saveKey,
                icon: const Icon(Icons.save),
                label: const Text('Save'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _testConnection,
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Test Connection'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _clearKey,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear Key'),
              ),
            ],
          ),
          if (_busy) const Padding(
            padding: EdgeInsets.only(top: 16),
            child: LinearProgressIndicator(),
          ),
          if (_message != null) Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(_message!),
          ),
          const SizedBox(height: 24),
          Text(OpenMeteoWinds.attribution,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
              'Weather data by Open-Meteo.com, licensed under CC BY 4.0. '
              'The free API is intended for non-commercial use; supply your own '
              'API key for commercial-compliant access. Forecast winds are '
              'advisory and not a substitute for an official weather briefing.'),
        ],
      ),
    );
  }
}
