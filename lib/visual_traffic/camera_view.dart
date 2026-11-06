import 'dart:async';

import 'package:avaremp/utils/app_log.dart';
import 'package:avaremp/link/link_service.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/visual_traffic/adsb_matcher.dart';
import 'package:avaremp/visual_traffic/adsb_source.dart';
import 'package:avaremp/visual_traffic/analyzer_worker.dart';
import 'package:avaremp/visual_traffic/attitude_filter.dart';
import 'package:avaremp/visual_traffic/decision_board.dart';
import 'package:avaremp/visual_traffic/decisions.dart';
import 'package:avaremp/visual_traffic/detection_models.dart';
import 'package:avaremp/visual_traffic/detection_painter.dart';
import 'package:avaremp/visual_traffic/frame_analyzer.dart';
import 'package:avaremp/visual_traffic/preview_encoder.dart';
import 'package:avaremp/visual_traffic/why_panel.dart';
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
  StreamSubscription<GyroscopeEvent>? _gyroSub;
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
  double _yaw = 0;
  bool _showWhy = false;

  bool _fuseGyro = true;
  bool _fuseAdsb = true;

  // Which way is down and where the aircraft is heading, from the gyroscope,
  // accelerometer, picture horizon, and GPS together.
  AttitudeFilter _filter = AttitudeFilter();
  int _deviceDegrees = 0;

  // The boxes as shown and shared: the analyzer's boxes with ADS-B's
  // confirmations applied.
  List<DetectionBox> _boxes = const [];

  int _lastSubmitMs = 0;
  int _lastPreviewMs = 0;
  final TrafficAlert _alert = TrafficAlert();
  final DecisionBoard _board = DecisionBoard();
  AdsbPicture _adsbPicture = AdsbPicture.empty;

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
    _yaw = settings.getVisualTrafficYaw();
    _fuseGyro = settings.getVisualTrafficFuseGyro();
    _fuseAdsb = settings.getVisualTrafficFuseAdsb();
    _filter = _newFilter();
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
    _gyroSub = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(_onGyro, onError: (Object _) {
      // No gyroscope: the picture alone follows the scene.
    });
    _begin();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hudTimer?.cancel();
    _accelSub?.cancel();
    _gyroSub?.cancel();
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

  /// Without the gyroscope the accelerometer has to do more of the work, so
  /// it is allowed to pull faster.
  AttitudeFilter _newFilter() =>
      AttitudeFilter(accelTimeConstant: _fuseGyro ? 60 : 1);

  void _onAccel(AccelerometerEvent event) {
    final Vec3 a = deviceToCamera(_deviceDegrees, event.x, event.y, event.z);
    _filter.onAccel(a, DateTime.now().millisecondsSinceEpoch);
  }

  void _onGyro(GyroscopeEvent event) {
    if (!_fuseGyro) {
      return;
    }
    final Vec3 w = deviceToCamera(_deviceDegrees, event.x, event.y, event.z);
    _filter.onGyro(w, DateTime.now().millisecondsSinceEpoch);
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
    final int device = _degreesOf(controller);
    final int turns = (((sensor - device) % 360) + 360) % 360 ~/ 90;
    return (turns + _rotation) % 4;
  }

  int _degreesOf(CameraController controller) {
    final int degrees = switch (controller.value.deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    _deviceDegrees = degrees;
    return degrees;
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
    _degreesOf(controller);
    // With a manual picture rotation the sensor axes no longer line up with
    // the picture, so the sensors are left out.
    final bool sensorsLineUp = _rotation == 0;
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
      gravity: sensorsLineUp ? _filter.gravity : null,
      motion: sensorsLineUp && _fuseGyro ? _filter.rotation : null,
      cues: _fuseAdsb ? _adsbPicture.cues : const [],
      wantPreview: wantPreview,
    );
    if (sent) {
      // The analyzer has this turn now. Start counting the next one.
      _filter.clearRotation();
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

    // The horizon in the picture is the most trustworthy, so it corrects the
    // sensors' idea of down.
    final HorizonReport horizon = result.horizonReport;
    final double? tilt = horizon.tiltDegrees;
    final double? pitch = horizon.pitchDegrees;
    if (horizon.source == HorizonSource.picture && tilt != null && pitch != null) {
      _filter.onPicture(tilt, pitch);
    }

    // GPS gives the heading once a second. The gyroscope carries it between.
    final AdsbSnapshot snapshot = AdsbSource.read();
    final OwnshipFix? gps = snapshot.ownship;
    OwnshipFix? ownship = gps;
    double? heading = gps?.trackDegrees;
    if (gps != null) {
      _filter.onGps(
        gps.trackDegrees,
        Object.hash(gps.latitude, gps.longitude, gps.trackDegrees),
      );
      if (_fuseGyro && gps.trackDegrees != null) {
        heading = _filter.heading ?? gps.trackDegrees;
        ownship = OwnshipFix(
          latitude: gps.latitude,
          longitude: gps.longitude,
          altitudeFt: gps.altitudeFt,
          speedKnots: gps.speedKnots,
          trackDegrees: heading,
        );
      }
    }

    _adsbPicture = AdsbMatcher(
      promoteDegrees: _fuseAdsb ? 3.5 : -1,
      maxCues: _fuseAdsb ? 3 : 0,
    ).match(
      ownship: ownship,
      traffic: snapshot.traffic,
      boxes: result.frame.boxes,
      fovH: result.frame.fovH,
      fovV: result.frame.fovV,
      pictureWidth: result.pictureWidth,
      pictureHeight: result.pictureHeight,
      horizon: horizon,
      yawOffsetDegrees: _yaw,
    );

    // A steady mover that lines up with an ADS-B aircraft is shown red.
    final List<DetectionBox> boxes = [
      for (final DetectionBox b in result.frame.boxes)
        _adsbPicture.promoted.containsKey(b.id)
            ? DetectionBox(
                id: b.id,
                x: b.x,
                y: b.y,
                w: b.w,
                h: b.h,
                confidence: b.confidence,
                tier: DetectionTier.airplane,
              )
            : b,
    ];
    _boxes = boxes;
    final DetectionFrame shown = DetectionFrame(
      seq: result.frame.seq,
      timestampMs: result.frame.timestampMs,
      fovH: result.frame.fovH,
      fovV: result.frame.fovV,
      boxes: boxes,
      horizonLeft: result.frame.horizonLeft,
      horizonRight: result.frame.horizonRight,
    );

    if (_share) {
      LinkService().sendDetections(shown);
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
    if (_alertOn && _alert.update(boxes)) {
      TrafficAlert.sound();
    }
    _board.update(
      result: result,
      adsbPicture: _adsbPicture,
      ownship: ownship,
      heading: heading,
      gpsTrack: gps?.trackDegrees,
    );
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
                    Text("Camera aim: ${_yaw.round().abs()}° ${_yaw >= 0 ? "right" : "left"} of the nose"),
                    const Text(
                      "Only used to place ADS-B aircraft in the picture. Leave at 0 when the phone looks straight ahead. AvareX assumes the nose points along the GPS track.",
                      style: TextStyle(fontSize: 12),
                    ),
                    Slider(
                      value: _yaw,
                      min: -60,
                      max: 60,
                      divisions: 120,
                      label: "${_yaw.round()}°",
                      onChanged: (double v) {
                        both(() => _yaw = v);
                      },
                      onChangeEnd: (double v) {
                        settings.setVisualTrafficYaw(v);
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
                      title: const Text("Use gyroscope"),
                      subtitle: const Text(
                        "Follow the scene through turns and carry the heading between GPS fixes. It is only used after it has been seen to agree with the picture.",
                      ),
                      value: _fuseGyro,
                      onChanged: (bool v) {
                        both(() {
                          _fuseGyro = v;
                          _filter = _newFilter();
                        });
                        settings.setVisualTrafficFuseGyro(v);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Use ADS-B to confirm"),
                      subtitle: const Text(
                        "Turn a yellow box red when it lines up closely with an ADS-B aircraft, and make the model look where ADS-B says an aircraft is.",
                      ),
                      value: _fuseAdsb,
                      onChanged: (bool v) {
                        both(() => _fuseAdsb = v);
                        settings.setVisualTrafficFuseAdsb(v);
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
            icon: Icon(_showWhy ? Icons.fact_check : Icons.fact_check_outlined),
            tooltip: "Why: how targets are chosen",
            onPressed: () => setState(() => _showWhy = !_showWhy),
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
                      boxes: _boxes,
                      fovH: frame?.fovH ?? _fov,
                      fovV: frame?.fovV ?? _fov * 0.56,
                      horizonLeft: frame?.horizonLeft,
                      horizonRight: frame?.horizonRight,
                      showHorizon: _showHorizon,
                      labels: _adsbPicture.labels,
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
        if (_showWhy)
          Positioned(
            left: 8,
            right: 8,
            bottom: 34,
            child: WhyPanel(
              board: _board,
              onClose: () => setState(() => _showWhy = false),
            ),
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
    final int red = _boxes.where((DetectionBox b) => b.tier == DetectionTier.airplane).length;
    final int yellow = _boxes.length - red;
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
