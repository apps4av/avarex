import 'package:flutter/material.dart';

import 'demo_engine.dart';
import 'demo_overlay.dart';

/// Sits above every route so the demo spotlight stays visible.
///
/// [MaterialApp.builder] places this *beside* the navigator, not inside it, so
/// the chrome needs its own [Overlay] for [IconButton] tooltips.
class DemoHost extends StatefulWidget {
  final Widget child;

  const DemoHost({super.key, required this.child});

  @override
  State<DemoHost> createState() => _DemoHostState();
}

class _DemoHostState extends State<DemoHost> {
  late final OverlayEntry _entry = OverlayEntry(builder: _buildStack);

  @override
  void didUpdateWidget(covariant DemoHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child != widget.child) {
      _entry.markNeedsBuild();
    }
  }

  Widget _buildStack(BuildContext context) {
    return Stack(
      children: [
        widget.child,
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

  @override
  Widget build(BuildContext context) {
    return Overlay(initialEntries: <OverlayEntry>[_entry]);
  }
}
