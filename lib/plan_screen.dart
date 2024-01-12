import 'package:avaremp/constants.dart';
import 'package:avaremp/plan_item_widget.dart';
import 'package:avaremp/plan_line_widget.dart';
import 'package:avaremp/plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/user_database_helper.dart';
import 'package:flutter/material.dart';

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});
  @override
  State<StatefulWidget> createState() => PlanScreenState();

}

class PlanScreenState extends State<PlanScreen> {

  String _name = "";

  Widget _makeContent(List<PlanRoute> items) {

    return StatefulBuilder(builder: (BuildContext context, StateSetter setState1) {
      return Container(padding: const EdgeInsets.all(5),
          child: Column(children: [
            const Expanded(
              flex: 1,
              child: Icon(Icons.drag_handle)),
            Expanded(
              flex: 4,
              child: Container(
                padding: const EdgeInsets.fromLTRB(50, 0, 50, 0),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: TextFormField(
                          onChanged: (value)  {
                            _name = value;
                          },
                          decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Plan Name',)
                        )
                      ),
                      Expanded(
                        flex: 2,
                        child: TextButton(
                          onPressed: () {
                            setState1(() {
                              Storage().route.name = _name;
                              items.insert(0, Storage().route);
                            });
                            UserDatabaseHelper.db.addPlan(_name, Storage().route);
                          },
                          child: const Text("Save")
                        )
                      )
                    ]
                )
              )
            ),
            Expanded(
              flex: 16,
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                return ListTile(
                  title: Text(items[index].name),
                  subtitle: Text(items[index].toString()),
                  trailing: PopupMenuButton(
                    itemBuilder: (BuildContext context)  => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      child: const Text('Load'),
                      onTap: () {
                        setState1(() {
                          Storage().route = items[index];
                        });
                        setState(() {
                          Storage().route = items[index];
                        });
                      },
                    ),
                    PopupMenuItem<String>(
                      child: const Text('Delete'),
                      onTap: () {
                        UserDatabaseHelper.db.deletePlan(items[index].name);
                        setState1(() {
                          items.removeAt(index);
                        });
                      },
                    ),
                  ],),
                );
              },
            )),
          ],
        )
      );
    });
  }

  Future<bool> _showPlans(BuildContext context) async {
    bool? exitResult = await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return FutureBuilder(
          future: UserDatabaseHelper.db.getPlans(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              return _makeContent(snapshot.data!);
            }
            return Container();
          },
        );
      },
    );
    return exitResult ?? false;
  }


  @override
  Widget build(BuildContext context) {
    final PlanRoute route = Storage().route;

    double? height = Constants.appbarMaxSize(context);
    double? bottom = Constants.bottomPaddingSize(context);

    // user can rearrange widgets
    return Container(padding: EdgeInsets.fromLTRB(5, height! + 10, 5, bottom),
      child: ReorderableListView(
          scrollDirection: Axis.vertical,
          children: <Widget>[
            ListTile( // header
              key: Key(Storage().getKey()),
              leading: const Icon(Icons.summarize_outlined),
              title: PlanLineWidgetState.getHeading(),
              tileColor: Constants.appBarBackgroundColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),),
              subtitle: PlanLineWidgetState.getNullFields(),
              onTap: () {_showPlans(context);},
              onLongPress: () {},
            ), // heading for dist, time etc.
            for(int index = 1; index <= route.length; index++)
              Dismissible( // able to delete with swipe
                background: Container(alignment:
                Alignment.centerRight,child: const Icon(Icons.delete_forever),),
                key: Key(Storage().getKey()),
                direction: DismissDirection.endToStart,
                onDismissed:(direction) {
                  setState(() {
                    route.removeWaypointAt(index - 1);
                  });
                },
                child:PlanItemWidget(waypoint:
                route.getWaypointAt(index - 1), next: route.isCurrent(index - 1),
                  onTap: () {
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
    );
  }
}
