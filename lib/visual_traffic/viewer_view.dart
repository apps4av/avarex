import 'dart:async';
import 'dart:typed_data';

import 'package:avaremp/link/link_service.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/visual_traffic/detection_models.dart';
import 'package:avaremp/visual_traffic/detection_painter.dart';
import 'package:flutter/material.dart';

/// Shows another phone's camera picture with the boxes it found, and sounds
/// an alert when that phone finds a new airplane.
class VisualTrafficViewerView extends StatefulWidget {
  const VisualTrafficViewerView({super.key});

  @override
  State<VisualTrafficViewerView> createState() =>
      _VisualTrafficViewerViewState();
}

class _VisualTrafficViewerViewState extends State<VisualTrafficViewerView> {
  // Boxes older than this are shown faintly, and the picture is called lost.
  static const Duration _stale = Duration(seconds: 2);

  final LinkService _link = LinkService();
  final TrafficAlert _alert = TrafficAlert();
  Timer? _clock;
  String? _selected;
  int _lastAlertSeq = -1;
  bool _alertOn = true;
  bool _showHorizon = false;

  @override
  void initState() {
    super.initState();
    _alertOn = Storage().settings.getVisualTrafficAlert();
    _selected = _link.watchTarget;
    _link.visualChange.addListener(_onVisual);
    // Ages the data on screen even when nothing new arrives.
    _clock = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _link.visualChange.removeListener(_onVisual);
    _link.watch(null);
    super.dispose();
  }

  void _onVisual() {
    if (!mounted) {
      return;
    }
    String? selected = _selected;
    if (selected == null) {
      final List<VisualSource> sources = _link.visualSources;
      if (sources.length == 1) {
        // The only camera phone around: just show it.
        selected = sources.first.id;
        _choose(selected);
      }
    }
    if (selected != null) {
      final VisualSource? source = _link.visualSource(selected);
      final DetectionFrame? frame = source?.frame;
      if (_alertOn && frame != null && frame.seq != _lastAlertSeq) {
        _lastAlertSeq = frame.seq;
        if (_alert.update(frame.boxes)) {
          TrafficAlert.sound();
        }
      }
    }
    setState(() {});
  }

  void _choose(String? id) {
    _selected = id;
    _alert.reset();
    _lastAlertSeq = -1;
    _link.watch(id);
  }

  @override
  Widget build(BuildContext context) {
    final List<VisualSource> sources = _link.visualSources;
    final String? selected = _selected;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Visual Traffic Viewer"),
        actions: [
          if (sources.length > 1 || (selected != null && sources.isNotEmpty))
            PopupMenuButton<String>(
              icon: const Icon(Icons.phone_android),
              tooltip: "Camera phone",
              onSelected: _choose,
              itemBuilder: (BuildContext context) => [
                for (final VisualSource s in sources)
                  CheckedPopupMenuItem<String>(
                    value: s.id,
                    checked: s.id == selected,
                    child: Text(s.name),
                  ),
              ],
            ),
          IconButton(
            icon: Icon(_alertOn ? Icons.notifications_active : Icons.notifications_off),
            tooltip: "Alert on a new red box",
            onPressed: () {
              setState(() => _alertOn = !_alertOn);
              Storage().settings.setVisualTrafficAlert(_alertOn);
            },
          ),
          IconButton(
            icon: Icon(_showHorizon ? Icons.horizontal_rule : Icons.landscape_outlined),
            tooltip: "Show horizon line",
            onPressed: () => setState(() => _showHorizon = !_showHorizon),
          ),
        ],
      ),
      body: selected == null ? _waitingForSource(sources) : _picture(selected),
    );
  }

  Widget _waitingForSource(List<VisualSource> sources) {
    if (!_link.isRunning) {
      return _message(
        _link.bindError == null
            ? "Link is not running. Join the same Wi-Fi as the camera phone."
            : "Link could not start: ${_link.bindError}",
      );
    }
    if (sources.isEmpty) {
      return _message(
        "Looking for a camera phone on this Wi-Fi.\n\nOn that phone open Visual Traffic and choose \"This phone is the camera\".",
        spinner: true,
      );
    }
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            "Choose a camera phone",
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
        ),
        for (final VisualSource s in sources)
          ListTile(
            leading: const Icon(Icons.videocam, color: Colors.white),
            title: Text(s.name, style: const TextStyle(color: Colors.white)),
            subtitle: Text(s.address, style: const TextStyle(color: Colors.white70)),
            onTap: () => setState(() => _choose(s.id)),
          ),
      ],
    );
  }

  Widget _picture(String id) {
    final VisualSource? source = _link.visualSource(id);
    final DateTime now = DateTime.now();
    final DetectionFrame? frame = source?.frame;
    final bool boxesFresh = source?.frameAt != null && now.difference(source!.frameAt!) < _stale;
    final Uint8List? jpeg = source?.preview;
    final bool pictureFresh = jpeg != null &&
        source?.previewAt != null &&
        now.difference(source!.previewAt!) < _stale;
    final double aspect = (jpeg != null && source!.previewWidth > 0 && source.previewHeight > 0)
        ? source.previewWidth / source.previewHeight
        : 16 / 9;
    final int red = boxesFresh ? (frame?.airplaneCount ?? 0) : 0;
    final String status;
    if (source == null || !boxesFresh) {
      status = "No data from ${source?.name ?? 'the camera phone'}";
    } else if (!pictureFresh) {
      status = "Waiting for the picture";
    } else {
      status = "";
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: aspect,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (jpeg != null)
                  Opacity(
                    opacity: pictureFresh ? 1 : 0.3,
                    child: Image.memory(
                      jpeg,
                      gaplessPlayback: true,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.medium,
                    ),
                  )
                else
                  const ColoredBox(color: Color(0xFF1B1B1B)),
                RepaintBoundary(
                  child: CustomPaint(
                    painter: DetectionPainter(
                      boxes: frame?.boxes ?? const [],
                      fovH: frame?.fovH ?? 65,
                      fovV: frame?.fovV ?? 37,
                      horizonLeft: frame?.horizonLeft,
                      horizonRight: frame?.horizonRight,
                      showHorizon: _showHorizon,
                      dimmed: !boxesFresh,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (status.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            top: 12,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(status, style: const TextStyle(color: Colors.white)),
              ),
            ),
          ),
        Positioned(
          left: 8,
          top: status.isEmpty ? 8 : 52,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: red > 0 ? const Color(0xCCB00020) : Colors.black54,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              red > 0 ? "$red AIRPLANE${red > 1 ? 'S' : ''}" : (source?.name ?? ""),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
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

  Widget _message(String text, {bool spinner = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spinner) const CircularProgressIndicator(),
            if (spinner) const SizedBox(height: 16),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
