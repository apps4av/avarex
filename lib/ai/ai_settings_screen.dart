import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../constants.dart';
import 'ai_credentials.dart';

/// Lets the pilot supply their own OpenAI-compatible AI provider for the
/// Flight Intelligence feature. Nothing is bundled with the app; the endpoint,
/// key and model are stored in platform secure storage on this device only.
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  final _credentials = const AiCredentials();
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();
  final _modelController = TextEditingController();
  bool _busy = false;
  bool _hideKey = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _credentials.read().then((config) {
      if (!mounted) return;
      setState(() {
        _urlController.text = config.baseUrl;
        _keyController.text = config.apiKey;
        _modelController.text =
            config.model.isEmpty ? AiCredentials.defaultModel : config.model;
      });
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  AiConfig get _current => AiConfig(
        baseUrl: _urlController.text,
        apiKey: _keyController.text,
        model: _modelController.text,
      );

  Future<void> _save() async {
    await _credentials.write(_current);
    if (!mounted) return;
    setState(() => _message = _current.isUsable
        ? 'Saved securely on this device.'
        : 'Enter at least a provider URL and a model to enable AI.');
  }

  Future<void> _clear() async {
    await _credentials.clear();
    _urlController.clear();
    _keyController.clear();
    _modelController.text = AiCredentials.defaultModel;
    if (!mounted) return;
    setState(() => _message = 'AI provider settings cleared.');
  }

  Future<void> _test() async {
    final config = _current;
    if (!config.isUsable) {
      setState(() => _message = 'Enter a provider URL and a model first.');
      return;
    }
    setState(() {
      _busy = true;
      _message = 'Testing connection...';
    });
    try {
      final response = await http.post(
        config.chatCompletionsUri,
        headers: {
          'Content-Type': 'application/json',
          if (config.apiKey.isNotEmpty)
            'Authorization': 'Bearer ${config.apiKey}',
        },
        body: jsonEncode({
          'model': config.model,
          'messages': [
            {'role': 'user', 'content': 'Reply with the single word: ok'}
          ],
          'max_tokens': 5,
        }),
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = response.statusCode == 200
            ? 'Connection successful; provider responded.'
            : 'Provider returned HTTP ${response.statusCode}. '
                'Check the URL, key and model.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Could not reach the provider. Check the URL and network.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text('Flight Intelligence Setup'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('AI provider',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
              'Flight Intelligence uses an AI provider that you supply. Enter '
              'the base URL of any OpenAI-compatible chat-completions API, an '
              'optional API key, and the model name. Requests are sent from '
              'this device directly to your provider; nothing is routed through '
              'AvareX servers.'),
          const SizedBox(height: 16),
          TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Provider base URL',
              hintText: 'https://api.openai.com/v1',
              helperText: 'OpenAI-compatible root; "/chat/completions" is added',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyController,
            obscureText: _hideKey,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'API key (optional)',
              helperText: 'Leave blank for keyless local servers',
              suffixIcon: IconButton(
                icon: Icon(_hideKey ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _hideKey = !_hideKey),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _modelController,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Model',
              hintText: 'gpt-4o-mini',
            ),
          ),
          const SizedBox(height: 16),
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
                label: const Text('Test Connection'),
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
          const Text(
              'Responses are generated by an AI model and may be inaccurate. '
              'Do not use this when life, health or property are at stake. Your '
              'API key is stored only in this device\'s secure storage.',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
