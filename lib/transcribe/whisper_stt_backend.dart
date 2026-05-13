import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import 'stt_backend.dart';
import 'whisper_model_manager.dart';

/// Continuously listens to the microphone, slices the stream into utterances
/// using a simple amplitude-based VAD, and feeds each utterance through
/// Whisper.cpp via the `whisper_ggml_plus` package. Output is pushed back
/// to [TranscribeService] via the callbacks provided to [init].
///
/// VAD strategy (intentionally simple, no native ML deps):
///  * Sample the recorder's amplitude every [_amplitudePollInterval].
///  * Track `speechSeen` once amplitude crosses [_speechThresholdDbfs].
///  * After [_endOfUtteranceSilence] of sustained low amplitude *and* at
///    least [_minUtteranceLength] of audio, close the WAV file, hand it off
///    to Whisper, and start a fresh recording.
///  * Hard-cap a single utterance at [_maxUtteranceLength] so a pilot
///    leaving the PTT keyed never produces a multi-minute monster file.
class WhisperSttBackend implements SttBackend {
  WhisperSttBackend({required this.model});

  /// Which Whisper variant to use. Caller picks based on what's installed
  /// (see [WhisperModelManager.isInstalled]).
  final WhisperModel model;

  @override
  SttEngine get engine => SttEngine.whisper;

  static const Duration _amplitudePollInterval = Duration(milliseconds: 80);

  /// End-of-utterance silence — kept short so the transcript catches up to
  /// the pilot's mental model quickly. Trade-off: too short and we'll split
  /// a single ATC call across two transcribe jobs.
  static const Duration _endOfUtteranceSilence = Duration(milliseconds: 400);

  /// Minimum recording window before we'll call something an utterance. Set
  /// just above the typical "click of the PTT being keyed" duration so the
  /// VAD doesn't fire on single-frame transients.
  static const Duration _minUtteranceLength = Duration(milliseconds: 400);

  /// Hard cap on a single utterance. Beyond this we force-flush so the
  /// Whisper inference for that chunk stays bounded — a 6 s clip on tiny.en
  /// transcribes in ~1 s on a modern phone; a 20 s clip can take 5–10 s and
  /// pushes the rest of the queue out of real-time.
  static const Duration _maxUtteranceLength = Duration(seconds: 6);

  /// Number of CPU threads Whisper.cpp gets for inference. The package
  /// default is 6 which oversubscribes on most 4-core SoCs and actually
  /// runs slower due to cache thrash. 4 is the sweet spot on
  /// modern phones; can be bumped on flagship 8-core devices later.
  static const int _whisperThreads = 4;

  /// dBFS threshold above which we treat the chunk as speech. The `record`
  /// plugin reports amplitude in negative-dBFS (0 = full-scale, ≤−160 =
  /// silence). −38 dBFS is loud enough to skip typical cabin hiss but quiet
  /// enough to catch a clipped ATC transmission.
  static const double _speechThresholdDbfs = -38.0;

  final AudioRecorder _recorder = AudioRecorder();
  final WhisperController _controller = WhisperController();

  String? _tempDir;
  bool _initialized = false;
  bool _listening = false;
  String? _initError;

  // Per-utterance state.
  String? _currentRecordingPath;
  DateTime? _utteranceStart;
  bool _speechSeen = false;
  DateTime? _silenceStart;
  Timer? _pollTimer;
  int _utteranceCounter = 0;

  /// Number of `_transcribeFile` calls currently waiting on the Whisper
  /// isolate. Used to back-pressure the queue so a slow device never falls
  /// further than [_maxInflight] utterances behind reality.
  int _inflightTranscriptions = 0;

  /// Maximum simultaneous Whisper inferences in flight. The package
  /// serializes onto a single isolate anyway, so this caps the pending
  /// queue depth more than concurrent work. Anything past this is dropped
  /// rather than queued — better to skip an ATC call than have the
  /// transcript drift 30 seconds behind the radio.
  static const int _maxInflight = 2;

  // Caller plumbing.
  SttUtteranceCallback? _onUtterance;
  SttPartialCallback? _onPartial;
  SttStatusCallback? _onStatus;
  SttErrorCallback? _onError;
  SttLevelCallback? _onLevel;

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
    if (_initialized) return true;

