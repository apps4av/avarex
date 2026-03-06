import 'plan_line_widget.dart';
import 'package:avaremp/plan/waypoint.dart';
import 'package:flutter/material.dart';
import 'package:avaremp/constants.dart';
import 'package:avaremp/destination/destination.dart';

class PlanItemWidget extends StatefulWidget {
  final Waypoint waypoint;
  final bool current;
  final Function onTap;

  const PlanItemWidget({super.key, required this.waypoint, required this.current, required this.onTap});

  @override
  State<StatefulWidget> createState() => PlanItemWidgetState();
}

class PlanItemWidgetState extends State<PlanItemWidget> {

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final currentColor = Constants.planCurrentColor;

    return Destination.isAirway(widget.waypoint.destination.type) || Destination.isProcedure(widget.waypoint.destination.type)
        ? ExpansionTile(
            leading: DestinationFactory.getIcon(
              widget.waypoint.destination.type,
              widget.waypoint.destinationsOnRoute.isEmpty ? Colors.red : primaryColor,
            ),
            title: Row(
              children: [
                Text(
                  widget.waypoint.destination.locationID,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: widget.current ? currentColor : primaryColor,
                  ),
                ),
                if (widget.current)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: currentColor.withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        "ACTIVE",
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: currentColor),
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Text(
              widget.waypoint.destination.secondaryName ?? widget.waypoint.destination.locationID,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            children: <Widget>[
              Column(children: _buildExpandableContent())
            ],
          )
        : ListTile(
            leading: DestinationFactory.getIcon(widget.waypoint.destination.type, primaryColor),
            title: Row(
              children: [
                Text(
                  widget.waypoint.destination.type == Destination.typeGps
                      ? widget.waypoint.destination.facilityName
                      : widget.waypoint.destination.locationID,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: widget.current ? currentColor : primaryColor,
                  ),
                ),
                if (widget.current)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: currentColor.withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        "ACTIVE",
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: currentColor),
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: PlanLineWidget(destination: widget.waypoint.destination),
            onTap: () {
              widget.onTap();
            },
          );
  }

  List<Widget> _buildExpandableContent() {
    List<Widget> columnContent = [];
    List<Destination> destinations = widget.waypoint.destinationsOnRoute;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final currentColor = Constants.planCurrentColor;

    for (int index = 0; index < destinations.length; index++) {
      final isCurrentInAirway = destinations[index] == widget.waypoint.destinationsOnRoute[widget.waypoint.currentDestinationIndex] && widget.current;
      
      columnContent.add(
        Container(
          color: isCurrentInAirway ? currentColor.withAlpha(20) : null,
          child: ListTile(
            title: Text(
              destinations[index].secondaryName ?? destinations[index].locationID,
              style: TextStyle(
                color: isCurrentInAirway ? currentColor : primaryColor,
                fontWeight: isCurrentInAirway ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: PlanLineWidget(destination: destinations[index]),
            leading: DestinationFactory.getIcon(widget.waypoint.destination.type, primaryColor),
            dense: true,
            onTap: () {
              setState(() {
                widget.waypoint.currentDestinationIndex = widget.waypoint.destinationsOnRoute.indexOf(destinations[index]);
                widget.onTap();
              });
            },
          ),
        ),
      );
    }
    return columnContent;
  }
}
