import 'package:avaremp/plan_lmfs.dart';
import 'package:flutter/material.dart';

class PlanManageWidget extends StatefulWidget {
  const PlanManageWidget({super.key});


  @override
  State<StatefulWidget> createState() => PlanManageWidgetState();
}

class PlanManageWidgetState extends State<PlanManageWidget> {

  Future<LmfsPlanList> getPlans() async {
    LmfsPlanList ret;
    LmfsInterface interface = LmfsInterface();
    ret = await interface.getFlightPlans();
    return ret;
  }

  Widget _makeContent(LmfsPlanList? plans) {

    if(null == plans) {
      return const Column(
          children: [
            Flexible(flex: 1, child: Text("Manage FAA Plans", style: TextStyle(fontWeight: FontWeight.w800),)),
            Padding(padding: EdgeInsets.all(10)),
            CircularProgressIndicator()
          ]
      );
    }

    List<LmfsPlanListPlan> items = plans.getPlans();

    return Column(
        children: [
          const Flexible(flex: 1, child: Text("Manage FAA Plans", style: TextStyle(fontWeight: FontWeight.w800),)),
          const Padding(padding: EdgeInsets.all(10)),
          Flexible(flex: 5, child: ListView.separated(
            itemCount: items.length,
            padding: const EdgeInsets.all(5),
            itemBuilder: (context, index) {
              final LmfsPlanListPlan item = items[index];
              return ListTile(
                title: Text("${item.departure} -> ${item.destination}"),
                leading: Text(item.aircraftId),
                subtitle: Text(item.currentState),
                trailing: PopupMenuButton(
                  itemBuilder: (BuildContext context)  => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      child: const Text('Activate'),
                      onTap: () {
                      },
                    ),
                    PopupMenuItem<String>(
                      child: const Text('Cancel'),
                      onTap: () {
                        LmfsInterface interface = LmfsInterface();
                        interface.cancelFlightPlan(item.id).then((value) => setState(() {
                          // this will refresh state of plans
                        }));
                      },
                    ),
                    PopupMenuItem<String>(
                      child: const Text('Close'),
                      onTap: () {
                      },
                    ),
                  ],),
              );
            },
            separatorBuilder: (context, index) {
              return const Divider();
            },
          ))
        ]);
  }


  @override
  Widget build(BuildContext context) {

    // get all aircraft since it is important to be able to change them quickly
    return FutureBuilder(
        future: getPlans(),
        builder: (context, snapshot) {
          return _makeContent(snapshot.data);
        });
  }

}

