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

class PlanLineWidgetState extends State<PlanLineWidget> {
  final TextEditingController _altitudeController = TextEditingController();
  final FocusNode _altitudeFocus = FocusNode();

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
    _altitudeFocus.removeListener(_onAltitudeFocus);
    _altitudeFocus.dispose();
    _altitudeController.dispose();
    super.dispose();
  }

  void _onAltitudeFocus() {
    if (!_altitudeFocus.hasFocus) {
      _commitAltitude();
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
    return TextField(
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
      onTap: () {},
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
