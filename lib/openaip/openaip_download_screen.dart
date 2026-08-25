import 'package:flutter/material.dart';

import '../storage.dart';
import 'openaip_client.dart';
import 'openaip_changes.dart';
import 'openaip_credentials.dart';
import 'openaip_database.dart';
import 'openaip_sync_service.dart';

class OpenAipDownloadScreen extends StatefulWidget {
  const OpenAipDownloadScreen({super.key});

  @override
  State<OpenAipDownloadScreen> createState() => _OpenAipDownloadScreenState();
}

class _OpenAipDownloadScreenState extends State<OpenAipDownloadScreen> {
  final _credentials = const OpenAipCredentials();
  final _keyController = TextEditingController();
  String _country = 'SE';
  bool _busy = false;
  bool _hideKey = true;
  double? _progress;
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
    if (mounted) setState(() => _message = 'API key saved securely on this device.');
  }

  Future<void> _clearKey() async {
    await _credentials.clear();
    _keyController.clear();
    if (mounted) setState(() => _message = 'API key cleared from this device.');
  }

  Future<void> _testConnection() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _message = 'Enter your personal openAIP API key first.');
      return;
    }
    setState(() { _busy = true; _message = 'Testing openAIP connection...'; });
    final client = OpenAipClient.withKey(key);
    try {
      await client.fetchCountry(OpenAipDataset.airports, _country, limit: 1);
      await _credentials.write(key);
      if (mounted) setState(() => _message = 'Connection successful; API key saved securely.');
    } catch (error) {
      if (mounted) setState(() => _message = 'Connection failed: $error');
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() => _message = 'Enter your personal openAIP API key first.');
      return;
    }
    setState(() { _busy = true; _progress = 0; _message = 'Starting openAIP download...'; });
    try {
      await _credentials.write(key);
      final database = OpenAipDatabase(
        database: await OpenAipDatabase.open(Storage().dataDir),
      );
      final client = OpenAipClient.withKey(key);
      final syncService = OpenAipSyncService.create(
        client: client,
        database: database,
      );
      final result = await syncService.syncCountry(_country, onProgress: (progress, message) {
        if (mounted) setState(() { _progress = progress; _message = message; });
      });
      client.close();
      OpenAipChanges.notifyChanged();
      if (mounted) {
        setState(() => _message = 'Installed ${result.airports} airports, ${result.navaids} navaids, '
            '${result.reportingPoints} reporting points, ${result.airspaces} airspaces, '
            'and ${result.obstacles} obstacles for $_country.');
      }
    } catch (error) {
      if (mounted) setState(() => _message = 'Unable to install openAIP data: $error');
    } finally {
      if (mounted) setState(() { _busy = false; _progress = null; });
    }
  }

  Future<void> _remove() async {
    setState(() { _busy = true; _message = 'Removing openAIP data...'; });
    try {
      final database = OpenAipDatabase(database: await OpenAipDatabase.open(Storage().dataDir));
      await database.deleteCountry(_country);
      OpenAipChanges.notifyChanged();
      if (mounted) setState(() => _message = 'Removed openAIP data for $_country.');
    } catch (error) {
      if (mounted) setState(() => _message = 'Unable to remove openAIP data: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('openAIP Data')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'openAIP is community-maintained supplementary data, not certified for primary navigation. '
          'Data is licensed CC BY-NC 4.0. Your personal API key is stored securely on this device.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _keyController,
          obscureText: _hideKey,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Personal openAIP API key',
            suffixIcon: IconButton(
              onPressed: () => setState(() => _hideKey = !_hideKey),
              icon: Icon(_hideKey ? Icons.visibility : Icons.visibility_off),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(onPressed: _busy ? null : _saveKey, icon: const Icon(Icons.key), label: const Text('Save Key')),
            OutlinedButton.icon(onPressed: _busy ? null : _testConnection, icon: const Icon(Icons.wifi_tethering), label: const Text('Test Connection')),
            TextButton.icon(onPressed: _busy ? null : _clearKey, icon: const Icon(Icons.delete_outline), label: const Text('Clear Key')),
          ],
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: _country,
          maxLength: 2,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'ISO country code', helperText: 'Examples: SE, DE, FR'),
          onChanged: (value) => _country = value.trim().toUpperCase(),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _download,
          icon: const Icon(Icons.download),
          label: const Text('Download Country Data'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _remove,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Remove Country Data'),
        ),
        if (_progress != null) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(value: _progress),
        ],
        if (_message != null) ...[
          const SizedBox(height: 16),
          Text(_message!),
        ],
        const SizedBox(height: 16),
        const Text('Data used comes from openAIP and is licensed under the Creative Commons Attribution-NonCommercial 4.0 International License. Visit https://www.openaip.net and contribute to better aviation data, free for everyone to use and share.'),
      ],
    ),
  );
}
