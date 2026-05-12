import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Singleton speech-to-text engine. Lives for the lifetime of the app so the
/// recognizer survives navigation between Map / Plate / Plan / Find / etc.
///
/// The [TranscribeScreen] is just a *view* of this service: it subscribes to
/// the [ValueNotifier]s and dispatches start/stop/clear calls. A small
/// [TranscribeStatusOverlay] pill, rendered globally on [MainScreen], lets
/// the pilot see and stop transcription from any tab.
///
/// Audio source: the OS microphone. The intended cockpit setup is to wire
/// the aviation headset's audio output (or an aviation audio splitter cable)
/// into the phone's audio input with a 3.5 mm TRRS cable (plus a USB-C or
/// Lightning audio adapter on phones without a 3.5 mm jack). The phone then
/// captures ATC audio plus the pilot's own transmissions as a normal
/// microphone signal — no Bluetooth involved. If nothing is wired in, the
/// phone's built-in microphone is used as a fallback (poor quality due to
/// cockpit noise).
class TranscribeService {
  static final TranscribeService _instance = TranscribeService._internal();

  factory TranscribeService() => _instance;

  TranscribeService._internal();

  final SpeechToText _speech = SpeechToText();

  // ---- Public, observable state -------------------------------------------

  final ValueNotifier<bool> isInitialized = ValueNotifier(false);
  final ValueNotifier<bool> isListening = ValueNotifier(false);
  final ValueNotifier<bool> isStarting = ValueNotifier(false);
  final ValueNotifier<double> audioLevel = ValueNotifier(0);
  final ValueNotifier<String> statusMessage = ValueNotifier('Idle');
  final ValueNotifier<String?> initError = ValueNotifier(null);
  final ValueNotifier<String> partial = ValueNotifier('');
  final ValueNotifier<List<TranscriptEntry>> entries =
      ValueNotifier(<TranscriptEntry>[]);

  bool _userStopRequested = false;
  bool _initInProgress = false;

  // ---- Init ---------------------------------------------------------------

  /// Idempotent. Safe to call from many places (e.g. each time the Transcribe
  /// screen opens). Returns immediately if already initialized.
  Future<void> init() async {
    if (isInitialized.value || _initInProgress) return;
    _initInProgress = true;
    try {
      final ok = await _speech.initialize(
        onStatus: _onStatus,
        onError: _onError,
        debugLogging: false,
      );
      isInitialized.value = ok;
      if (!ok) {
        initError.value =
            'Speech recognition is not available on this device. On Android, install/enable a speech recognizer (e.g. Google) and grant microphone permission.';
      } else {
        initError.value = null;
      }
    } catch (e) {
      isInitialized.value = false;
      initError.value = 'Failed to initialize speech recognition: $e';
    } finally {
      _initInProgress = false;
    }
  }

  // ---- Recognizer callbacks ----------------------------------------------

  void _onStatus(String status) {
    statusMessage.value = status;
    // The platform recognizer auto-stops after `pauseFor` of silence; restart
    // it if the user hasn't pressed Stop, so the screen functions as a
    // continuous live transcription view.
    final stoppedByRecognizer =
        status == 'done' || status == 'notListening';
    if (stoppedByRecognizer && isListening.value && !_userStopRequested) {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (isListening.value &&
            !_userStopRequested &&
            !_speech.isListening) {
          _startRecognition();
        }
      });
    }
  }

  void _onError(SpeechRecognitionError err) {
    statusMessage.value = 'Error: ${err.errorMsg}';
    final recoverable = !err.permanent;
    if (recoverable && isListening.value && !_userStopRequested) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (isListening.value &&
            !_userStopRequested &&
            !_speech.isListening) {
          _startRecognition();
        }
      });
    }
  }

  // ---- Public control surface --------------------------------------------

  Future<void> start() async {
    if (!isInitialized.value) {
      await init();
      if (!isInitialized.value) return;
    }
    if (isListening.value || isStarting.value) return;

    isStarting.value = true;
    _userStopRequested = false;
    statusMessage.value = 'Preparing audio…';

    try {
      await WakelockPlus.enable();
    } catch (_) { /* ignore */ }

    isListening.value = true;
    isStarting.value = false;

    await _startRecognition();
  }

  Future<void> _startRecognition() async {
    try {
      await _speech.listen(
        onResult: _onResult,
        listenFor: const Duration(minutes: 30),
        pauseFor: const Duration(seconds: 5),
        onSoundLevelChange: (level) {
          audioLevel.value = level;
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: ListenMode.dictation,
          cancelOnError: false,
          autoPunctuation: true,
        ),
      );
    } catch (e) {
      isListening.value = false;
      statusMessage.value = 'Failed to start: $e';
      try {
        await WakelockPlus.disable();
      } catch (_) { /* ignore */ }
    }
  }

  Future<void> stop() async {
    _userStopRequested = true;
    isListening.value = false;
    isStarting.value = false;

    try {
      await _speech.stop();
    } catch (_) { /* ignore */ }
    try {
      await WakelockPlus.disable();
    } catch (_) { /* ignore */ }

    // Promote any in-flight partial result to a finalized entry so nothing
    // is lost when the pilot stops mid-utterance.
    final p = partial.value.trim();
    if (p.isNotEmpty) {
      final list = List<TranscriptEntry>.from(entries.value)
        ..add(TranscriptEntry(DateTime.now(), p));
      entries.value = list;
    }
    partial.value = '';
    audioLevel.value = 0;
    statusMessage.value = 'Stopped';
  }

  void _onResult(SpeechRecognitionResult result) {
    if (result.finalResult) {
      final words = result.recognizedWords.trim();
      if (words.isNotEmpty) {
        final list = List<TranscriptEntry>.from(entries.value)
          ..add(TranscriptEntry(DateTime.now(), words));
        entries.value = list;
      }
      partial.value = '';
    } else {
      partial.value = result.recognizedWords;
    }
  }

  void clear() {
    entries.value = <TranscriptEntry>[];
    partial.value = '';
  }

  bool get hasContent => entries.value.isNotEmpty || partial.value.isNotEmpty;
}

class TranscriptEntry {
  final DateTime timestamp;
  final String text;
  const TranscriptEntry(this.timestamp, this.text);
}
