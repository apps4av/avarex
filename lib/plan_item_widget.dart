import 'package:avaremp/plan_route.dart';
import 'package:flutter/material.dart';
import 'constants.dart';
import 'destination.dart';

class PlanItemWidget extends StatefulWidget {
  final Waypoint waypoint;
  final bool next;
  final Function onTap;

  // it crashes if not static

  const PlanItemWidget({super.key, required this.waypoint, required this.next, required this.onTap});

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
          leading: TypeIcons.getIcon(widget.waypoint.destination.type, widget.waypoint.airwaySegmentsOnRoute.isEmpty ? Colors.red : Colors.white),
          title: Text(widget.waypoint.destination.locationID, style: TextStyle(color: widget.next ? Constants.planCurrentColor : Colors.white),),
          children: <Widget>[
            Column(
              children: _buildExpandableContent(),
            ),
          ],
        ),
        const Divider()
     ])

     :

     Column(children: [
       ListTile(
         leading: TypeIcons.getIcon(widget.waypoint.destination.type, Colors.white),
         subtitle: Text(widget.waypoint.destination.locationID, style: TextStyle(color: widget.next ? Constants.planCurrentColor : Colors.white)),
         onTap: () {
           widget.onTap();
         }
      ),
       const Divider(),
     ]);
  }

  List<Widget> _buildExpandableContent() {
    List<Widget> columnContent = [];

    for (Destination destination in widget.waypoint.airwaySegmentsOnRoute) {
      columnContent.add(
        ListTile(
          subtitle: Text(destination.locationID, style : TextStyle(color : (destination == widget.waypoint.airwaySegmentsOnRoute[widget.waypoint.currentAirwaySegment] && widget.next) ? Constants.planCurrentColor : Colors.white)),
          leading: TypeIcons.getIcon(widget.waypoint.destination.type, Colors.white),
          onTap: () {
            setState(() {
              widget.waypoint.currentAirwaySegment = widget.waypoint.airwaySegmentsOnRoute.indexOf(destination);
              widget.onTap();// go to this point in airway
            });
          }
        ),
      );
    }
    return columnContent;
  }
}
