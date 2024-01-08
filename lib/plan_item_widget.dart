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

    // different tiles for airways
    return Destination.isAirway(widget.waypoint.destination.type) ?

      Column(children: [
        ExpansionTile(
          leading: TypeIcons.getIcon(widget.waypoint.destination.type, widget.waypoint.adjustedPoints.isEmpty ? Colors.red : Colors.white),
          title: Text(widget.waypoint.destination.locationID, style: TextStyle(color: widget.next ? Constants.planCurrentColor : Colors.white),),
          children: <Widget>[
            Column(
              children: mBuildExpandableContent(),
            ),
          ],
        ),
        const Divider()
     ])

     :

     Column(children: [
       ListTile(
         leading: TypeIcons.getIcon(widget.waypoint.destination.type, Colors.white),
         title: Text(widget.waypoint.destination.locationID, style: TextStyle(color: widget.next ? Constants.planCurrentColor : Colors.white))),
       const Divider(),
     ]);
  }

  List<Widget> mBuildExpandableContent() {
    List<Widget> columnContent = [];

    for (Destination destination in widget.waypoint.adjustedPoints) {
      columnContent.add(
        ListTile(
          title: Text(destination.locationID, style : TextStyle(color : (destination == widget.waypoint.adjustedPoints[widget.waypoint.next] && widget.next) ? Constants.planCurrentColor : Colors.white)),
          leading: TypeIcons.getIcon(widget.waypoint.destination.type, Colors.white),
          onLongPress: () {
            setState(() {
              widget.waypoint.next = widget.waypoint.adjustedPoints.indexOf(destination); // go to this point in airway
            });
          }
        ),
      );
    }
    return columnContent;
  }

}
