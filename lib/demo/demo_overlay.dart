import 'package:flutter/material.dart';

/// Visual state the [DemoHost] paints on top of the app.
class DemoOverlayState {
  final bool visible;
  final Rect? highlight;
  final String caption;
  final String? tourTitle;
  final bool paused;
  final int stepIndex;
  final int stepCount;

  const DemoOverlayState({
    required this.visible,
    this.highlight,
    this.caption = '',
    this.tourTitle,
    this.paused = false,
    this.stepIndex = 0,
    this.stepCount = 0,
  });

  static const DemoOverlayState hidden = DemoOverlayState(visible: false);

  DemoOverlayState copyWith({
    bool? visible,
    Rect? highlight,
    bool clearHighlight = false,
    String? caption,
    String? tourTitle,
    bool? paused,
    int? stepIndex,
    int? stepCount,
  }) {
    return DemoOverlayState(
      visible: visible ?? this.visible,
      highlight: clearHighlight ? null : (highlight ?? this.highlight),
      caption: caption ?? this.caption,
      tourTitle: tourTitle ?? this.tourTitle,
      paused: paused ?? this.paused,
      stepIndex: stepIndex ?? this.stepIndex,
      stepCount: stepCount ?? this.stepCount,
    );
  }
}

class DemoOverlay extends StatelessWidget {
  final DemoOverlayState state;
  final VoidCallback onPauseResume;
  final VoidCallback onSkip;
  final VoidCallback onExit;

  const DemoOverlay({
    super.key,
    required this.state,
    required this.onPauseResume,
    required this.onSkip,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    if (!state.visible) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);
    final Rect? hole = state.highlight;

    return Stack(
      children: [
        // Dim + spotlight + finger: pass hits through so simulated taps reach the app.
        IgnorePointer(
          child: Stack(
            children: [
              CustomPaint(
                painter: _SpotlightPainter(hole: hole),
                child: const SizedBox.expand(),
              ),
              if (hole != null) _Finger(position: hole.center),
            ],
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
          child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (state.caption.isNotEmpty)
                      Expanded(
                        child: IgnorePointer(
                          child: Material(
                            elevation: 4,
                            color: theme.colorScheme.surface.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (state.tourTitle != null)
                                    Text(
                                      state.tourTitle!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: theme.colorScheme.primary,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  if (state.tourTitle != null) const SizedBox(height: 4),
                                  Text(
                                    state.caption,
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                  ),
                                  if (state.stepCount > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        '${state.stepIndex} / ${state.stepCount}',
                                        style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    const SizedBox(width: 8),
                    Material(
                      elevation: 4,
                      color: theme.colorScheme.surface.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(24),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: state.paused ? 'Resume' : 'Pause',
                            icon: Icon(state.paused ? Icons.play_arrow : Icons.pause),
                            onPressed: onPauseResume,
                          ),
                          IconButton(
                            tooltip: 'Skip step',
                            icon: const Icon(Icons.skip_next),
                            onPressed: onSkip,
                          ),
                          IconButton(
                            tooltip: 'Exit demo',
                            icon: const Icon(Icons.close),
                            onPressed: onExit,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ),
        ),
      ],
    );
  }
}

class _Finger extends StatelessWidget {
  final Offset position;

  const _Finger({required this.position});

  @override
  Widget build(BuildContext context) {
    const double size = 44;
    return Positioned(
      left: position.dx - 8,
      top: position.dy - 6,
      child: Icon(
        Icons.touch_app,
        size: size,
        color: Colors.white,
        shadows: const [
          Shadow(blurRadius: 8, color: Colors.black54, offset: Offset(1, 2)),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? hole;

  _SpotlightPainter({required this.hole});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint dim = Paint()..color = Colors.black.withValues(alpha: 0.45);
    final Path path = Path()..addRect(Offset.zero & size);
    if (hole != null) {
      final Rect padded = hole!.inflate(10);
      path.addRRect(RRect.fromRectAndRadius(padded, const Radius.circular(12)));
      path.fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(path, dim);
    if (hole != null) {
      final Paint ring = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawRRect(
        RRect.fromRectAndRadius(hole!.inflate(10), const Radius.circular(12)),
        ring,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.hole != hole;
  }
}
