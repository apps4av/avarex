import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Secure storage for the optional, user-supplied Open-Meteo API key.
//
// Open-Meteo's free endpoint is used by default (non-commercial, CC BY 4.0).
// A user who needs commercial-compliant access may enter their own key, which
// routes requests to the customer endpoint. The key is never embedded in the
// app, source, logs, or downloaded data.
class OpenMeteoCredentials {
  static const _key = 'open-meteo-api-key';
  final FlutterSecureStorage _storage;

  const OpenMeteoCredentials(
      {FlutterSecureStorage storage = const FlutterSecureStorage(
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
