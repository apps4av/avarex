import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

/// One downloadable Whisper voice pack option exposed on the Downloads screen.
@immutable
class WhisperVoicePackVariant {
  /// Underlying `whisper_ggml_plus` model.
  final WhisperModel model;

  /// Short display name shown in the UI (e.g. "Compact (English)").
  final String displayName;

  /// Subtitle / one-line description.
  final String description;

  /// Approximate on-disk size in MB, for the "~150 MB" hint shown in the row.
  final int approxSizeMb;

  const WhisperVoicePackVariant({
    required this.model,
    required this.displayName,
    required this.description,
    required this.approxSizeMb,
  });
}

/// All voice packs we surface in the UI. We intentionally don't expose the
/// huge models (small / medium / large) — they're too slow for real-time use
/// on a phone in the cockpit. The first entry is the "recommended" default
/// and is what `_chooseWhisperModel` falls back to when both are installed.
const List<WhisperVoicePackVariant> kWhisperVoicePackVariants = [
  WhisperVoicePackVariant(
    model: WhisperModel.tinyEn,
    displayName: 'Compact (English)',
    description: 'Recommended. Fastest, smallest — keeps the transcript real-time.',
    approxSizeMb: 75,
  ),
  WhisperVoicePackVariant(
    model: WhisperModel.baseEn,
    displayName: 'Standard (English)',
    description: 'Higher accuracy on ATC accents but ~3× slower per utterance.',
    approxSizeMb: 142,
  ),
];

/// Possible states a single voice pack can be in. The Transcribe screen
/// drives downloads/deletes with direct actions (tap a row to start, tap
/// an in-flight download to cancel, tap an installed row to confirm
/// delete), so there's no separate "queued" state.
enum WhisperModelState {
  /// Not on disk.
  absentIdle,

  /// On disk and ready to use.
  presentIdle,

  /// Download in progress.
  downloading,

  /// Deletion in progress.
  deleting,
}

/// Singleton that owns the lifecycle of every downloadable Whisper voice
/// pack file (`ggml-${modelName}.bin`). It deliberately writes to the same
/// directory that `whisper_ggml_plus`'s [WhisperController.getPath] reads, so
/// that the controller picks up our files without any extra plumbing.
class WhisperModelManager {
  WhisperModelManager._internal();
  static final WhisperModelManager _instance = WhisperModelManager._internal();
  factory WhisperModelManager() => _instance;

  /// Overrides for the per-model download URL. The default URL is the one
  /// embedded in `whisper_ggml_plus`'s [WhisperModel.modelUri] (HuggingFace's
  /// `ggerganov/whisper.cpp` mirror), which is the stock OpenAI model.
  ///
  /// When you publish an aviation-fine-tuned `ggml-tiny.en.bin` (see
  /// `tools/whisper-atc/`), add its URL here. The Compact tile in the
  /// Transcribe screen's AI Voice Pack section will then pull *your* file
  /// instead of the stock one, with the existing progress / atomic-rename /
  /// cancel UX intact.
  ///
  /// Bump the URL (`...-v2`, `...-v3`, ...) every time you re-train and ask
  /// users to delete + re-download from the voice-pack tile to upgrade.
  static const Map<WhisperModel, String> _customDownloadUrls = {
     WhisperModel.tinyEn:
       'https://www.apps4av.org/share/ggml-tiny.en.bin',
  };

  /// Resolves the URL that [download] should fetch for [model]: the entry
  /// from [_customDownloadUrls] if one exists, otherwise the package default.
  Uri _downloadUriFor(WhisperModel model) {
    final override = _customDownloadUrls[model];
    if (override != null) return Uri.parse(override);
    return model.modelUri;
  }

  /// One [_PackState] per variant in [kWhisperVoicePackVariants].
  final Map<WhisperModel, _PackState> _states = {
    for (final v in kWhisperVoicePackVariants)
      v.model: _PackState(),
  };

  /// Fires whenever any pack's state, progress, or installed-ness changes.
  /// Listeners typically re-read the public getters below.
  final ChangeNotifier changes = _PublicNotifier();
  void _notifyChanges() => (changes as _PublicNotifier).notify();

  String? _modelDir;

  /// Computes (and caches) the directory that `whisper_ggml_plus` uses for
  /// model storage. Must match [WhisperController.getModelDir] exactly so
  /// the controller resolves the file we wrote here.
  Future<String> _getModelDir() async {
    if (_modelDir != null) return _modelDir!;
    final Directory libraryDirectory = Platform.isIOS || Platform.isMacOS
        ? await getLibraryDirectory()
        : await getApplicationSupportDirectory();
    _modelDir = libraryDirectory.path;
    return _modelDir!;
  }

