import 'dart:async';

import 'package:avaremp/main_screen.dart';
import 'package:avaremp/plan/plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'demo_overlay.dart';
import 'demo_registry.dart';
import 'demo_step.dart';
import 'demo_target.dart';
import 'demo_tour.dart';

/// Plays [DemoTour]s by highlighting targets and dispatching real pointer events.
class DemoEngine {
  DemoEngine._();
  static final DemoEngine instance = DemoEngine._();

  final ValueNotifier<DemoOverlayState> overlay =
      ValueNotifier<DemoOverlayState>(DemoOverlayState.hidden);

  bool isRunning = false;
  bool paused = false;

  bool _skipRequested = false;
  bool _exitRequested = false;
  int _pointerId = 900000;

  String? _planSnapshotJson;
  String? _planSnapshotName;
  String sampleRoute = 'KBOS KORH';
  String sampleIdent = 'KBOS';

  Future<void> playAll() => playTours(DemoRegistry.tours);

  Future<void> playTour(DemoTour tour) => playTours(<DemoTour>[tour]);

  Future<void> playTours(List<DemoTour> tours) async {
    if (isRunning || tours.isEmpty) {
      return;
    }
    isRunning = true;
    paused = false;
    _exitRequested = false;
    Storage().isDemoRunning = true;
    try {
      for (final DemoTour tour in tours) {
        if (_exitRequested) {
          break;
        }
        await _playTour(tour);
      }
    } finally {
      await restorePlanIfNeeded();
      isRunning = false;
      paused = false;
      Storage().isDemoRunning = false;
      overlay.value = DemoOverlayState.hidden;
    }
  }

  void pause() {
    if (!isRunning || paused) {
      return;
    }
    paused = true;
    overlay.value = overlay.value.copyWith(paused: true);
  }

  void resume() {
    if (!isRunning || !paused) {
      return;
    }
    paused = false;
    overlay.value = overlay.value.copyWith(paused: false);
  }

  void togglePause() {
    if (paused) {
      resume();
    } else {
      pause();
    }
  }

  void skip() {
    _skipRequested = true;
  }

  void exit() {
    _exitRequested = true;
    _skipRequested = true;
    paused = false;
  }

  Future<void> snapshotPlan() async {
    _planSnapshotJson = Storage().route.toJson(Storage().route.name);
    _planSnapshotName = Storage().route.name;
  }

  Future<void> restorePlanIfNeeded() async {
    if (_planSnapshotJson == null) {
      return;
    }
    try {
      final PlanRoute restored = await PlanRoute.fromJson(
        _planSnapshotJson!,
        _planSnapshotName ?? 'New Plan',
        false,
      );
      Storage().route.copyFrom(restored);
    } catch (_) {
      // Keep whatever is on screen if restore fails.
    }
    _planSnapshotJson = null;
    _planSnapshotName = null;
  }

  Future<void> _playTour(DemoTour tour) async {
    final int total = tour.steps.length;
    for (int i = 0; i < tour.steps.length; i++) {
      if (_exitRequested) {
        return;
      }
      _skipRequested = false;
      overlay.value = overlay.value.copyWith(
        visible: true,
        tourTitle: tour.title,
        stepIndex: i + 1,
        stepCount: total,
        paused: paused,
      );
      await _runStep(tour.steps[i]);
    }
  }

