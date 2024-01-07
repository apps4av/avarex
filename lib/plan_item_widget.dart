import 'package:flutter/material.dart';
import 'constants.dart';
import 'destination.dart';

class PlanItemWidget extends StatefulWidget {
  final Destination destination;
  final bool next;

  // it crashes if not static

  const PlanItemWidget({super.key, required this.destination, required this.next});

  @override
  State<StatefulWidget> createState() => PlanItemWidgetState();
}


class PlanItemWidgetState extends State<PlanItemWidget> {

  @override
  Widget build(BuildContext context) {

    Color color = Colors.white;
    if(widget.destination is AirwayDestination && (widget.destination as AirwayDestination).adjustedPoints.isEmpty) {
      color = Colors.red;
    }

    return Column(children: [
      ListTile(
        leading: TypeIcons.getIcon(widget.destination.type, color),
        subtitle: Text(widget.destination.locationID, style: TextStyle(color: widget.next ? Constants.planActiveColor : Colors.white))),
      const Divider(),
    ]);

  }

}
