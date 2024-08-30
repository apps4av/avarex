import 'plan_line_widget.dart';
import 'package:avaremp/plan/waypoint.dart';
import 'package:flutter/material.dart';
import 'package:avaremp/destination/airway.dart';
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
    return Destination.isAirway(widget.waypoint.destination.type) ?

     FutureBuilder(
        future: AirwayLookupFuture(widget.waypoint).getAll(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return _makeContent(snapshot.data);
          }
          else {
            return _makeContent(null);
          }
        }
    )

    :

    Column(children: [
      ListTile(
          leading: DestinationFactory.getIcon(widget.waypoint.destination.type, Theme.of(context).colorScheme.primary),
          title: Text(widget.waypoint.destination.locationID, style: TextStyle(color: widget.current ? Constants.planCurrentColor : Theme.of(context).colorScheme.primary)),
          subtitle: PlanLineWidget(destination: widget.waypoint.destination),
          onTap: () {
            widget.onTap();
          }
      ),
    ]);

  }

  Widget _makeContent(AirwayLookupFuture? future) {

    return Column(children: [
      ExpansionTile(
        leading: DestinationFactory.getIcon(widget.waypoint.destination.type, widget.waypoint.airwayDestinationsOnRoute.isEmpty ? Colors.red : Theme.of(context).colorScheme.primary),
        title: Text(widget.waypoint.destination.locationID, style: TextStyle(color: widget.current ? Constants.planCurrentColor : Theme.of(context).colorScheme.primary),),
        subtitle: Text(future == null || future.lookupAirwaySegments.isEmpty ? "" : future.lookupAirwaySegments[widget.waypoint.currentAirwayDestinationIndex].locationID),
        children: <Widget>[
          Column(children: _buildExpandableContent(future),)
        ],
      ),
    ]);

  }

  List<Widget> _buildExpandableContent(AirwayLookupFuture? future) {
    List<Widget> columnContent = [];

    if(null == future) {
      return [];
    }

    List<Destination> destinations = widget.waypoint.airwayDestinationsOnRoute;

    for (int index = 0; index < destinations.length; index++) {
      columnContent.add(
        ListTile(
          title: Text(future.lookupAirwaySegments[index].locationID, style : TextStyle(color : (destinations[index] == widget.waypoint.airwayDestinationsOnRoute[widget.waypoint.currentAirwayDestinationIndex] && widget.current) ? Constants.planCurrentColor : Theme.of(context).colorScheme.primary)),
          subtitle: PlanLineWidget(destination: future.lookupAirwaySegments[index],),
          leading: DestinationFactory.getIcon(widget.waypoint.destination.type, Theme.of(context).colorScheme.primary),
          onTap: () {
            setState(() {
              widget.waypoint.currentAirwayDestinationIndex = widget.waypoint.airwayDestinationsOnRoute.indexOf(destinations[index]);
              widget.onTap();// go to this point in airway
            });
          }
        ),
      );
    }
    return columnContent;
  }
}

