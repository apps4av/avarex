import 'package:avaremp/destination_calculations.dart';
import 'package:flutter/material.dart';

import 'constants.dart';
import 'destination.dart';

class PlanLineWidget extends StatefulWidget {

  final Destination destination;

  const PlanLineWidget({super.key, required this.destination, });

  @override
  State<StatefulWidget> createState() => PlanLineWidgetState();
}

class PlanLineWidgetState extends State<PlanLineWidget> {

  @override
  Widget build(BuildContext context) {
    return Column(
        children: [
          _getFields()
        ]
      );
  }

  static Widget getHeading() {
    return const Row(children: [
      Expanded(flex: 1, child: Text("Dist")),
      Expanded(flex: 1, child: Text("GSpd")),
      Expanded(flex: 1, child: Text("Crs")),
      Expanded(flex: 1, child: Text("Time")),
      Expanded(flex: 1, child: Text("Fuel")),
    ]);
  }

  static Widget getNullFields() {
    return const Row(children: [
      Expanded(flex: 1, child: Text("---")),
      Expanded(flex: 1, child: Text("---")),
      Expanded(flex: 1, child: Text("---")),
      Expanded(flex: 1, child: Text("--:--")),
      Expanded(flex: 1, child: Text("---")),
    ]);
  }

  static Widget getFieldsFromCalculations(DestinationCalculations? calculations) {
    return null == calculations ?
      getNullFields() :
      Row(children: [
        Expanded(flex: 1, child: Text(calculations.distance.round().toString())),
        Expanded(flex: 1, child: Text(calculations.groundSpeed.round().toString())),
        Expanded(flex: 1, child: Text(calculations.course.round().toString())),
        Expanded(flex: 1, child: Text(Constants.secondsToHHmm(calculations.time.round()))),
        Expanded(flex: 1, child: Text(calculations.fuel.toStringAsFixed(1))),
      ]);
  }

  Widget _getFields() {
    return getFieldsFromCalculations(widget.destination.calculations);
  }

}
