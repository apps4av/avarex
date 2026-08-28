import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import '../constants.dart';
import '../storage.dart';

class FullScreen {
  static final ValueNotifier<bool> state = ValueNotifier<bool>(false);

  static bool get supported => Constants.supportsWindowManagement;

  static Future<void> applySaved() async {
    if (!supported) {
      return;
    }
    try {
      await windowManager.ensureInitialized();
      await set(Storage().settings.getFullScreen());
    }
    catch (e) {
      Storage().setException("Full screen failed: $e");
    }
  }

  static Future<void> set(bool on) async {
    if (!supported) {
      return;
    }
    try {
      await windowManager.setFullScreen(on);
      Storage().settings.setFullScreen(on);
      state.value = on;
    }
    catch (e) {
      Storage().setException("Full screen failed: $e");
    }
  }
}
