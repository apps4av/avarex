import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:universal_io/io.dart';

/// Speaks demo narration. Uses platform TTS, then Linux `espeak`/`spd-say` if needed.
class DemoSpeech {
  DemoSpeech._();
  static final DemoSpeech instance = DemoSpeech._();

  FlutterTts? _tts;
  bool _initAttempted = false;
  bool _ttsReady = false;

  Future<void> init() async {
    if (_initAttempted) {
      return;
    }
    _initAttempted = true;
    if (kIsWeb) {
      await _initTts();
      return;
    }
    await _initTts();
  }

  Future<void> _initTts() async {
    try {
      final FlutterTts tts = FlutterTts();
      await tts.setSpeechRate(0.48);
      await tts.setVolume(1.0);
      await tts.setPitch(1.0);
      await tts.awaitSpeakCompletion(true);
      _tts = tts;
      _ttsReady = true;
    } catch (_) {
      _tts = null;
      _ttsReady = false;
    }
  }

  /// Speaks [text] and returns when finished (or immediately if TTS is unavailable).
  Future<bool> speak(String text) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    await init();
    await stop();
    if (_ttsReady && _tts != null) {
      try {
        await _tts!.speak(trimmed);
        return true;
      } catch (_) {
        _ttsReady = false;
      }
    }
    return _speakLinux(trimmed);
  }

  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }

  Future<void> pause() async {
    try {
      await _tts?.pause();
    } catch (_) {
      await stop();
    }
  }

  Future<bool> _speakLinux(String text) async {
    if (kIsWeb) {
      return false;
    }
    try {
      if (!Platform.isLinux) {
        return false;
      }
    } catch (_) {
      return false;
    }
    const List<List<String>> commands = <List<String>>[
      <String>['espeak-ng', '-s', '140'],
      <String>['espeak', '-s', '140'],
      <String>['spd-say'],
    ];
    for (final List<String> cmd in commands) {
      try {
        final ProcessResult result = await Process.run(
          cmd.first,
          <String>[...cmd.skip(1), text],
        );
        if (result.exitCode == 0) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }
}
