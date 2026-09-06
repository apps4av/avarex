import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Firebase App Check startup for every platform that initializes Firebase.
///
/// Release:
///   Android — Play Integrity
///   iOS / macOS — App Attest, DeviceCheck fallback
///   Windows — debug provider only (FlutterFire desktop C++ SDK limitation)
///
/// Debug (`flutter run`): Android / Apple use the debug provider so simulators
/// and local devices can talk to Firebase. Register the token printed in the
/// logs under Firebase Console → App Check → Apps → Manage debug tokens.
class AppCheckService {
  /// Replaced in the Windows GitHub Action from
  /// `secrets.APP_CHECK_WINDOWS_DEBUG_TOKEN`. Create that token in
  /// Firebase Console → App Check → the Windows app → Manage debug tokens.
  static const String _windowsDebugToken =
      '@@__app_check_windows_debug_token__@@';

  static String? get windowsDebugToken {
    const token = _windowsDebugToken;
    if (token.isEmpty || token.contains('@@__')) {
      return null;
    }
    return token;
  }

  static Future<void> activate() async {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
      providerWindows: WindowsDebugProvider(debugToken: windowsDebugToken),
    );
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
  }
}
