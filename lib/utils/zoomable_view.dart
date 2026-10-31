import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Pinch / double-tap / mouse-wheel zoom that can live inside a [PageView].
///
/// [InteractiveViewer] cannot be used for that: its scale recognizer wins the
/// gesture arena over the page view's horizontal drag, so the pages can no longer
/// be swiped. This widget instead reads raw pointer events (which never take part
/// in the arena):
///  * one finger while not zoomed does nothing here, so the pager can swipe;
///  * two fingers pinch-zoom (and pan);
///  * one finger pans while zoomed in.
///
/// [onLockChanged] is called with true while the content is zoomed in or being
/// pinched. The parent should disable page swiping while it is true.
class ZoomableView extends StatefulWidget {
  final Widget child;
  final ValueChanged<bool>? onLockChanged;
  final double maxScale;

  const ZoomableView({
    super.key,
    required this.child,
    this.onLockChanged,
    this.maxScale = 6,
  });

  @override
  State<ZoomableView> createState() => _ZoomableViewState();
}

class _ZoomableViewState extends State<ZoomableView> {
  static const double _snapScale = 1.05;
  static const double _doubleTapScale = 3;

  final Map<int, Offset> _pointers = {};
  double _scale = 1;
  Offset _offset = Offset.zero; // translation, applied after scaling about the centre
  Size _size = Size.zero;

  // state when the set of pointers last changed
  double _baseScale = 1;
  Offset _baseOffset = Offset.zero;
  Offset _baseFocal = Offset.zero; // relative to the centre
  double _baseDistance = 0;

  Offset _doubleTapPosition = Offset.zero;
  bool _locked = false;

  Offset get _center => Offset(_size.width / 2, _size.height / 2);

  Offset get _focal {
    Offset sum = Offset.zero;
    for (final Offset p in _pointers.values) {
      sum += p;
    }
    return sum / _pointers.length.toDouble();
  }

  double get _distance {
    if (_pointers.length < 2) {
      return 0;
    }
    final List<Offset> p = _pointers.values.toList();
    return (p[0] - p[1]).distance;
  }

  void _rebase() {
    _baseScale = _scale;
    _baseOffset = _offset;
    _baseDistance = _distance;
    _baseFocal = _pointers.isEmpty ? Offset.zero : _focal - _center;
  }

  Offset _clampOffset(Offset t, double scale) {
    final double maxX = max(0, (scale - 1) * _size.width / 2);
    final double maxY = max(0, (scale - 1) * _size.height / 2);
    return Offset(t.dx.clamp(-maxX, maxX), t.dy.clamp(-maxY, maxY));
  }

  void _notifyLock() {
    final bool locked = _pointers.length >= 2 || _scale > 1.01;
    if (locked != _locked) {
      _locked = locked;
      widget.onLockChanged?.call(locked);
    }
  }

  void _onDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    _rebase();
    _notifyLock();
  }

  void _onMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) {
      return;
    }
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length < 2 && _scale <= 1) {
      return; // plain swipe, not ours
    }
    double scale = _baseScale;
    if (_pointers.length >= 2 && _baseDistance > 0) {
      scale = (_baseScale * _distance / _baseDistance).clamp(1.0, widget.maxScale);
    }
    // content point that was under the focal point when the gesture (re)started
    final Offset content = (_baseFocal - _baseOffset) / _baseScale;
    final Offset offset = (_focal - _center) - content * scale;
    setState(() {
      _scale = scale;
      _offset = _clampOffset(offset, scale);
    });
    _notifyLock();
  }

  void _onUp(PointerEvent e) {
    if (_pointers.remove(e.pointer) == null) {
      return;
    }
    setState(() {
      if (_scale < _snapScale) {
        _scale = 1;
        _offset = Offset.zero;
      }
    });
    _rebase();
    _notifyLock();
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) {
      return;
    }
    final double scale = (_scale * exp(-e.scrollDelta.dy / 300)).clamp(1.0, widget.maxScale);
    _zoomAbout(e.localPosition, scale);
  }

  void _zoomAbout(Offset position, double scale) {
    final Offset content = (position - _center - _offset) / _scale;
    final Offset offset = (position - _center) - content * scale;
    setState(() {
      if (scale < _snapScale) {
        _scale = 1;
        _offset = Offset.zero;
      }
      else {
        _scale = scale;
        _offset = _clampOffset(offset, scale);
      }
    });
    _rebase();
    _notifyLock();
  }

  void _onDoubleTap() {
    _zoomAbout(_doubleTapPosition, _scale > 1 ? 1 : _doubleTapScale);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _size = constraints.biggest;
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onUp,
        onPointerSignal: _onSignal,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTapDown: (d) => _doubleTapPosition = d.localPosition,
          onDoubleTap: _onDoubleTap,
          child: ClipRect(
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.translationValues(_offset.dx, _offset.dy, 0) *
                  Matrix4.diagonal3Values(_scale, _scale, 1),
              child: widget.child,
            ),
          ),
        ),
      );
    });
  }
}
