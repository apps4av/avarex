import 'plan_line_widget.dart';
import 'package:avaremp/plan/waypoint.dart';
import 'package:flutter/material.dart';
import 'package:avaremp/constants.dart';
import 'package:avaremp/destination/destination.dart';

class PlanItemWidget extends StatefulWidget {
  final Waypoint waypoint;
  final bool current;
  final Function onTap;

  // it crashes if not static

  const PlanItemWidget({super.key, required this.waypoint, required this.current, required this.onTap});

  @override
  State<StatefulWidget> createState() => PlanItemWidgetState();
}

class PlanItemWidgetState extends State<PlanItemWidget> {

  @override
  Widget build(BuildContext context) {

    // different tiles for airways
    return Destination.isAirway(widget.waypoint.destination.type) || Destination.isProcedure(widget.waypoint.destination.type) ?

    Column(children: [
      ExpansionTile(
        leading: DestinationFactory.getIcon(widget.waypoint.destination.type, widget.waypoint.destinationsOnRoute.isEmpty ? Colors.red : Theme.of(context).colorScheme.primary),
        title: Text(widget.waypoint.destination.locationID, style: TextStyle(color: widget.current ? Constants.planCurrentColor : Theme.of(context).colorScheme.primary),),
        subtitle: Text(widget.waypoint.destination.secondaryName != null ? widget.waypoint.destination.secondaryName! : widget.waypoint.destination.locationID),
        children: <Widget>[
          Column(children: _buildExpandableContent(),)
        ],
      ),
    ])

    :

    Column(children: [
      ListTile(
          leading: DestinationFactory.getIcon(widget.waypoint.destination.type, Theme.of(context).colorScheme.primary),
          // Do not clobber plan with GPS sexagesimal
          title: Text(widget.waypoint.destination.type == Destination.typeGps ? widget.waypoint.destination.facilityName : widget.waypoint.destination.locationID, style: TextStyle(color: widget.current ? Constants.planCurrentColor : Theme.of(context).colorScheme.primary)),
          subtitle: PlanLineWidget(destination: widget.waypoint.destination),
          onTap: () {
            widget.onTap();
          }
      ),
    ]);

  }


  List<Widget> _buildExpandableContent() {
    List<Widget> columnContent = [];

    List<Destination> destinations = widget.waypoint.destinationsOnRoute;

    for (int index = 0; index < destinations.length; index++) {
      columnContent.add(
        ListTile(
          title: Text(destinations[index].secondaryName != null ? destinations[index].secondaryName! : destinations[index].locationID, style : TextStyle(color : (destinations[index] == widget.waypoint.destinationsOnRoute[widget.waypoint.currentDestinationIndex] && widget.current) ? Constants.planCurrentColor : Theme.of(context).colorScheme.primary)),
          subtitle: PlanLineWidget(destination: destinations[index],),
          leading: DestinationFactory.getIcon(widget.waypoint.destination.type, Theme.of(context).colorScheme.primary),
          onTap: () {
            setState(() {
              widget.waypoint.currentDestinationIndex = widget.waypoint.destinationsOnRoute.indexOf(destinations[index]);
              widget.onTap();// go to this point in airway
            });
          }
        ),
      );
    }
    return columnContent;
  }
}

