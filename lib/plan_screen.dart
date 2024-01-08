import 'package:avaremp/constants.dart';
import 'package:avaremp/plan_item_widget.dart';
import 'package:avaremp/plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});
  @override
  State<StatefulWidget> createState() => PlanScreenState();

}

class PlanScreenState extends State<PlanScreen> {

  Widget makeWaypoint(List<Waypoint> items, int index) {
      return Dismissible( // able to delete with swipe
        background: Container(alignment: Alignment.centerRight,child: const Icon(Icons.delete_forever),),
        key: Key(Storage().getKey()),
        direction: DismissDirection.endToStart,
        onDismissed:(direction) {
          items.removeAt(index);
        },
        child: ListTile(
          title: Text(items[index].destination.locationID),
          subtitle: Text("${items[index].destination.facilityName} ( ${items[index].destination.type} )"),
          dense: true,
          isThreeLine: true,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final PlanRoute route = Storage().route;

    double? height = Constants.appbarMaxSize(context);
    double? bottom = Constants.bottomPaddingSize(context);

    // user can rearrange widgets
    return Container(padding: EdgeInsets.fromLTRB(5, height!, 5, bottom),
        child:Column(
          children:[
            Expanded(flex: 80,
                child: ReorderableListView(
                  scrollDirection: Axis.vertical,
                  children: <Widget>[
                    for(int index = 0; index < route.length; index++)
                      Dismissible( // able to delete with swipe
                        background: Container(alignment: Alignment.centerRight,child: const Icon(Icons.delete_forever),),
                        key: Key(Storage().getKey()),
                        direction: DismissDirection.endToStart,
                        onDismissed:(direction) {
                          setState(() {
                            route.removeWaypointAt(index);
                          });
                        },
                        child: GestureDetector(
                          child:PlanItemWidget(waypoint: route.getWaypointAt(index), next: route.isNext(index)),
                          onLongPress: () {
                            setState(() {
                              Storage().route.setNext(index);
                            });
                          },
                        ),
                    ),
                  ],
                  onReorder: (int oldIndex, int newIndex) {
                    setState(() {
                      if (oldIndex < newIndex) {
                        newIndex -= 1;
                      }
                      route.moveWaypoint(oldIndex, newIndex);
                    }
                  );
                }
              )
            ),
          ]
        )
    );
  }
}
