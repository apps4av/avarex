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
  /// a single ATC call across two transcribe jobs (which then produce
  /// near-duplicate output because Whisper hallucinates context on each
  /// half). 600 ms is long enough to ride over the natural intra-phrase
  /// pauses in ATC speech ("Cessna [pause] one [pause] two three") without
  /// adding much perceived latency to the transcript.
  static const Duration _endOfUtteranceSilence = Duration(milliseconds: 600);

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

  /// Peak amplitude (dBFS) observed during the current utterance — surfaced
  /// in the post-transcribe status hint so we can see at a glance whether
  /// audio is actually reaching the recorder.
  double _utterancePeakDbfs = -160;

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

  /// Ring of the most recently published utterance texts (normalized for
  /// comparison). Used to drop adjacent duplicates that arise when Whisper
  /// hallucinates the same content across split chunks, or when its greedy
  /// decoder produces near-identical output on overlapping audio.
  final List<String> _recentPublished = [];
  static const int _recentPublishedWindow = 4;

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
    _utterancePeakDbfs = -160;

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
    if (dbfs > _utterancePeakDbfs) _utterancePeakDbfs = dbfs;

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
      await _finishUtteranceAndStartNext(
        transcribe: _speechSeen,
        utteranceDuration: age,
        peakDbfs: _utterancePeakDbfs,
      );
    }
  }

  /// Stops the current recorder, hands the file off to Whisper (if we ever
  /// heard speech), and immediately spins up a fresh recording so the mic
  /// gap between utterances is < 50 ms in practice.
  Future<void> _finishUtteranceAndStartNext({
    required bool transcribe,
    required Duration utteranceDuration,
    required double peakDbfs,
  }) async {
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
      // No speech detected — surface a diagnostic so we can see the
      // amplitude meter and threshold are working before the radio kicks
      // in, instead of silently dropping every chunk.
      _onStatus?.call('Silence (peak ${peakDbfs.toStringAsFixed(0)} dBFS) — '
          'threshold ${_speechThresholdDbfs.toStringAsFixed(0)} dBFS');
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
    _transcribeFile(
      wavPath,
      utteranceDuration: utteranceDuration,
      peakDbfs: peakDbfs,
    );
  }

  Future<void> _transcribeFile(
    String wavPath, {
    required Duration utteranceDuration,
    required double peakDbfs,
  }) async {
    _inflightTranscriptions++;
    _onPartial?.call('…');
    final inferenceStart = DateTime.now();
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
        //
        // We deliberately leave `vadMode` at its `auto` default. The
        // package ships a silero VAD model and applies it inside the
        // inference pass to filter silent frames — disabling it actually
        // makes the model more likely to hallucinate "thank you for
        // watching"-style output on near-silent chunks.
        threads: _whisperThreads,
        withTimestamps: false,
      );
      final inferenceMs =
          DateTime.now().difference(inferenceStart).inMilliseconds;
      final raw = result?.transcription.text ?? '';
      final cleaned = _cleanWhisperOutput(raw);
      final preview = raw.trim().isEmpty
          ? '(empty)'
          : '"${_truncate(raw.trim(), 60)}"';
      String filteredNote = '';
      if (cleaned.isEmpty && raw.trim().isNotEmpty) {
        filteredNote = ' [filtered]';
      }
      // Drop adjacent duplicates - the most common source of "the same
      // sentence keeps printing" complaints. Comparison is case- and
      // punctuation-insensitive so "Cleared to land" and "cleared to land."
      // collapse to one published row.
      String? published = cleaned;
      if (published.isNotEmpty && _isRecentDuplicate(published)) {
        filteredNote = ' [duplicate]';
        published = null;
      }
      _onStatus?.call(
        '${utteranceDuration.inMilliseconds}ms audio · '
        'peak ${peakDbfs.toStringAsFixed(0)} dBFS · '
        '${inferenceMs}ms infer · $preview$filteredNote',
      );
      if (published != null && published.isNotEmpty) {
        _onUtterance?.call(SttUtterance(DateTime.now(), published));
        _trackPublished(published);
      }
    } catch (e) {
      _onError?.call('Whisper transcription failed: $e', recoverable: true);
    } finally {
      _inflightTranscriptions--;
      // Only clear the partial indicator when the queue actually drains -
      // otherwise back-to-back utterances can race and leave a stale "..."
      // on screen, or worse, a clear before another inference finishes.
      if (_inflightTranscriptions <= 0) {
        _onPartial?.call('');
      }
      _safeDelete(wavPath);
      // whisper_ggml_plus skips its conversion step when the input already
      // ends in `.wav` (which ours does), so no side-car file is produced.
      // We still try to clean any stray copy in case behaviour changes.
      _safeDelete('$wavPath.wav');
    }
  }

  /// Case- and punctuation-insensitive normalization used for the dedup
  /// ring. Strips trailing punctuation, collapses whitespace, lowercases.
  static String _normalizeForDedup(String s) {
    final lower = s.toLowerCase();
    final stripped = lower.replaceAll(RegExp(r'[\s\.,!\?\-…]+'), ' ').trim();
    return stripped;
  }

  bool _isRecentDuplicate(String text) {
    final norm = _normalizeForDedup(text);
    if (norm.isEmpty) return false;
    return _recentPublished.contains(norm);
  }

  void _trackPublished(String text) {
    final norm = _normalizeForDedup(text);
    if (norm.isEmpty) return;
    _recentPublished.add(norm);
    while (_recentPublished.length > _recentPublishedWindow) {
      _recentPublished.removeAt(0);
    }
  }

  static String _truncate(String s, int n) {
    if (s.length <= n) return s;
    return '${s.substring(0, n - 1)}…';
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

    t = _collapseTailRepetition(t);
    return t;
  }

  /// Collapse Whisper's greedy-decoder repetition loops within a single
  /// transcription. Whisper-tiny.en on near-silent / padded audio is
  /// notorious for outputs like "Cleared to land. Cleared to land. Cleared
  /// to land." We detect a 2-to-6-word phrase repeated 3+ times at the
  /// tail and drop all but the first occurrence.
  static String _collapseTailRepetition(String text) {
    final words = text.split(RegExp(r'\s+'));
    if (words.length < 6) return text;
    for (int n = 6; n >= 2; n--) {
      if (words.length < n * 3) continue;
      String span(int start) =>
          words.sublist(start, start + n).join(' ').toLowerCase();
      final lastStart = words.length - n;
      final tail1 = span(lastStart);
      final tail2 = span(lastStart - n);
      final tail3 = span(lastStart - 2 * n);
      if (tail1 == tail2 && tail2 == tail3) {
        // Keep the prefix plus a single copy of the looped phrase. The
        // first occurrence ends at index (lastStart - n - 1), so we take
        // sublist(0, lastStart - n).
        return words.sublist(0, lastStart - n).join(' ');
      }
    }
    return text;
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
    _recentPublished.clear();
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
