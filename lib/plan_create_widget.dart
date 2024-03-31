import 'package:avaremp/plan_route.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:avaremp/storage.dart';

class PlanCreateWidget extends StatefulWidget {
  const PlanCreateWidget({super.key});

  @override
  State<StatefulWidget> createState() => PlanCreateWidgetState();
}

class PlanCreateWidgetState extends State<PlanCreateWidget> {

  String _route = "";
  bool _getting = false;

  @override
  Widget build(BuildContext context) {

    return Container(padding: const EdgeInsets.all(0),
      child: Column(children: [
        Container(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 0), child: const Text("Create", style: TextStyle(fontWeight: FontWeight.w800),),),
        const Padding(padding: EdgeInsets.all(10)),
        Visibility(visible: _getting, child: const CircularProgressIndicator(),),
        const Padding(padding: EdgeInsets.all(10)),
        TextFormField(
            onChanged: (value)  {
              _route = value;
            },
            decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Route',)),
        const Padding(padding: EdgeInsets.all(10)),
        Row(mainAxisAlignment: MainAxisAlignment.center, children:[
          TextButton(
            onPressed: () {
              if(_getting) {
                return;
              }
              setState(() {_getting = true;});
              PlanRoute.fromLine("New Plan", _route).then((value) {
                  Storage().route.copyFrom(value);
                  Storage().route.setCurrentWaypoint(0);
                  setState(() {_getting = false;});
                  Navigator.pop(context);
              });
            },
            child: const Text("Create As Entered"),),
          const Tooltip(triggerMode: TooltipTriggerMode.tap, message: "Enter all waypoints in Route, separated by spaces.", child: Icon(Icons.info))
        ]),
        const Padding(padding: EdgeInsets.all(10)),
        Row(mainAxisAlignment: MainAxisAlignment.center, children:[
          TextButton(
            onPressed: () {
              if(_getting) {
                return;
              }
              setState(() {_getting = true;});
              PlanRoute.fromPreferred("New Plan", _route, Storage().route.altitude, Storage().route.altitude).then((value) {
                Storage().route.copyFrom(value);
                Storage().route.setCurrentWaypoint(0);
                setState(() {_getting = false;});
                Navigator.pop(context);
              });
            },
            child: const Text("Create IFR Preferred Route"),),
          const Tooltip(triggerMode: TooltipTriggerMode.tap, message: "Enter departure and destination in Route, separated by a space.", child: Icon(Icons.info))
        ]),
        const Padding(padding: EdgeInsets.all(10)),
      ])
    );
  }

}

