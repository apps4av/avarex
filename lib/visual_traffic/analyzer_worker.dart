import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:avaremp/utils/app_log.dart';
import 'package:avaremp/visual_traffic/aircraft_detector.dart';
import 'package:avaremp/visual_traffic/frame_analyzer.dart';
import 'package:avaremp/visual_traffic/luma_frame.dart';
import 'package:avaremp/visual_traffic/preview_encoder.dart';

/// One analyzed frame coming back from the worker.
class WorkerOutput {
  const WorkerOutput(this.result, this.preview);

  final AnalysisResult result;

  /// Present when the frame was submitted with `wantPreview`.
  final PreviewPicture? preview;
}

/// Runs [FrameAnalyzer] and the model on a background isolate, so the camera
/// preview and the rest of the app stay smooth.
///
/// The camera hands over one brightness plane per frame. [submit] copies it
/// across without a second copy, and the worker answers with boxes. Submit the
/// next frame only when [busy] is false, so frames never pile up.
class AnalyzerWorker {
  AnalyzerWorker._(
      this._isolate, this._commands, this._receive, this.modelAvailable);

  final Isolate _isolate;
  final SendPort _commands;
  final ReceivePort _receive;

  /// False when the model could not be loaded, so only motion-based yellow
  /// boxes are possible.
  final bool modelAvailable;

  final StreamController<WorkerOutput> _outputs =
      StreamController<WorkerOutput>.broadcast();
  bool _busy = false;
  bool _stopped = false;

  Stream<WorkerOutput> get outputs => _outputs.stream;
  bool get busy => _busy;

  /// Starts the isolate. [modelBytes] is the `.tflite` file, or null to run
  /// without a model.
  static Future<AnalyzerWorker> start({
    required AnalyzerSettings settings,
    Uint8List? modelBytes,
  }) async {
    final ReceivePort receive = ReceivePort();
    final Completer<_Ready> ready = Completer<_Ready>();
    AnalyzerWorker? worker;
    receive.listen((Object? message) {
      if (message is _Ready) {
        if (!ready.isCompleted) {
          ready.complete(message);
        }
      } else if (message is _Output) {
        worker?._onOutput(message);
      } else if (message is _Failure) {
        AppLog.logMessage("Visual Traffic analyzer error: ${message.text}");
        worker?._busy = false;
      } else if (message is List) {
        // Uncaught isolate error: [message, stack trace].
        AppLog.logMessage("Visual Traffic analyzer crashed: $message");
        worker?._busy = false;
        if (!ready.isCompleted) {
          ready.completeError(StateError("analyzer isolate failed to start"));
        }
      }
    });
    final Isolate isolate = await Isolate.spawn(
      _entry,
      _Start(receive.sendPort, modelBytes, settings),
      onError: receive.sendPort,
    );
    final _Ready answer;
    try {
      answer = await ready.future;
    } catch (_) {
      receive.close();
      isolate.kill(priority: Isolate.immediate);
      rethrow;
    }
    worker = AnalyzerWorker._(
        isolate, answer.commands, receive, answer.modelAvailable);
    return worker;
  }

  /// Sends the brightness plane of one camera frame for analysis. Does
  /// nothing while a frame is still being worked on.
  ///
  /// [bytes] is copied. [quarterTurns] is how many clockwise quarter turns
  /// make the frame upright.
  bool submit({
    required Uint8List bytes,
    required int width,
    required int height,
    required int rowStride,
    required int quarterTurns,
    required int timestampMs,
    GravityHint? gravity,
    bool wantPreview = false,
  }) {
    if (_busy || _stopped) {
      return false;
    }
    _busy = true;
    _commands.send(_FrameCommand(
      TransferableTypedData.fromList([bytes]),
      width,
      height,
      rowStride,
      quarterTurns,
      timestampMs,
      gravity,
      wantPreview,
    ));
    return true;
  }

  void updateSettings(AnalyzerSettings settings) {
    if (!_stopped) {
      _commands.send(settings);
    }
  }

  Future<void> stop() async {
    if (_stopped) {
      return;
    }
    _stopped = true;
    _commands.send(const _Stop());
    // Give the isolate a moment to close the model, then make sure.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _isolate.kill(priority: Isolate.beforeNextEvent);
    _receive.close();
    await _outputs.close();
  }

  void _onOutput(_Output output) {
    _busy = false;
    if (!_stopped) {
      _outputs.add(WorkerOutput(output.result, output.preview));
    }
  }
}

// Messages. Plain classes, which isolates copy as they are.

class _Start {
  const _Start(this.reply, this.modelBytes, this.settings);
  final SendPort reply;
  final Uint8List? modelBytes;
  final AnalyzerSettings settings;
}

class _Ready {
  const _Ready(this.commands, this.modelAvailable);
  final SendPort commands;
  final bool modelAvailable;
}

class _FrameCommand {
  const _FrameCommand(this.bytes, this.width, this.height, this.rowStride,
      this.quarterTurns, this.timestampMs, this.gravity, this.wantPreview);
  final TransferableTypedData bytes;
  final int width;
  final int height;
  final int rowStride;
  final int quarterTurns;
  final int timestampMs;
  final GravityHint? gravity;
  final bool wantPreview;
}

class _Stop {
  const _Stop();
}

class _Output {
  const _Output(this.result, this.preview);
  final AnalysisResult result;
  final PreviewPicture? preview;
}

class _Failure {
  const _Failure(this.text);
  final String text;
}

void _entry(_Start start) {
  final ReceivePort commands = ReceivePort();
  AircraftConfirmer? confirmer;
  final Uint8List? modelBytes = start.modelBytes;
  if (modelBytes != null) {
    confirmer = TfliteAircraftConfirmer.create(modelBytes);
  }
  final FrameAnalyzer analyzer =
      FrameAnalyzer(confirmer: confirmer, settings: start.settings);
  start.reply.send(_Ready(commands.sendPort, confirmer != null));
  commands.listen((Object? message) {
    if (message is _FrameCommand) {
      try {
        final Uint8List bytes = message.bytes.materialize().asUint8List();
        final LumaFrame frame = LumaFrame(
          bytes: bytes,
          sourceWidth: message.width,
          sourceHeight: message.height,
          rowStride: message.rowStride,
          quarterTurns: message.quarterTurns,
        );
        final AnalysisResult result = analyzer.process(
          frame,
          timestampMs: message.timestampMs,
          gravity: message.gravity,
        );
        final PreviewPicture? preview =
            message.wantPreview ? PreviewEncoder.encode(frame) : null;
        start.reply.send(_Output(result, preview));
      } catch (e, st) {
        start.reply.send(_Failure("$e\n$st"));
      }
    } else if (message is AnalyzerSettings) {
      analyzer.updateSettings(message);
    } else if (message is _Stop) {
      analyzer.dispose();
      commands.close();
    }
  });
}