  Future<void> _runStep(DemoStep step) async {
    switch (step) {
      case Narrate(:final text, :final hold):
        _showCaption(text, highlight: null);
        await _hold(hold);
      case Tap(:final targetId, :final caption, :final timeout, :final after):
        final Rect? rect = await _waitForTarget(targetId, timeout);
        if (rect == null) {
          return;
        }
        _showCaption(caption ?? overlay.value.caption, highlight: rect);
        await _hold(const Duration(milliseconds: 450));
        if (_cancelled) {
          return;
        }
        await _tapRect(rect);
        await _hold(after);
      case Wait(:final duration):
        await _hold(duration);
      case GoTab(:final index, :final caption):
        _showCaption(
          caption ?? _tabCaption(index),
          highlight: DemoTargets.rectOf('nav.bar'),
        );
        await _hold(const Duration(milliseconds: 500));
        if (_cancelled) {
          return;
        }
        _goTab(index);
        await _hold(const Duration(milliseconds: 450));
      case final TypeText typeStep:
        final Rect? rect = await _waitForTarget(typeStep.targetId, typeStep.timeout);
        if (rect == null) {
          return;
        }
        _showCaption(typeStep.caption ?? overlay.value.caption, highlight: rect);
        await _hold(const Duration(milliseconds: 300));
        if (_cancelled) {
          return;
        }
        await _tapRect(rect);
        await _typeInto(typeStep.targetId, typeStep.resolved());
        FocusManager.instance.primaryFocus?.unfocus();
        await _hold(const Duration(milliseconds: 400));
      case Pop(:final after):
        Storage().navigatorKey.currentState?.maybePop();
        await _hold(after);
      case Prepare(:final run):
        try {
          await run();
        } catch (_) {
          // Setup failures should not abort the rest of the tour.
        }
    }
  }

  bool get _cancelled => _exitRequested || _skipRequested;

  void _showCaption(String text, {Rect? highlight}) {
    overlay.value = overlay.value.copyWith(
      visible: true,
      highlight: highlight,
      clearHighlight: highlight == null,
      caption: text,
      paused: paused,
    );
  }

  String _tabCaption(int index) {
    switch (index) {
      case GoTab.mapIndex:
        return 'MAP is the moving map.';
      case GoTab.plateIndex:
        return 'PLATE shows approach plates and airport diagrams.';
      case GoTab.planIndex:
        return 'PLAN is where you build a route.';
      case GoTab.findIndex:
        return 'FIND searches airports, navaids, and fixes.';
      default:
        return 'These tabs switch the main screens.';
    }
  }

  void _goTab(int index) {
    try {
      switch (index) {
        case GoTab.mapIndex:
          MainScreenState.gotoMap();
        case GoTab.plateIndex:
          MainScreenState.gotoPlate();
        case GoTab.planIndex:
          MainScreenState.gotoPlan();
        case GoTab.findIndex:
          MainScreenState.gotoFind();
      }
    } catch (_) {
      // Bottom nav may not be mounted yet.
    }
  }

  Future<Rect?> _waitForTarget(String id, Duration timeout) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_cancelled) {
        return null;
      }
      await _yieldPaused();
      if (_cancelled) {
        return null;
      }
      final Rect? rect = DemoTargets.rectOf(id);
      if (rect != null && rect.width > 0 && rect.height > 0) {
        return rect;
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    return null;
  }

  Future<void> _tapRect(Rect rect) async {
    final Offset position = rect.center;
    final int pointer = _pointerId++;
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: pointer, position: position),
    );
    await Future<void>.delayed(const Duration(milliseconds: 70));
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(pointer: pointer, position: position),
    );
  }

  Future<void> _typeInto(String id, String text) async {
    for (int i = 1; i <= text.length; i++) {
      if (_cancelled) {
        return;
      }
      await _yieldPaused();
      _applyText(id, text.substring(0, i));
      await Future<void>.delayed(const Duration(milliseconds: 70));
    }
    _applyText(id, text);
  }

  void _applyText(String id, String text) {
    final BuildContext? ctx = DemoTargets.contextOf(id);
    if (ctx == null) {
      return;
    }
    TextEditingController? controller;
    ValueChanged<String>? onChanged;
    void visitor(Element element) {
      final Widget widget = element.widget;
      if (widget is EditableText) {
        controller = widget.controller;
      }
      if (widget is TextFormField) {
        onChanged = widget.onChanged;
      }
      if (widget is TextField) {
        onChanged ??= widget.onChanged;
      }
      element.visitChildren(visitor);
    }

    ctx.visitChildElements(visitor);
    if (controller != null) {
      controller!.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    onChanged?.call(text);
  }

  Future<void> _hold(Duration duration) async {
    final DateTime deadline = DateTime.now().add(duration);
    while (DateTime.now().isBefore(deadline)) {
      if (_cancelled) {
        return;
      }
      await _yieldPaused();
      if (_cancelled) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _yieldPaused() async {
    while (paused && !_exitRequested && !_skipRequested) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }
}
