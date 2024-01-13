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
  List<String> _currentItems = [];

  Widget _makeContent() {

    return StatefulBuilder(builder: (BuildContext context, StateSetter setState1) {
      return Container(padding: const EdgeInsets.all(5),
          child: Column(children: [
            Expanded(
              flex: 2,
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
                              _currentItems.insert(0, Storage().route.name);
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
                itemCount: _currentItems.length,
                itemBuilder: (context, index) {
                return ListTile(
                  title: Text(_currentItems[index].toString()),
                  trailing: PopupMenuButton(
                    itemBuilder: (BuildContext context)  => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      child: const Text('Load'),
                      onTap: () {
                        re() async {
                          PlanRoute route = await UserDatabaseHelper.db.getPlan(_currentItems[index], false);
                          setState1(() {
                            Storage().route = route;
                          });
                          setState(() {
                            Storage().route = route;
                          });
                        }
                        re();
                        Navigator.pop(context);
                      },
                    ),
                      PopupMenuItem<String>(
                        child: const Text('Load Reversed'),
                        onTap: () {
                          re() async {
                            PlanRoute route = await UserDatabaseHelper.db.getPlan(_currentItems[index], true);
                            setState1(() {
                              Storage().route = route;
                            });
                            setState(() {
                              Storage().route = route;
                            });
                          }
                          re();
                          Navigator.pop(context);
                        },
                      ),
                    PopupMenuItem<String>(
                      child: const Text('Delete'),
                      onTap: () {
                        UserDatabaseHelper.db.deletePlan(_currentItems[index]);
                        setState1(() {
                          _currentItems.removeAt(index);
                        });
                      },
                    ),
                  ],),
                );
              },
            )),
            Expanded(
                flex: 2,
                child: Container()),
          ],
        )
      );
    });
  }

  Future<bool> _showPlans(BuildContext context) async {
    bool? exitResult = await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return FutureBuilder(
          future: UserDatabaseHelper.db.getPlans(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              _currentItems = snapshot.data == null ? _currentItems : snapshot.data!;
            }
            return _makeContent();
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
      child: Stack(children:[
        Column(
          children: [
            Expanded(flex: 1, child: ListTile( // header
              key: Key(Storage().getKey()),
              leading: const Icon(Icons.summarize_outlined),
              title: PlanLineWidgetState.getHeading(),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),),
              subtitle: PlanLineWidgetState.getNullFields(),
            )), // heading for dist, time etc.
            Expanded(flex: 5, child: ReorderableListView(
              scrollDirection: Axis.vertical,
              children: <Widget>[
                for(int index = 0; index < route.length; index++)
                  Dismissible( // able to delete with swipe
                    background: Container(alignment:
                    Alignment.centerRight,child: const Icon(Icons.delete_forever),),
                    key: Key(Storage().getKey()),
                    direction: DismissDirection.endToStart,
                    onDismissed:(direction) {
                      setState(() {
                        route.removeWaypointAt(index);
                      });
                    },
                    child: ValueListenableBuilder<int>( // update in plan change
                      valueListenable: route.change,
                      builder: (context, value, _) {
                        return PlanItemWidget(
                          waypoint: route.getWaypointAt(index),
                          current: route.isCurrent(index),
                          onTap: () {
                            setState(() {
                              Storage().route.setCurrentWaypoint(index);
                            });
                          },
                        );
                     },
                  )
                ),
              ],
              onReorder: (int oldIndex, int newIndex) {
                setState(() {
                  if (oldIndex < newIndex) {
                    newIndex -= 1;
                  }
                  route.moveWaypoint(oldIndex, newIndex);
                });
              })
            ),
          ]
        ),
        Align(
            alignment: Alignment.bottomCenter,
            child: IconButton(icon: const Icon(Icons.horizontal_rule),
              onPressed: () { _showPlans(context); },)),
        Align(
            alignment: Alignment.bottomRight,
            child: TextButton(onPressed: () {
              Storage().route.advance();
              }, child: const Text("Next")))
      ])
    );
  }
}
