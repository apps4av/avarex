import 'package:avaremp/plan_route.dart';
import 'package:flutter/material.dart';
import 'constants.dart';
import 'destination.dart';

class PlanItemWidget extends StatefulWidget {
  final Waypoint waypoint;
  final bool next;

  // it crashes if not static

  const PlanItemWidget({super.key, required this.waypoint, required this.next});

  @override
  State<StatefulWidget> createState() => PlanItemWidgetState();
}


class PlanItemWidgetState extends State<PlanItemWidget> {

  @override
  Widget build(BuildContext context) {

    Color iconColor = Destination.isAirway(widget.waypoint.destination.type) && widget.waypoint.adjustedPoints.isEmpty ? Colors.red : Colors.white;

    return Column(children: [
      ListTile(
        leading: TypeIcons.getIcon(widget.waypoint.destination.type, iconColor),
        subtitle: Text(widget.waypoint.destination.locationID, style: TextStyle(color: widget.next ? Constants.planCurrentColor : Colors.white))),
      const Divider(),
    ]);

  }

}
