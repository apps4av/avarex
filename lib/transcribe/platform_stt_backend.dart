import 'dart:async';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'stt_backend.dart';

/// Wraps the `speech_to_text` plugin (SFSpeechRecognizer on iOS,
/// SpeechRecognizer on Android). Used as the default engine when the Whisper
/// voice pack hasn't been downloaded yet.
class PlatformSttBackend implements SttBackend {
  PlatformSttBackend();

  @override
  SttEngine get engine => SttEngine.platform;

  final SpeechToText _speech = SpeechToText();

  bool _initialized = false;
  bool _listening = false;
  bool _userStopRequested = false;
  bool _initInProgress = false;
  String? _initError;

  SttUtteranceCallback? _onUtterance;
  SttPartialCallback? _onPartial;
  SttStatusCallback? _onStatus;
  SttErrorCallback? _onError;
  SttLevelCallback? _onLevel;

  String _partialBuffer = '';

  @override
  bool get isInitialized => _initialized;

  @override
  String? get initError => _initError;

  @override
  bool get isListening => _listening;

  @override
  Future<bool> init({
    required SttUtteranceCallback onUtterance,
    required SttPartialCallback onPartial,
    required SttStatusCallback onStatus,
    required SttErrorCallback onError,
    required SttLevelCallback onLevel,
  }) async {
    _onUtterance = onUtterance;
    _onPartial = onPartial;
    _onStatus = onStatus;
    _onError = onError;
    _onLevel = onLevel;

    if (_initialized || _initInProgress) return _initialized;
    _initInProgress = true;
    try {
      final ok = await _speech.initialize(
        onStatus: _onPluginStatus,
        onError: _onPluginError,
        debugLogging: false,
      );
      _initialized = ok;
      _initError = ok
          ? null
          : 'Speech recognition is not available on this device. On Android, install/enable a speech recognizer (e.g. Google) and grant microphone permission.';
    } catch (e) {
      _initialized = false;
      _initError = 'Failed to initialize speech recognition: $e';
    } finally {
      _initInProgress = false;
    }
    return _initialized;
  }

  void _onPluginStatus(String status) {
    _onStatus?.call(status);
    // The platform recognizer auto-stops after its internal VAD timeout
    // (1–3 s on Android, ~1 s on iOS) which is uncontrollable through this
    // plugin. Restart as fast as we can to minimize the dead window when a
    // short ATC call lands between sessions.
    final stoppedByRecognizer =
        status == 'done' || status == 'notListening';
    if (stoppedByRecognizer && _listening && !_userStopRequested) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (_listening && !_userStopRequested && !_speech.isListening) {
          _startRecognition();
        }
      });
    }
  }

  void _onPluginError(SpeechRecognitionError err) {
    _onError?.call(err.errorMsg, recoverable: !err.permanent);
    final recoverable = !err.permanent;
    if (recoverable && _listening && !_userStopRequested) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_listening && !_userStopRequested && !_speech.isListening) {
          _startRecognition();
        }
      });
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    if (result.finalResult) {
      final words = result.recognizedWords.trim();
      if (words.isNotEmpty) {
        _onUtterance?.call(SttUtterance(DateTime.now(), words));
      }
      _partialBuffer = '';
      _onPartial?.call('');
    } else {
      _partialBuffer = result.recognizedWords;
      _onPartial?.call(_partialBuffer);
    }
  }

  @override
  Future<void> start() async {
    if (!_initialized) return;
    if (_listening) return;
    _listening = true;
    _userStopRequested = false;
    await _startRecognition();
  }

  Future<void> _startRecognition() async {
    try {
      await _speech.listen(
        onResult: _onResult,
        // Long pauseFor so the plugin's Dart-side silence timer never adds
        // an extra stop on top of the platform's own VAD timeout. Sessions
        // end when the platform decides (or `listenFor` expires).
        listenFor: const Duration(minutes: 30),
        pauseFor: const Duration(minutes: 30),
        onSoundLevelChange: (level) {
          _onLevel?.call(level);
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          // `ListenMode.search` selects the short-utterance language model
          // (Android: `LANGUAGE_MODEL_WEB_SEARCH`; iOS: search-style task),
          // which has a tighter VAD and is a far better fit for bursty
          // ATC calls than `dictation`.
          listenMode: ListenMode.search,
          cancelOnError: false,
          autoPunctuation: true,
        ),
      );
    } catch (e) {
      _listening = false;
      _onError?.call('Failed to start: $e', recoverable: false);
    }
  }

  @override
  Future<void> stop() async {
    _userStopRequested = true;
    _listening = false;
    try {
      await _speech.stop();
    } catch (_) { /* ignore */ }
    // Promote any in-flight partial result to a finalized utterance so we
    // don't lose what the pilot was mid-saying when they tapped Stop.
    final p = _partialBuffer.trim();
    if (p.isNotEmpty) {
      _onUtterance?.call(SttUtterance(DateTime.now(), p));
      _partialBuffer = '';
      _onPartial?.call('');
    }
  }

  @override
  Future<void> dispose() async {
    if (_listening) {
      try {
        await _speech.stop();
      } catch (_) { /* ignore */ }
    }
    _listening = false;
    _initialized = false;
  }
}
