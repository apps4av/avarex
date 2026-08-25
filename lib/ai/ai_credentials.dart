import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage for the optional, user-supplied AI provider configuration.
///
/// Flight Intelligence talks to an OpenAI-compatible chat-completions endpoint
/// that the pilot supplies (base URL + API key + model). Nothing is embedded in
/// the app, source, logs or downloaded data. When no configuration is present
/// the feature simply prompts the pilot to add one.
///
/// The base URL is the OpenAI-compatible root, e.g.:
///   https://api.openai.com/v1
///   https://openrouter.ai/api/v1
///   http://192.168.1.10:11434/v1   (a local llama.cpp / Ollama server)
/// The request is always POSTed to `<baseUrl>/chat/completions`.
class AiConfig {
  final String baseUrl;
  final String apiKey;
  final String model;

  const AiConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });

  /// A configuration is usable once a base URL and a model are set. The API key
  /// is optional so local, keyless servers (llama.cpp, Ollama, LM Studio) work.
  bool get isUsable => baseUrl.isNotEmpty && model.isNotEmpty;

  /// The full chat-completions endpoint derived from [baseUrl].
  Uri get chatCompletionsUri {
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$root/chat/completions');
  }
}

/// Reads and writes the AI provider configuration in platform secure storage.
class AiCredentials {
  static const _urlKey = 'ai-provider-base-url';
  static const _apiKey = 'ai-provider-api-key';
  static const _modelKey = 'ai-provider-model';

  static const String defaultModel = 'gpt-4o-mini';

  final FlutterSecureStorage _storage;

  const AiCredentials(
      {FlutterSecureStorage storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      )})
      : _storage = storage;

  Future<AiConfig> read() async {
    final url = (await _storage.read(key: _urlKey))?.trim() ?? '';
    final key = (await _storage.read(key: _apiKey))?.trim() ?? '';
    final model = (await _storage.read(key: _modelKey))?.trim() ?? '';
    return AiConfig(baseUrl: url, apiKey: key, model: model);
  }

  Future<void> write(AiConfig config) async {
    final url = config.baseUrl.trim();
    final key = config.apiKey.trim();
    final model = config.model.trim();
    if (url.isEmpty) {
      await _storage.delete(key: _urlKey);
    } else {
      await _storage.write(key: _urlKey, value: url);
    }
    if (key.isEmpty) {
      await _storage.delete(key: _apiKey);
    } else {
      await _storage.write(key: _apiKey, value: key);
    }
    if (model.isEmpty) {
      await _storage.delete(key: _modelKey);
    } else {
      await _storage.write(key: _modelKey, value: model);
    }
  }

  Future<void> clear() async {
    await _storage.delete(key: _urlKey);
    await _storage.delete(key: _apiKey);
    await _storage.delete(key: _modelKey);
  }
}
