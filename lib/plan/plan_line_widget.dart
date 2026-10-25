import 'package:avaremp/destination/destination_calculations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:avaremp/constants.dart';
import 'package:avaremp/destination/destination.dart';

class PlanLineWidget extends StatefulWidget {

  final Destination destination;
  final int altitude;
  final ValueChanged<int> onAltitudeChanged;
  final VoidCallback onAltitudeCleared;

  const PlanLineWidget({
    super.key,
    required this.destination,
    required this.altitude,
    required this.onAltitudeChanged,
    required this.onAltitudeCleared,
  });

  @override
  State<StatefulWidget> createState() => PlanLineWidgetState();
}

/// Accepts focus only after a tap. A route popping back (nav log, 3D) must
/// not restore this field and open the keyboard.
class _AltitudeFocusNode extends FocusNode {
  bool armed = false;

  @override
  bool get canRequestFocus => armed && super.canRequestFocus;
}

class PlanLineWidgetState extends State<PlanLineWidget> {
  /// Altitude fields currently open. The one-second plan refresh skips those
  /// rows so the keyboard is not dismissed by the rebuild.
  static int editingCount = 0;
  static bool get isEditing => editingCount > 0;

  /// The plan tab stays mounted under the map. Drop the field so the keyboard
  /// does not stay up on a screen where nothing is being edited.
  static void endEditing() {
    if (!isEditing) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
  }

  final TextEditingController _altitudeController = TextEditingController();
  final _AltitudeFocusNode _altitudeFocus = _AltitudeFocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _altitudeController.text = widget.altitude.toString();
    _altitudeFocus.addListener(_onAltitudeFocus);
  }

  @override
  void didUpdateWidget(PlanLineWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool differentPlace =
        widget.destination.locationID != oldWidget.destination.locationID;
    if (!_altitudeFocus.hasFocus &&
        (widget.altitude != oldWidget.altitude || differentPlace)) {
      _altitudeController.text = widget.altitude.toString();
    }
  }

  @override
  void dispose() {
    _setEditing(false);
    _altitudeFocus.removeListener(_onAltitudeFocus);
    _altitudeFocus.dispose();
    _altitudeController.dispose();
    super.dispose();
  }

  void _onAltitudeFocus() {
    final bool focused = _altitudeFocus.hasFocus;
    if (!focused) {
      _altitudeFocus.armed = false;
    }
    _setEditing(focused);
    if (!focused) {
      _commitAltitude();
    }
  }

  void _setEditing(bool editing) {
    if (_editing == editing) {
      return;
    }
    _editing = editing;
    if (editing) {
      editingCount++;
    } else if (editingCount > 0) {
      editingCount--;
    }
  }

  void _commitAltitude() {
    final String text = _altitudeController.text.trim();
    if (text.isEmpty) {
      widget.onAltitudeCleared();
      _altitudeController.text = widget.altitude.toString();
      return;
    }
    final int? value = int.tryParse(text);
    if (value == null || value > 60000) {
      _altitudeController.text = widget.altitude.toString();
      return;
    }
    _altitudeController.text = value.toString();
    if (value != widget.altitude) {
      widget.onAltitudeChanged(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      ..._calculationCells(widget.destination.calculations),
      Expanded(flex: 1, child: _altitudeField()),
    ]);
  }

  Widget _altitudeField() {
    return Semantics(
      label: 'Altitude',
      value: _altitudeController.text,
      child: ExcludeSemantics(
        child: Listener(
          onPointerDown: (_) {
            _altitudeFocus.armed = true;
          },
          onPointerUp: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_altitudeFocus.hasFocus) {
                _altitudeFocus.armed = false;
              }
            });
          },
          onPointerCancel: (_) {
            if (!_altitudeFocus.hasFocus) {
              _altitudeFocus.armed = false;
            }
          },
          child: TextField(
            controller: _altitudeController,
            focusNode: _altitudeFocus,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: DefaultTextStyle.of(context).style,
            decoration: const InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: (_) => _commitAltitude(),
          ),
        ),
      ),
    );
  }

  static Widget getHeading() {
    return const Row(children: [
      Expanded(flex: 1, child: Text("Dist")),
      Expanded(flex: 1, child: Text("GSpd")),
      Expanded(flex: 1, child: Text("Crs")),
      Expanded(flex: 1, child: Text("Time")),
      Expanded(flex: 1, child: Text("Fuel")),
      Expanded(flex: 1, child: Text("Alt")),
    ]);
  }

  static List<Widget> _calculationCells(DestinationCalculations? calculations) {
    if (calculations == null) {
      return const [
        Expanded(flex: 1, child: Text("---")),
        Expanded(flex: 1, child: Text("---")),
        Expanded(flex: 1, child: Text("---")),
        Expanded(flex: 1, child: Text("--:--")),
        Expanded(flex: 1, child: Text("---")),
      ];
    }
    return [
      Expanded(flex: 1, child: Text(calculations.distance.round().toString())),
      Expanded(flex: 1, child: Text(calculations.groundSpeed.round().toString())),
      Expanded(flex: 1, child: Text(calculations.course.round().toString())),
      Expanded(flex: 1, child: Text(Constants.secondsToHHmm(calculations.time.round()))),
      Expanded(flex: 1, child: Text(calculations.fuel.toStringAsFixed(1))),
    ];
  }

  static Widget getFieldsFromCalculations(DestinationCalculations? calculations, {Widget? altitudeCell}) {
    return Row(children: [
      ..._calculationCells(calculations),
      Expanded(flex: 1, child: altitudeCell ?? const SizedBox.shrink()),
    ]);
  }

}
