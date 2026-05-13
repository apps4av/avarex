import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import 'package:avaremp/storage.dart';

import 'platform_stt_backend.dart';
import 'stt_backend.dart';
import 'whisper_model_manager.dart';
import 'whisper_stt_backend.dart';

/// Singleton speech-to-text engine. Lives for the lifetime of the app so the
/// recognizer survives navigation between Map / Plate / Plan / Find / etc.
///
/// The [TranscribeScreen] is just a *view* of this service: it subscribes to
/// the [ValueNotifier]s and dispatches start/stop/clear calls. A small
/// [TranscribeStatusOverlay] pill, rendered globally on [MainScreen], lets
/// the pilot see and stop transcription from any tab.
///
/// ## Engine selection
///
/// At runtime the service picks one of two engines:
///
///  * [PlatformSttBackend] — wraps the OS recognizer via `speech_to_text`.
///    Default fallback. Usually requires an internet connection on Android.
///  * [WhisperSttBackend]  — fully offline, runs Whisper.cpp on the device
///    against a model file downloaded from the Downloads screen.
///
/// The choice is driven by [AppSettings.getTranscribeEngine]:
///   `auto`     → Whisper if its model is installed, else platform.
///   `platform` → always platform.
///   `whisper`  → always Whisper (fails fast if no model).
///
/// ## Audio source
///
/// The OS microphone. Recommended cockpit setup is to wire the aviation
/// headset's audio output into the phone's audio input with a 3.5 mm TRRS
/// cable (plus a USB-C / Lightning audio adapter on phones without a 3.5 mm
/// jack). The phone then sees ATC audio plus the pilot's own transmissions
/// as a normal mic signal — no Bluetooth pairing involved. If nothing is
/// wired in, the phone's built-in mic is used as a (noisy) fallback.
class TranscribeService {
  static final TranscribeService _instance = TranscribeService._internal();

  factory TranscribeService() => _instance;

  TranscribeService._internal();

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

  /// Which engine is currently in use. Mirrors [SttEngine] but is null until
  /// [init] has chosen a backend.
  final ValueNotifier<SttEngine?> activeEngine = ValueNotifier(null);

  SttBackend? _backend;
  bool _initInProgress = false;

  // ---- Init ---------------------------------------------------------------

  /// Idempotent. Safe to call from many places (e.g. each time the
  /// Transcribe screen opens). Picks the right backend based on user
  /// preference + model availability.
  Future<void> init() async {
    if (_initInProgress) return;
    _initInProgress = true;
    try {
      final preferred = _resolvePreferredEngine();

      // If we already have a backend and it matches the desired engine,
      // we're done. Otherwise we may need to tear it down and rebuild.
      if (_backend != null && _backend!.engine == preferred && isInitialized.value) {
        return;
      }
      if (_backend != null && _backend!.engine != preferred) {
        await _backend!.dispose();
        _backend = null;
        isInitialized.value = false;
      }

      _backend = _buildBackend(preferred);
      activeEngine.value = _backend!.engine;

      final ok = await _backend!.init(
        onUtterance: _onUtterance,
        onPartial: _onPartial,
        onStatus: _onBackendStatus,
        onError: _onBackendError,
        onLevel: _onLevel,
      );
      isInitialized.value = ok;
      initError.value = ok ? null : _backend!.initError;

      // If the user asked for Whisper but it failed (e.g. model missing),
      // transparently fall back to the platform engine so they can still
      // transcribe — but keep the error message in [initError] so the UI
      // can offer a "Download AI voice pack" prompt.
      if (!ok && preferred == SttEngine.whisper) {
        await _backend!.dispose();
        _backend = _buildBackend(SttEngine.platform);
        activeEngine.value = _backend!.engine;
        final fallbackOk = await _backend!.init(
          onUtterance: _onUtterance,
          onPartial: _onPartial,
          onStatus: _onBackendStatus,
          onError: _onBackendError,
          onLevel: _onLevel,
        );
        isInitialized.value = fallbackOk;
        // Combine the two error messages so the user sees both: "Whisper
        // model missing" and (if applicable) "platform recognizer also
        // unavailable".
        if (!fallbackOk) {
          initError.value =
              '${_backend!.initError ?? 'Speech recognition is unavailable.'} '
              '(AI voice pack also unavailable — install it from Downloads.)';
        }
      }
    } finally {
      _initInProgress = false;
    }
  }

