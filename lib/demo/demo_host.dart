import 'package:flutter/material.dart';

import 'demo_engine.dart';
import 'demo_overlay.dart';

/// Sits above every route so the demo spotlight stays visible.
class DemoHost extends StatelessWidget {
  final Widget child;

  const DemoHost({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        ValueListenableBuilder<DemoOverlayState>(
          valueListenable: DemoEngine.instance.overlay,
          builder: (context, state, _) {
            return DemoOverlay(
              state: _toLocal(context, state),
              onPauseResume: DemoEngine.instance.togglePause,
              onSkip: DemoEngine.instance.skip,
              onExit: DemoEngine.instance.exit,
            );
          },
        ),
      ],
    );
  }

  DemoOverlayState _toLocal(BuildContext context, DemoOverlayState state) {
    final Rect? highlight = state.highlight;
    if (highlight == null) {
      return state;
    }
    final RenderObject? object = context.findRenderObject();
    if (object is! RenderBox || !object.hasSize) {
      return state;
    }
    final Offset topLeft = object.globalToLocal(highlight.topLeft);
    return state.copyWith(highlight: topLeft & highlight.size);
  }
}