  /// Absolute path of the model file on disk (whether it exists or not).
  Future<String> modelFilePath(WhisperModel model) async {
    final dir = await _getModelDir();
    return '$dir/ggml-${model.modelName}.bin';
  }

  /// Whether a usable model file is present on disk.
  Future<bool> isInstalled(WhisperModel model) async {
    final p = await modelFilePath(model);
    final f = File(p);
    if (!await f.exists()) return false;
    // Sanity check: model files are tens of MB. Anything smaller is almost
    // certainly a partial / corrupted download from a previous run.
    final size = await f.length();
    return size > 1024 * 1024; // >1 MB
  }

  /// Synchronous best-effort flag used by the UI. Updated by [_refreshInstalled].
  bool isInstalledSync(WhisperModel model) => _states[model]?.installed ?? false;

  int progressPercent(WhisperModel model) =>
      _states[model]?.progressPercent ?? 0;

  WhisperModelState stateOf(WhisperModel model) =>
      _states[model]?.state ?? WhisperModelState.absentIdle;

  /// Should be called once at app start so [isInstalledSync] reflects reality.
  Future<void> refreshAll() async {
    for (final v in kWhisperVoicePackVariants) {
      await _refreshInstalled(v.model);
    }
    _notifyChanges();
  }

  Future<void> _refreshInstalled(WhisperModel model) async {
    final present = await isInstalled(model);
    final s = _states[model]!;
    s.installed = present;
    if (s.state == WhisperModelState.downloading ||
        s.state == WhisperModelState.deleting) {
      // Don't clobber an in-flight operation's state.
      return;
    }
    s.state = present
        ? WhisperModelState.presentIdle
        : WhisperModelState.absentIdle;
  }

  /// Number of variants currently downloading or deleting.
  int activeOperationCount() {
    int n = 0;
    for (final s in _states.values) {
      if (s.state == WhisperModelState.downloading ||
          s.state == WhisperModelState.deleting) {
        n++;
      }
    }
    return n;
  }