    try {
      // Verify model file is on disk before we claim we're initialized.
      if (!await WhisperModelManager().isInstalled(model)) {
        _initError =
            'AI voice pack not installed. Download it from the Downloads screen.';
        return false;
      }

      // Pre-warm the controller so it knows the model path. This does not
      // actually load weights into RAM — that happens lazily on first
      // transcribe — but it does ensure the file exists where the FFI bridge
      // expects to find it.
      await _controller.initModel(model);

      // Mic permission. `record` returns false if either denied or
      // permanently rejected.
      final granted = await _recorder.hasPermission();
      if (!granted) {
        _initError =
            'Microphone permission denied. Enable it in system settings to use offline transcription.';
        return false;
      }

      _tempDir ??= (await getTemporaryDirectory()).path;
      _initialized = true;
      _initError = null;
      return true;
    } catch (e) {
      _initialized = false;
      _initError = 'Failed to initialize Whisper backend: $e';
      return false;
    }
  }

  @override
  Future<void> start() async {
    if (!_initialized) return;
    if (_listening) return;
    _listening = true;
    _onStatus?.call('Listening (offline AI)');
    try {
      await _beginNewUtteranceRecording();
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(_amplitudePollInterval, (_) {
        // Drive the VAD loop. Errors here shouldn't kill the timer.
        _onAmplitudeTick().catchError((Object e, StackTrace st) {
          if (kDebugMode) {
            debugPrint('WhisperSttBackend VAD tick error: $e\n$st');
          }
        });
      });
    } catch (e) {
      _listening = false;
      _onError?.call('Failed to start recorder: $e', recoverable: false);
    }
  }

  Future<void> _beginNewUtteranceRecording() async {
    final id = (_utteranceCounter++).toString().padLeft(6, '0');
    final path = '${_tempDir!}/avarex_utterance_$id.wav';
    _currentRecordingPath = path;
    _utteranceStart = DateTime.now();
    _speechSeen = false;
    _silenceStart = null;

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        // Aviation headsets pump strong signal — disable AGC/AEC so we don't
        // over-quiet a busy ATC transmission. Noise suppression we leave on
        // where supported; cockpit slipstream hiss is so broadband that the
        // recognizer benefits from it.
        autoGain: false,
        echoCancel: false,
        noiseSuppress: true,
      ),
      path: path,
    );
  }

  Future<void> _onAmplitudeTick() async {
    if (!_listening || _currentRecordingPath == null) return;

    final amp = await _recorder.getAmplitude();
    final dbfs = amp.current;
    _onLevel?.call(dbfs);

    final now = DateTime.now();
    final age = now.difference(_utteranceStart!);

    if (dbfs > _speechThresholdDbfs) {
      _speechSeen = true;
      _silenceStart = null;
    } else if (_speechSeen) {
      _silenceStart ??= now;
    }

    final silenceDuration = _silenceStart == null
        ? Duration.zero
        : now.difference(_silenceStart!);

    final endedBySilence = _speechSeen &&
        age >= _minUtteranceLength &&
        silenceDuration >= _endOfUtteranceSilence;
    final endedByCap = age >= _maxUtteranceLength;

    if (endedBySilence || endedByCap) {
      await _finishUtteranceAndStartNext(transcribe: _speechSeen);
    }
  }

  /// Stops the current recorder, hands the file off to Whisper (if we ever
  /// heard speech), and immediately spins up a fresh recording so the mic
  /// gap between utterances is < 50 ms in practice.
  Future<void> _finishUtteranceAndStartNext({required bool transcribe}) async {
    final pathToProcess = _currentRecordingPath;
    _currentRecordingPath = null;

    String? stopped;
    try {
      stopped = await _recorder.stop();
    } catch (e) {
      _onError?.call('Recorder stop failed: $e', recoverable: true);
    }

    if (_listening) {
      try {
        await _beginNewUtteranceRecording();
      } catch (e) {
        _onError?.call('Failed to restart recorder: $e', recoverable: false);
        _listening = false;
        _pollTimer?.cancel();
      }
    }

    // The path `record` actually used; fall back to ours.
    final wavPath = stopped ?? pathToProcess;
    if (wavPath == null) return;
    if (!transcribe) {
      _safeDelete(wavPath);
      return;
    }

    // Back-pressure: if Whisper is already lagging behind the radio, drop
    // this chunk rather than queue it. Lets the transcript stay roughly
    // real-time on slow phones at the cost of some missed utterances.
    if (_inflightTranscriptions >= _maxInflight) {
      _safeDelete(wavPath);
      _onStatus?.call('Transcription falling behind — dropped utterance');
      return;
    }

    // Fire-and-forget transcribe. With our 6 s max-utterance cap and
    // tiny.en model, this typically returns in under 1 s on modern phones.
    // ignore: unawaited_futures
    _transcribeFile(wavPath);
  }

  Future<void> _transcribeFile(String wavPath) async {
    _inflightTranscriptions++;
    // The "…" placeholder is a cheap visual hint that processing is in
    // flight; cleared in `finally`.
    _onPartial?.call('…');
    try {
      final result = await _controller.transcribe(
        model: model,
        audioPath: wavPath,
        lang: 'en',
        // Speed knobs:
        //  * `threads`: capped at 4 (see [_whisperThreads]).
        //  * `withTimestamps: false` — we don't surface segment timestamps,
        //    only the final text, so skipping timestamp generation shaves a
        //    little off every chunk.
        //  * `vadMode: disabled` — we already chunk audio with our own
        //    amplitude VAD; running another VAD inside whisper.cpp wastes
        //    CPU on every chunk.
        //  * `convert: false` — the file is already a 16 kHz mono WAV
        //    written by `record`, so the package's conversion step (which
        //    would error without `whisper_ggml_plus_ffmpeg`) is a no-op
        //    anyway, but skipping it removes the conditional logging.
        threads: _whisperThreads,
        withTimestamps: false,
        vadMode: WhisperVadMode.disabled,
        convert: false,
      );
      final raw = result?.transcription.text ?? '';
      final cleaned = _cleanWhisperOutput(raw);
      if (cleaned.isNotEmpty) {
        _onUtterance?.call(SttUtterance(DateTime.now(), cleaned));
      }
    } catch (e) {
      _onError?.call('Whisper transcription failed: $e', recoverable: true);
    } finally {
      _inflightTranscriptions--;
      _onPartial?.call('');
      _safeDelete(wavPath);
      // whisper_ggml_plus skips its conversion step when the input already
      // ends in `.wav` (which ours does), so no side-car file is produced.
      // We still try to clean any stray copy in case behaviour changes.
      _safeDelete('$wavPath.wav');
    }
  }

  void _safeDelete(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) {
        f.deleteSync();
      }
    } catch (_) { /* ignore */ }
  }

  /// Strip out common Whisper hallucinations on silent / near-silent audio.
  /// These show up most often when the pilot's headset is keyed but no one
  /// is talking — Whisper invents "thanks for watching", "music plays",
  /// "[BLANK_AUDIO]" etc.
  static const _hallucinationFragments = <String>[
    'thanks for watching',
    'thank you for watching',
    'subscribe to',
    '[blank_audio]',
    '(silence)',
    '(music)',
    '(music playing)',
    '[music]',
    '[silence]',
    'you you you',
    '. . .',
  ];

  String _cleanWhisperOutput(String s) {
    var t = s.trim();
    if (t.isEmpty) return '';

    // Strip enclosing whitespace and stray "[" "]" annotations.
    final lower = t.toLowerCase();
    for (final h in _hallucinationFragments) {
      if (lower == h || lower.contains(h)) {
        return '';
      }
    }
    // Drop entries that are just punctuation / single chars (Whisper's
    // favorite low-information output on garbled audio).
    if (t.length <= 2) return '';
    final stripped = t.replaceAll(RegExp(r'[\s\.,!\?\-…]'), '');
    if (stripped.isEmpty) return '';

    return t;
  }

  @override
  Future<void> stop() async {
    _listening = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    try {
      await _recorder.stop();
    } catch (_) { /* ignore */ }
    if (_currentRecordingPath != null) {
      _safeDelete(_currentRecordingPath!);
      _currentRecordingPath = null;
    }
    _onPartial?.call('');
    _onLevel?.call(-160);
  }

  @override
  Future<void> dispose() async {
    await stop();
    try {
      await _recorder.dispose();
    } catch (_) { /* ignore */ }
    _initialized = false;
  }
}
