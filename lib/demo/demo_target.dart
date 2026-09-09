import 'package:flutter/material.dart';

/// Live registry of [DemoTarget] keys so the engine can find on-screen controls.
class DemoTargets {
  static final Map<String, GlobalKey> _keys = {};

  static GlobalKey keyFor(String id) {
    return _keys.putIfAbsent(id, () => GlobalKey(debugLabel: id));
  }

  static bool isMounted(String id) {
    return _keys[id]?.currentContext != null;
  }

  static BuildContext? contextOf(String id) {
    return _keys[id]?.currentContext;
  }

  static Rect? rectOf(String id) {
    final BuildContext? ctx = _keys[id]?.currentContext;
    if (ctx == null) {
      return null;
    }
    final RenderObject? object = ctx.findRenderObject();
    if (object is! RenderBox || !object.hasSize) {
      return null;
    }
    final Offset offset = object.localToGlobal(Offset.zero);
    return offset & object.size;
  }
}

/// Wraps a control so a demo tour can highlight and tap it by [id].
class DemoTarget extends StatelessWidget {
  final String id;
  final Widget child;

  const DemoTarget({super.key, required this.id, required this.child});

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: DemoTargets.keyFor(id),
      child: child,
    );
  }
}
