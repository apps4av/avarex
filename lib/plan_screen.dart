import 'package:avaremp/constants.dart';
import 'package:avaremp/plan_item_widget.dart';
import 'package:avaremp/plan_line_widget.dart';
import 'package:avaremp/plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});
  @override
  State<StatefulWidget> createState() => PlanScreenState();

}

class PlanScreenState extends State<PlanScreen> {

  @override
  Widget build(BuildContext context) {
    final PlanRoute route = Storage().route;

    double? height = Constants.appbarMaxSize(context);
    double? bottom = Constants.bottomPaddingSize(context);

    // user can rearrange widgets
    return Container(padding: EdgeInsets.fromLTRB(5, height!, 5, bottom),
        child:Stack(
          children:[
            ReorderableListView(
                scrollDirection: Axis.vertical,
                children: <Widget>[
                  ListTile( // header
                    key: Key(Storage().getKey()),
                    leading: const Icon(Icons.summarize_outlined),
                    title: PlanLineWidgetState.getHeading(),
                    subtitle: PlanLineWidgetState.getNullFields()
                  ), // heading for dist, time etc.
                  for(int index = 1; index <= route.length; index++)
                    Dismissible( // able to delete with swipe
                      background: Container(alignment: Alignment.centerRight,child: const Icon(Icons.delete_forever),),
                      key: Key(Storage().getKey()),
                      direction: DismissDirection.endToStart,
                      onDismissed:(direction) {
                        setState(() {
                          route.removeWaypointAt(index - 1);
                        });
                      },
                      child:PlanItemWidget(waypoint: route.getWaypointAt(index - 1), next: route.isCurrent(index - 1), onTap: () {
                        setState(() {
                          Storage().route.setCurrentWaypoint(index - 1);
                        });
                      },),
                    ),
                ],
                onReorder: (int oldIndex, int newIndex) {
                  if(0 == oldIndex || 0 == newIndex) {
                    return; // leaving heading alone
                  }
                  setState(() {
                    if (oldIndex < newIndex) {
                      newIndex -= 1;
                    }
                    route.moveWaypoint(oldIndex - 1, newIndex - 1);
                  }
                );
              }
            ),
          ]
        )
    );
  }
}
