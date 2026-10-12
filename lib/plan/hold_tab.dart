import 'package:avaremp/main_screen.dart';
import 'package:avaremp/map_screen.dart';
import 'package:avaremp/plan/hold.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Hold setup dialog opened from the destination popup Main tab.
class HoldSetup {
  static Future<void> open(
    BuildContext host, {
    required LatLng fix,
    required String name,
  }) {
    return showDialog<void>(
      context: host,
      builder: (context) => _HoldDialog(
        fix: fix,
        name: name,
        onDrawn: () {
          MapScreenState.showOnMap(fix);
          MainScreenState.gotoMap();
          if (host.mounted) {
            Navigator.of(host).pop();
          }
        },
      ),
    );
  }
}

class _HoldDialog extends StatefulWidget {
  final LatLng fix;
  final String name;
  final VoidCallback onDrawn;

  const _HoldDialog({
    required this.fix,
    required this.name,
    required this.onDrawn,
  });

  @override
  State<_HoldDialog> createState() => _HoldDialogState();
}

class _HoldDialogState extends State<_HoldDialog> {
  static const List<double> _lengths = [1.5, 2, 3, 4];

  late int _inbound;
  bool _right = true;
  double _legNm = 4;

  @override
  void initState() {
    super.initState();
    final HoldPattern? existing = Storage().hold;
    if (existing != null && _sameFix(existing.fix, widget.fix)) {
      _inbound = existing.inboundMagnetic.round() % 360;
      _right = existing.rightTurns;
      _legNm = _matchLength(existing.legNm);
    } else {
      _inbound = _defaultInbound().round() % 360;
    }
  }

  double _matchLength(double nm) {
    for (final double option in _lengths) {
      if ((option - nm).abs() < 0.05) {
        return option;
      }
    }
    return 4;
  }

  bool _sameFix(LatLng a, LatLng b) {
    return (a.latitude - b.latitude).abs() < 0.002 &&
        (a.longitude - b.longitude).abs() < 0.002;
  }

  double _norm(double deg) {
    final double m = deg % 360;
    return m < 0 ? m + 360 : m;
  }

  /// Magnetic course from ownship to the fix, or track if already there.
  double _defaultInbound() {
    final LatLng here =
        LatLng(Storage().position.latitude, Storage().position.longitude);
    final double variation = Storage().area.variation;
    if (_sameFix(here, widget.fix)) {
      return _norm(Storage().position.heading - variation);
    }
    final double courseTrue =
        GeoCalculations().calculateBearing(here, widget.fix);
    return _norm(courseTrue - variation);
  }

  void _bump(int delta) {
    setState(() {
      _inbound = (_inbound + delta) % 360;
      if (_inbound < 0) {
        _inbound += 360;
      }
    });
  }

  String _nm(double nm) {
    return nm == nm.roundToDouble() ? "${nm.toInt()}" : nm.toStringAsFixed(1);
  }

  void _draw() {
    final double speedKt = holdSpeedFromMs(Storage().position.speed);
    Storage().setHold(HoldPattern(
      fix: widget.fix,
      name: widget.name,
      inboundMagnetic: _inbound.toDouble(),
      rightTurns: _right,
      legNm: _legNm,
      speedKt: speedKt,
    ));
    Navigator.of(context).pop();
    widget.onDrawn();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text("Hold", style: text.titleLarge),
                  ),
                  IconButton(
                    tooltip: "Close",
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  widget.name,
                  style: text.bodyMedium?.copyWith(color: scheme.outline),
                ),
              ),
              const SizedBox(height: 16),
              _heading(context, "Inbound"),
              const SizedBox(height: 6),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                  child: Column(
                    children: [
                      Text(
                        "${_inbound.toString().padLeft(3, "0")}°",
                        textAlign: TextAlign.center,
                        style: text.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        "magnetic",
                        style: text.labelSmall?.copyWith(color: scheme.outline),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _nudge(context, -10)),
                          Expanded(child: _nudge(context, -1)),
                          Expanded(child: _nudge(context, 1)),
                          Expanded(child: _nudge(context, 10)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _heading(context, "Turns"),
              const SizedBox(height: 6),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment<bool>(
                    value: true,
                    label: Text("Right"),
                    icon: Icon(Icons.turn_right),
                    tooltip: "Standard",
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    label: Text("Left"),
                    icon: Icon(Icons.turn_left),
                  ),
                ],
                selected: {_right},
                onSelectionChanged: (Set<bool> next) {
                  setState(() => _right = next.first);
                },
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  "Right is standard",
                  style: text.labelSmall?.copyWith(color: scheme.outline),
                ),
              ),
              const SizedBox(height: 16),
              _heading(context, "Length (NM)"),
              const SizedBox(height: 6),
              SegmentedButton<double>(
                showSelectedIcon: false,
                segments: [
                  for (final double nm in _lengths)
                    ButtonSegment<double>(
                      value: nm,
                      label: Text(_nm(nm)),
                    ),
                ],
                selected: {_legNm},
                onSelectionChanged: (Set<double> next) {
                  setState(() => _legNm = next.first);
                },
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  onPressed: _draw,
                  child: const Text("Draw on Map"),
                ),
              ),
              ValueListenableBuilder<int>(
                valueListenable: Storage().holdChange,
                builder: (context, _, __) {
                  if (Storage().hold == null) {
                    return const SizedBox(height: 4);
                  }
                  return Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: () => Storage().setHold(null),
                      child: const Text("Clear hold"),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, String label) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }

  Widget _nudge(BuildContext context, int delta) {
    final String label = delta > 0 ? "+$delta" : "$delta";
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(44, 40),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () => _bump(delta),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