  SttEngine _resolvePreferredEngine() {
    final raw = Storage().settings.getTranscribeEngine();
    switch (raw) {
      case 'platform':
        return SttEngine.platform;
      case 'whisper':
        return SttEngine.whisper;
      case 'auto':
      default:
        return WhisperModelManager().isAnyInstalled()
            ? SttEngine.whisper
            : SttEngine.platform;
    }
  }

  SttBackend _buildBackend(SttEngine engine) {
    switch (engine) {
      case SttEngine.whisper:
        return WhisperSttBackend(model: _chooseWhisperModel());
      case SttEngine.platform:
        return PlatformSttBackend();
    }
  }

  /// Picks the fastest Whisper variant from those installed. We prefer
  /// `tiny.en` over `base.en` because the ~3× lower inference cost keeps
  /// the transcript real-time even on mid-range phones in the cockpit; the
  /// accuracy gap is small enough that more captured utterances beats
  /// fewer-but-better ones for ATC use. If only the larger model is on
  /// disk we'll happily use it. Falls back to the user-preferred name and
  /// finally to `tiny.en` (which will fail init and trigger the download
  /// prompt) when nothing is installed.
  WhisperModel _chooseWhisperModel() {
    final mgr = WhisperModelManager();
    if (mgr.isInstalledSync(WhisperModel.tinyEn)) return WhisperModel.tinyEn;
    if (mgr.isInstalledSync(WhisperModel.baseEn)) return WhisperModel.baseEn;

    final saved = Storage().settings.getTranscribeWhisperModel();
    for (final v in kWhisperVoicePackVariants) {
      if (v.model.modelName == saved) return v.model;
    }
    return WhisperModel.tinyEn;
  }

  /// Tear down the current backend and let [init] pick a fresh one on next
  /// call. Used when the user changes the engine preference in the UI or
  /// installs / deletes a Whisper model on the Downloads screen.
  Future<void> reconfigure() async {
    if (_backend == null) {
      await init();
      return;
    }
    final wasListening = isListening.value;
    if (wasListening) {
      await stop();
    }
    await _backend!.dispose();
    _backend = null;
    isInitialized.value = false;
    await init();
    if (wasListening && isInitialized.value) {
      await start();
    }
  }

  // ---- Backend callbacks --------------------------------------------------

  void _onUtterance(SttUtterance u) {
    final list = List<TranscriptEntry>.from(entries.value)
      ..add(TranscriptEntry(u.timestamp, u.text));
    entries.value = list;
  }

  void _onPartial(String s) {
    partial.value = s;
  }

  void _onBackendStatus(String message) {
    statusMessage.value = message;
  }

  void _onBackendError(String message, {required bool recoverable}) {
    statusMessage.value = 'Error: $message';
    if (!recoverable) {
      isListening.value = false;
      // Best-effort: drop the wakelock so we don't pin the screen on a
      // permanently-broken recognizer.
      WakelockPlus.disable().catchError((_) {});
    }
  }

  void _onLevel(double levelDbfs) {
    audioLevel.value = levelDbfs;
  }

  // ---- Public control surface --------------------------------------------

  Future<void> start() async {
    if (!isInitialized.value) {
      await init();
      if (!isInitialized.value) return;
    }
    if (isListening.value || isStarting.value) return;

    isStarting.value = true;
    statusMessage.value = 'Preparing audio…';

    try {
      await WakelockPlus.enable();
    } catch (_) { /* ignore */ }

    isListening.value = true;
    isStarting.value = false;

    await _backend!.start();
  }

  Future<void> stop() async {
    isListening.value = false;
    isStarting.value = false;

    try {
      await _backend?.stop();
    } catch (_) { /* ignore */ }
    try {
      await WakelockPlus.disable();
    } catch (_) { /* ignore */ }

    audioLevel.value = 0;
    statusMessage.value = 'Stopped';
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
