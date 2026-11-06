import 'dart:async';

import 'package:avaremp/utils/app_log.dart';
import 'package:avaremp/link/link_service.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/visual_traffic/analyzer_worker.dart';
import 'package:avaremp/visual_traffic/detection_models.dart';
import 'package:avaremp/visual_traffic/detection_painter.dart';
import 'package:avaremp/visual_traffic/frame_analyzer.dart';
import 'package:avaremp/visual_traffic/preview_encoder.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// The phone with the camera. Looks through the windshield, finds other
/// aircraft, draws boxes on them, and tells viewers on Link.
class VisualTrafficCameraView extends StatefulWidget {
  const VisualTrafficCameraView({super.key});

  @override
  State<VisualTrafficCameraView> createState() =>
      _VisualTrafficCameraViewState();
}

class _VisualTrafficCameraViewState extends State<VisualTrafficCameraView>
    with WidgetsBindingObserver {
  static const String _modelAsset = 'assets/models/yolox_nano.tflite';

  // Frames are analyzed about this often. A phone has plenty of room at this
  // rate and stays cooler than at the camera's full 30 frames a second.
  static const int _minFrameGapMs = 90;
  static const int _minPreviewGapMs = 250;

  CameraController? _controller;
  AnalyzerWorker? _worker;
  StreamSubscription<WorkerOutput>? _outputSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;
  Timer? _hudTimer;

  String? _error;
  bool _starting = false;
  bool _modelLoadFailed = false;

  // Settings, loaded from and saved to the app settings.
  double _fov = 65;
  double _sensitivity = 1;
  int _rotation = 0;
  bool _alertOn = true;
  bool _share = true;
  bool _showHorizon = false;

  // Latest accelerometer reading, smoothed.
  double _ax = 0, _ay = 0, _az = 0;
  bool _haveAccel = false;

  int _lastSubmitMs = 0;
  int _lastPreviewMs = 0;
  final TrafficAlert _alert = TrafficAlert();

  AnalysisResult? _result;
  double _avgMs = 0;
  int _framesThisSecond = 0;
  int _fps = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final settings = Storage().settings;
    _fov = settings.getVisualTrafficFov();
    _sensitivity = settings.getVisualTrafficSensitivity();
    _rotation = settings.getVisualTrafficRotation() % 4;
    _alertOn = settings.getVisualTrafficAlert();
    _share = settings.getVisualTrafficShare();
    _hudTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _fps = _framesThisSecond;
        _framesThisSecond = 0;
      });
    });
    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen(_onAccel, onError: (Object _) {
      // No accelerometer: the horizon comes from the picture alone.
    });
    _begin();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hudTimer?.cancel();
    _accelSub?.cancel();
    _outputSub?.cancel();
    final AnalyzerWorker? worker = _worker;
    if (worker != null) {
      worker.stop();
    }
    final CameraController? controller = _controller;
    _controller = null;
    if (controller != null) {
      _shutDownCamera(controller);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The camera must be released when the app is not in front, and taken
    // again when it comes back.
    if (state == AppLifecycleState.inactive) {
      final CameraController? controller = _controller;
      if (controller != null) {
        _controller = null;
        _shutDownCamera(controller);
        if (mounted) {
          setState(() {});
        }
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null && _worker != null && _error == null) {
        _openCamera();
      }
    }
  }

  Future<void> _shutDownCamera(CameraController controller) async {
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // already stopped
    }
    try {
      await controller.dispose();
    } catch (_) {
      // already disposed
    }
  }

  void _onAccel(AccelerometerEvent event) {
    // Smoothing keeps vibration out of the horizon fallback.
    const double keep = 0.85;
    if (!_haveAccel) {
      _ax = event.x;
      _ay = event.y;
      _az = event.z;
      _haveAccel = true;
      return;
    }
    _ax = _ax * keep + event.x * (1 - keep);
    _ay = _ay * keep + event.y * (1 - keep);
    _az = _az * keep + event.z * (1 - keep);
  }

  Future<void> _begin() async {
    if (_starting) {
      return;
    }
    _starting = true;
    try {
      Uint8List? modelBytes;
      try {
        final ByteData data = await rootBundle.load(_modelAsset);
        modelBytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } catch (e) {
        AppLog.logMessage("Visual Traffic model missing: $e");
        _modelLoadFailed = true;
      }
      final AnalyzerWorker worker = await AnalyzerWorker.start(
        settings: AnalyzerSettings(fovH: _fov, sensitivity: _sensitivity),
        modelBytes: modelBytes,
      );
      if (!mounted) {
        worker.stop();
        return;
      }
      _worker = worker;
      _outputSub = worker.outputs.listen(_onOutput);
      await _openCamera();
    } catch (e) {
      AppLog.logMessage("Visual Traffic start error: $e");
      if (mounted) {
        setState(() => _error = "Could not start the analyzer: $e");
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _openCamera() async {
    try {
      final List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('none', 'This device has no camera.');
      }
      final CameraDescription chosen = cameras.firstWhere(
        (CameraDescription c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final CameraController controller = CameraController(
        chosen,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      _alert.reset();
      await controller.startImageStream(_onImage);
      if (mounted) {
        setState(() => _error = null);
      }
    } on CameraException catch (e) {
      AppLog.logMessage("Visual Traffic camera error: ${e.code} ${e.description}");
      if (mounted) {
        setState(() {
          _error = e.code.toLowerCase().contains('access')
              ? "Camera permission was denied. Allow camera access for AvareX in Settings, then come back."
              : "Camera problem: ${e.description ?? e.code}";
        });
      }
    } catch (e) {
      AppLog.logMessage("Visual Traffic camera error: $e");
      if (mounted) {
        setState(() => _error = "Camera problem: $e");
      }
    }
  }

  /// Clockwise quarter turns that make a camera frame upright for the way the
  /// phone is held, plus the user's correction.
  int _quarterTurns(CameraController controller) {
    final int sensor = controller.description.sensorOrientation;
    final int device = switch (controller.value.deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    final int turns = (((sensor - device) % 360) + 360) % 360 ~/ 90;
    return (turns + _rotation) % 4;
  }

  /// Which way is down, in the camera's own axes: x to the right of the
  /// upright picture, y toward its bottom, z out through the lens.
  GravityHint? _gravity(CameraController controller) {
    if (!_haveAccel || _rotation != 0) {
      // With a manual rotation the axes below no longer line up.
      return null;
    }
    // The accelerometer reports the push of the floor, so down is the
    // opposite way.
    final double dx = -_ax, dy = -_ay, dz = -_az;
    switch (controller.value.deviceOrientation) {
      case DeviceOrientation.portraitUp:
        return GravityHint(dx, -dy, -dz);
      case DeviceOrientation.portraitDown:
        return GravityHint(-dx, dy, -dz);
      case DeviceOrientation.landscapeLeft:
        return GravityHint(-dy, -dx, -dz);
      case DeviceOrientation.landscapeRight:
        return GravityHint(dy, dx, -dz);
    }
  }

  void _onImage(CameraImage image) {
    final AnalyzerWorker? worker = _worker;
    final CameraController? controller = _controller;
    if (worker == null || controller == null || worker.busy) {
      return;
    }
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSubmitMs < _minFrameGapMs || image.planes.isEmpty) {
      return;
    }
    final Plane plane = image.planes[0];
    final bool wantPreview = _share &&
        now - _lastPreviewMs >= _minPreviewGapMs &&
        LinkService().hasWatchers;
    final bool sent = worker.submit(
      bytes: plane.bytes,
      width: image.width,
      height: image.height,
      rowStride: plane.bytesPerRow,
      quarterTurns: _quarterTurns(controller),
      timestampMs: now,
      gravity: _gravity(controller),
      wantPreview: wantPreview,
    );
    if (sent) {
      _lastSubmitMs = now;
      if (wantPreview) {
        _lastPreviewMs = now;
      }
    }
  }

  void _onOutput(WorkerOutput output) {
    final AnalysisResult result = output.result;
    _framesThisSecond++;
    _avgMs = _avgMs == 0 ? result.milliseconds : _avgMs * 0.9 + result.milliseconds * 0.1;
    if (_share) {
      LinkService().sendDetections(result.frame);
      final PreviewPicture? preview = output.preview;
      if (preview != null) {
        LinkService().sendPreview(
          seq: result.frame.seq,
          width: preview.width,
          height: preview.height,
          jpeg: preview.jpeg,
        );
      }
    }
    if (_alertOn && _alert.update(result.frame.boxes)) {
      TrafficAlert.sound();
    }
    if (mounted) {
      setState(() => _result = result);
    }
  }

  void _applyAnalyzerSettings() {
    _worker?.updateSettings(
      AnalyzerSettings(fovH: _fov, sensitivity: _sensitivity),
    );
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheet) {
            final settings = Storage().settings;
            void both(VoidCallback change) {
              setSheet(change);
              if (mounted) {
                setState(() {});
              }
            }

            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Camera field of view: ${_fov.round()}°"),
                    const Text(
                      "How wide the camera sees across the picture. Labels show how far off the nose a target is, so a wrong value gives wrong angles. Most phone main cameras are 60 to 70.",
                      style: TextStyle(fontSize: 12),
                    ),
                    Slider(
                      value: _fov,
                      min: 40,
                      max: 100,
                      divisions: 60,
                      label: "${_fov.round()}°",
                      onChanged: (double v) {
                        both(() => _fov = v);
                      },
                      onChangeEnd: (double v) {
                        settings.setVisualTrafficFov(v);
                        _applyAnalyzerSettings();
                      },
                    ),
                    Text("Sensitivity: ${_sensitivity.toStringAsFixed(2)}"),
                    const Text(
                      "Lower finds only clear targets. Higher also finds faint ones, with more false yellow boxes.",
                      style: TextStyle(fontSize: 12),
                    ),
                    Slider(
                      value: _sensitivity,
                      min: 0.5,
                      max: 1.5,
                      divisions: 20,
                      label: _sensitivity.toStringAsFixed(2),
                      onChanged: (double v) {
                        both(() => _sensitivity = v);
                      },
                      onChangeEnd: (double v) {
                        settings.setVisualTrafficSensitivity(v);
                        _applyAnalyzerSettings();
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text("Picture rotation: ${_rotation * 90}°"),
                      subtitle: const Text(
                        "If boxes do not sit on what you see, turn this until they do.",
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: () {
                          both(() => _rotation = (_rotation + 1) % 4);
                          settings.setVisualTrafficRotation(_rotation);
                        },
                        child: const Text("Rotate 90°"),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Alert on a new red box"),
                      subtitle: const Text("Beep and vibrate."),
                      value: _alertOn,
                      onChanged: (bool v) {
                        both(() => _alertOn = v);
                        settings.setVisualTrafficAlert(v);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Share with other devices"),
                      subtitle: const Text(
                        "Send boxes and a small picture over Link to a device showing this camera.",
                      ),
                      value: _share,
                      onChanged: (bool v) {
                        both(() => _share = v);
                        settings.setVisualTrafficShare(v);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Show horizon line"),
                      subtitle: const Text("For checking the sky and ground split."),
                      value: _showHorizon,
                      onChanged: (bool v) {
                        both(() => _showHorizon = v);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final AnalysisResult? result = _result;
    final int watchers = LinkService().hasWatchers ? 1 : 0;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Visual Traffic Camera"),
        actions: [
          if (_share && watchers > 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.cast_connected),
            ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: "Settings",
            onPressed: _openSettings,
          ),
        ],
      ),
      body: _body(result),
    );
  }

  Widget _body(AnalysisResult? result) {
    final String? error = _error;
    if (error != null) {
      return _message(error, icon: Icons.videocam_off);
    }
    final CameraController? controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final DetectionFrame? frame = result?.frame;
    final bool landscape = controller.value.deviceOrientation == DeviceOrientation.landscapeLeft ||
        controller.value.deviceOrientation == DeviceOrientation.landscapeRight;
    final double sensorAspect = controller.value.aspectRatio;
    final double aspect = landscape ? sensorAspect : 1 / sensorAspect;
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: aspect,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(controller),
                RepaintBoundary(
                  child: CustomPaint(
                    painter: DetectionPainter(
                      boxes: frame?.boxes ?? const [],
                      fovH: frame?.fovH ?? _fov,
                      fovV: frame?.fovV ?? _fov * 0.56,
                      horizonLeft: frame?.horizonLeft,
                      horizonRight: frame?.horizonRight,
                      showHorizon: _showHorizon,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 8,
          top: 8,
          child: _hud(result),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            color: Colors.black54,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: const Text(
              "Traffic awareness aid only. It misses aircraft. Not for collision avoidance. Keep looking outside.",
              style: TextStyle(color: Colors.white, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _hud(AnalysisResult? result) {
    final DetectionFrame? frame = result?.frame;
    final int red = frame?.airplaneCount ?? 0;
    final int yellow = (frame?.boxes.length ?? 0) - red;
    final List<String> lines = [
      "$_fps fps  ${_avgMs.round()} ms",
      "red $red  yellow $yellow",
      if (result != null && !result.modelAvailable)
        "no model: yellow boxes only"
      else if (_modelLoadFailed)
        "model file missing: yellow boxes only",
      if (result != null && result.cluttered) "busy sky: yellow boxes held back",
      if (result != null && result.horizon == null) "no horizon found",
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        lines.join("\n"),
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  Widget _message(String text, {required IconData icon}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.white70),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
