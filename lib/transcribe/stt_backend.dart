import 'package:flutter/foundation.dart';

/// Identifier for the currently-active STT engine. Surfaced to the UI so the
/// pilot can tell at a glance whether they're running the online platform
/// recognizer or fully-offline Whisper.
enum SttEngine {
  /// `speech_to_text` plugin → SFSpeechRecognizer on iOS, SpeechRecognizer on
  /// Android. Quality is good but usually requires an active internet
  /// connection on Android.
  platform,

  /// Whisper.cpp via `whisper_ggml_plus`. Fully offline once the model file is
  /// installed via the Downloads menu. Noticeably better at noisy ATC audio
  /// than the platform recognizer.
  whisper,
}

/// One finalized utterance produced by an [SttBackend].
@immutable
class SttUtterance {
  final DateTime timestamp;
  final String text;
  const SttUtterance(this.timestamp, this.text);
}

/// Callback shape used by [SttBackend] to push results up to the service.
typedef SttUtteranceCallback = void Function(SttUtterance utterance);
typedef SttPartialCallback = void Function(String partialText);
typedef SttStatusCallback = void Function(String message);
typedef SttErrorCallback = void Function(String message, {required bool recoverable});
typedef SttLevelCallback = void Function(double levelDbfs);

/// Engine-agnostic speech-to-text contract. Implementations:
///   * [PlatformSttBackend] — wraps the `speech_to_text` plugin
///   * [WhisperSttBackend]  — wraps `record` + `whisper_ggml_plus`
///
/// The backend pushes results back to the owner via the callbacks provided to
/// [init]; the owner (typically [TranscribeService]) is responsible for
/// turning those into [ValueNotifier] updates that the UI listens to.
abstract class SttBackend {
  /// Stable identifier — surfaced in the UI.
  SttEngine get engine;

  /// Idempotent. Returns true if the backend is ready to start.
  Future<bool> init({
    required SttUtteranceCallback onUtterance,
    required SttPartialCallback onPartial,
    required SttStatusCallback onStatus,
    required SttErrorCallback onError,
    required SttLevelCallback onLevel,
  });

  /// `true` once [init] succeeded.
  bool get isInitialized;

  /// Human-readable explanation of why [init] failed, if it did. Used by the
  /// Transcribe screen to render a help banner (e.g. "Install the Whisper
  /// voice pack from Downloads to use offline transcription.").
  String? get initError;

  /// Begin continuous recognition. Safe to call when already listening.
  Future<void> start();

  /// Stop recognition. Safe to call when already stopped. May emit one final
  /// partial → utterance promotion before returning.
  Future<void> stop();

  /// `true` between successful [start] and matching [stop].
  bool get isListening;

  /// Release any expensive resources (audio recorders, model handles).
  Future<void> dispose();
}
