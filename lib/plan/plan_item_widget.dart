import 'plan_line_widget.dart';
import 'package:avaremp/plan/waypoint.dart';
import 'package:avaremp/storage.dart';
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

  /// Name plus the ACTIVE badge, kept inside the tile width. A plain [Row] lets a long procedure name paint past the edge.
  Widget _waypointTitle(String name) {
    final Color primaryColor = Theme.of(context).colorScheme.primary;
    final Color currentColor = Constants.planCurrentColor;
    final Text label = Text(
      name,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        color: widget.current ? currentColor : primaryColor,
      ),
    );
    if (!widget.current) {
      return label;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const double badgeSlot = 72;
        final double nameWidth = constraints.maxWidth.isFinite
            ? (constraints.maxWidth - badgeSlot).clamp(0, constraints.maxWidth).toDouble()
            : 0;
        return Row(
          children: [
            SizedBox(width: nameWidth, child: label),
            const SizedBox(width: 8),
            SizedBox(
              width: badgeSlot - 8,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
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
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Destination.isAirway(widget.waypoint.destination.type) || Destination.isProcedure(widget.waypoint.destination.type)
        ? ExpansionTile(
            leading: DestinationFactory.getIcon(
              widget.waypoint.destination.type,
              widget.waypoint.destinationsOnRoute.isEmpty ? Colors.red : primaryColor,
            ),
            title: _waypointTitle(widget.waypoint.destination.locationID),
            subtitle: Text(
              widget.waypoint.destination.secondaryName ?? widget.waypoint.destination.locationID,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            children: <Widget>[
              Column(children: _buildExpandableContent())
            ],
          )
        : ListTile(
            leading: DestinationFactory.getIcon(widget.waypoint.destination.type, primaryColor),
            title: _waypointTitle(
              widget.waypoint.destination.type == Destination.typeGps
                  ? widget.waypoint.destination.facilityName
                  : widget.waypoint.destination.locationID,
            ),
            subtitle: _altitudeLine(widget.waypoint.destination, null),
            onTap: () {
              widget.onTap();
            },
          );
  }

  Widget _altitudeLine(Destination destination, int? fixIndex) {
    final int planAltitude = Storage().route.altitude;
    return PlanLineWidget(
      destination: destination,
      altitude: widget.waypoint.effectiveAltitude(planAltitude, fixIndex),
      onAltitudeChanged: (int value) {
        widget.waypoint.setAltitudeOnly(fixIndex, value);
        Storage().route.update();
      },
      onAltitudeCleared: () {
        widget.waypoint.clearLegCruise(fixIndex);
        Storage().route.update();
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isCurrentInAirway ? currentColor : primaryColor,
                fontWeight: isCurrentInAirway ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: _altitudeLine(destinations[index], index),
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
