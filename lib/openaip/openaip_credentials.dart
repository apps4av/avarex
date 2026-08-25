import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class OpenAipCredentials {
  static const _key = 'openaip-api-key';
  final FlutterSecureStorage _storage;

  const OpenAipCredentials({FlutterSecureStorage storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  )})
      : _storage = storage;

  Future<String?> read() async {
    final value = (await _storage.read(key: _key))?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> write(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await clear();
      return;
    }
    await _storage.write(key: _key, value: normalized);
  }

  Future<void> clear() => _storage.delete(key: _key);
}