  /// Streamed download with progress + cancel support. Writes to a
  /// `.partial` sidecar first and atomically renames on success so a
  /// crashed/killed app can never leave a half-baked model file in place.
  Future<void> download(WhisperModel model) async {
    final s = _states[model]!;
    if (s.state == WhisperModelState.downloading) return;
    s.state = WhisperModelState.downloading;
    s.progressPercent = 0;
    s.cancelRequested = false;
    _notifyChanges();

    final path = await modelFilePath(model);
    final partialPath = '$path.partial';
    final partialFile = File(partialPath);

    IOSink? sink;
    http.StreamedResponse? response;
    try {
      // Ensure the destination directory exists (especially the iOS Library
      // dir; usually fine on Android too).
      await Directory(await _getModelDir()).create(recursive: true);

      final client = http.Client();
      final request = http.Request('GET', _downloadUriFor(model));
      response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final total = response.contentLength ?? 0;
      sink = partialFile.openWrite();
      int downloaded = 0;
      int lastReportedPct = 0;

      await for (final chunk in response.stream) {
        if (s.cancelRequested) {
          throw _CancelledException();
        }
        sink.add(chunk);
        downloaded += chunk.length;
        if (total > 0) {
          final pct = ((downloaded / total) * 100).clamp(0, 100).toInt();
          if (pct - lastReportedPct >= 1) {
            s.progressPercent = pct;
            lastReportedPct = pct;
            _notifyChanges();
          }
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;
      client.close();

      // Atomic rename from `.partial` → final path.
      await partialFile.rename(path);

      s.progressPercent = 100;
      s.installed = true;
      s.state = WhisperModelState.presentIdle;
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) { /* ignore */ }
      try {
        if (await partialFile.exists()) {
          await partialFile.delete();
        }
      } catch (_) { /* ignore */ }
      s.progressPercent = 0;
      s.installed = await isInstalled(model);
      s.state = s.installed
          ? WhisperModelState.presentIdle
          : WhisperModelState.absentIdle;
    } finally {
      s.cancelRequested = false;
      _notifyChanges();
    }
  }

  /// Request cancellation of an in-flight download. The download loop will
  /// notice and clean up its sidecar file.
  void cancelDownload(WhisperModel model) {
    final s = _states[model]!;
    if (s.state == WhisperModelState.downloading) {
      s.cancelRequested = true;
      _notifyChanges();
    }
  }

  /// Sideload a `.bin` file the user already has on disk (e.g. an
  /// aviation-fine-tuned model produced by `tools/whisper-atc/`) into the
  /// slot for [model]. The source is copied to `<model dir>/ggml-${model.modelName}.bin`
  /// via a `.partial` sidecar + atomic rename, so a failure can never
  /// corrupt the existing installed file.
  ///
  /// Returns the destination path on success. Throws on any I/O error.
  Future<String> importFromFile(WhisperModel model, String sourcePath) async {
    final s = _states[model]!;
    final src = File(sourcePath);

    if (!await src.exists()) {
      throw Exception('Source file does not exist: $sourcePath');
    }
    final srcSize = await src.length();
    if (srcSize < 1024 * 1024) {
      // Whisper model files are tens of MB. Anything smaller is almost
      // certainly not a valid ggml file - bail before clobbering the slot.
      throw Exception(
        'File is too small (${srcSize ~/ 1024} KB) to be a Whisper model.',
      );
    }

    // Reuse the downloading state for UI feedback; conceptually identical
    // from the user's perspective (a row going from "absent" to "installing"
    // to "installed"), and lets [VoicePackSection] keep its existing
    // state-machine without a new branch.
    s.state = WhisperModelState.downloading;
    s.progressPercent = 0;
    _notifyChanges();

    final destPath = await modelFilePath(model);
    final partialPath = '$destPath.partial';
    final partialFile = File(partialPath);

    try {
      await Directory(await _getModelDir()).create(recursive: true);
      if (await partialFile.exists()) {
        await partialFile.delete();
      }

      // Streamed copy so a multi-hundred-MB import doesn't block the UI
      // thread and so we can publish progress as we go.
      final readStream = src.openRead();
      final sink = partialFile.openWrite();
      int copied = 0;
      int lastReportedPct = 0;
      await for (final chunk in readStream) {
        sink.add(chunk);
        copied += chunk.length;
        final pct = ((copied / srcSize) * 100).clamp(0, 100).toInt();
        if (pct - lastReportedPct >= 1) {
          s.progressPercent = pct;
          lastReportedPct = pct;
          _notifyChanges();
        }
      }
      await sink.flush();
      await sink.close();

      // Replace any existing file atomically.
      final existing = File(destPath);
      if (await existing.exists()) {
        await existing.delete();
      }
      await partialFile.rename(destPath);

      s.progressPercent = 100;
      s.installed = true;
      s.state = WhisperModelState.presentIdle;
      return destPath;
    } catch (e) {
      try {
        if (await partialFile.exists()) {
          await partialFile.delete();
        }
      } catch (_) { /* ignore */ }
      s.progressPercent = 0;
      s.installed = await isInstalled(model);
      s.state = s.installed
          ? WhisperModelState.presentIdle
          : WhisperModelState.absentIdle;
      rethrow;
    } finally {
      _notifyChanges();
    }
  }

  /// Delete the on-disk model file (and any sidecar `.partial`).
  Future<void> delete(WhisperModel model) async {
    final s = _states[model]!;
    s.state = WhisperModelState.deleting;
    s.progressPercent = 0;
    _notifyChanges();
    try {
      final path = await modelFilePath(model);
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
      final partial = File('$path.partial');
      if (await partial.exists()) {
        await partial.delete();
      }
      s.installed = false;
      s.state = WhisperModelState.absentIdle;
    } catch (_) {
      s.installed = await isInstalled(model);
      s.state = s.installed
          ? WhisperModelState.presentIdle
          : WhisperModelState.absentIdle;
    } finally {
      _notifyChanges();
    }
  }

  /// Is at least one voice pack installed?
  bool isAnyInstalled() {
    for (final s in _states.values) {
      if (s.installed) return true;
    }
    return false;
  }

  /// Returns the [WhisperVoicePackVariant] description for a given model, or
  /// null if the model isn't one of the exposed variants.
  WhisperVoicePackVariant? variantFor(WhisperModel model) {
    for (final v in kWhisperVoicePackVariants) {
      if (v.model == model) return v;
    }
    return null;
  }
}

class _PackState {
  WhisperModelState state = WhisperModelState.absentIdle;
  int progressPercent = 0;
  bool installed = false;
  bool cancelRequested = false;
}

class _CancelledException implements Exception {}

/// [ChangeNotifier] subclass that re-exposes [notifyListeners] as a public
/// `notify()` method, so [WhisperModelManager] (which isn't itself a
/// [ChangeNotifier]) can publish updates without polluting its API surface.
class _PublicNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
