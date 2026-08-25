import 'package:flutter/material.dart';

import '../constants.dart';
import 'opensky_credentials.dart';
import 'opensky_service.dart';

/// Settings for the optional internet (ADS-B) traffic layer backed by the
/// OpenSky Network. The pilot supplies their own OpenSky API client
/// (client_id/secret); nothing is bundled. The layer is off by default and is
/// clearly labelled advisory-only.
class OpenSkySettingsScreen extends StatefulWidget {
  const OpenSkySettingsScreen({super.key});

  @override
  State<OpenSkySettingsScreen> createState() => _OpenSkySettingsScreenState();
}

class _OpenSkySettingsScreenState extends State<OpenSkySettingsScreen> {
  final _credentials = const OpenSkyCredentials();
  final _idController = TextEditingController();
  final _secretController = TextEditingController();
  bool _enabled = false;
  bool _busy = false;
  bool _hideSecret = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _credentials.readClientId().then((v) {
      if (mounted) setState(() => _idController.text = v);
    });
    _credentials.readClientSecret().then((v) {
      if (mounted) setState(() => _secretController.text = v);
    });
    _credentials.readEnabled().then((v) {
      if (mounted) setState(() => _enabled = v);
    });
  }

  @override
  void dispose() {
    _idController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await _credentials.write(
      clientId: _idController.text,
      clientSecret: _secretController.text,
    );
    await _credentials.setEnabled(_enabled);
    if (mounted) {
      setState(() => _message = 'Saved securely on this device.');
    }
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _message = 'Testing OpenSky authentication...';
    });
    final err = await OpenSkyService.instance
        .testCredentials(_idController.text.trim(), _secretController.text.trim());
    if (mounted) {
      setState(() {
        _busy = false;
        _message = err ?? 'Authentication successful.';
      });
    }
  }

  Future<void> _clear() async {
    await _credentials.clear();
    _idController.clear();
    _secretController.clear();
    if (mounted) {
      setState(() {
        _enabled = false;
        _message = 'OpenSky settings cleared.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text('Internet Traffic (OpenSky)'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Prominent advisory / safety notice.
          Card(
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber, color: scheme.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Advisory only. Internet traffic from OpenSky is '
                      'crowd-sourced, delayed and incomplete. It is NOT for '
                      'separation or collision avoidance. A connected ADS-B '
                      'receiver remains the real-time traffic source.',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('OpenSky API client',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
              'Create a free account at opensky-network.org, open the Account '
              'page, create an API client, and paste its client ID and secret '
              'below. Traffic is fetched from your own account; nothing is '
              'bundled with the app and the credentials stay in this device\'s '
              'secure storage.'),
          const SizedBox(height: 16),
          TextField(
            controller: _idController,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Client ID',
              hintText: 'e.g. yourname-api-client',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _secretController,
            obscureText: _hideSecret,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Client secret',
              suffixIcon: IconButton(
                icon: Icon(_hideSecret ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _hideSecret = !_hideSecret),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show internet traffic on the map'),
            subtitle: const Text(
                'Enable the OpenSky layer (needs credentials above). Also '
                'turn on the "Traffic" map layer to see it.'),
            value: _enabled,
            onChanged: _busy ? null : (v) => setState(() => _enabled = v),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save),
                label: const Text('Save'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _test,
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Test'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _clear,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear'),
              ),
            ],
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_message!),
            ),
          const SizedBox(height: 24),
          Text(OpenSkyService.attribution,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
              'Data from The OpenSky Network, opensky-network.org, provided for '
              'non-commercial use. Coverage depends on community receivers and '
              'varies by region and altitude.',
              style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
