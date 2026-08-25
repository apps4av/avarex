import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage for the optional, user-supplied OpenSky Network API
/// credentials used by the internet (ADS-B) traffic layer.
///
/// OpenSky uses the OAuth2 client-credentials flow: the pilot creates an API
/// client in their own OpenSky account and supplies the client_id and
/// client_secret here. Nothing is embedded in the app, source, logs, or
/// downloaded data, and each pilot uses their own account/credits.
///
/// Internet traffic is ADVISORY ONLY: it is crowdsourced, delayed and
/// incomplete, and must never be used for separation or collision avoidance.
class OpenSkyCredentials {
  static const _idKey = 'opensky-client-id';
  static const _secretKey = 'opensky-client-secret';
  static const _enabledKey = 'opensky-enabled';

  final FlutterSecureStorage _storage;

  const OpenSkyCredentials(
      {FlutterSecureStorage storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      )})
      : _storage = storage;

  Future<String> readClientId() async =>
      (await _storage.read(key: _idKey))?.trim() ?? '';

  Future<String> readClientSecret() async =>
      (await _storage.read(key: _secretKey))?.trim() ?? '';

  /// Whether the pilot has turned the internet-traffic layer on. Off by
  /// default; only meaningful when credentials are also present.
  Future<bool> readEnabled() async =>
      (await _storage.read(key: _enabledKey)) == 'true';

  /// True when credentials are present AND the feature is enabled.
  Future<bool> isActive() async {
    if (!await readEnabled()) return false;
    final id = await readClientId();
    final secret = await readClientSecret();
    return id.isNotEmpty && secret.isNotEmpty;
  }

  Future<void> write({required String clientId, required String clientSecret}) async {
    final id = clientId.trim();
    final secret = clientSecret.trim();
    if (id.isEmpty) {
      await _storage.delete(key: _idKey);
    } else {
      await _storage.write(key: _idKey, value: id);
    }
    if (secret.isEmpty) {
      await _storage.delete(key: _secretKey);
    } else {
      await _storage.write(key: _secretKey, value: secret);
    }
  }

  Future<void> setEnabled(bool value) async =>
      _storage.write(key: _enabledKey, value: value ? 'true' : 'false');

  Future<void> clear() async {
    await _storage.delete(key: _idKey);
    await _storage.delete(key: _secretKey);
    await _storage.delete(key: _enabledKey);
  }
}
