import 'package:avaremp/plan_route.dart';
import 'package:flutter/material.dart';
import 'package:avaremp/storage.dart';

class PlanCreateWidget extends StatefulWidget {
  const PlanCreateWidget({super.key});


  @override
  State<StatefulWidget> createState() => PlanCreateWidgetState();
}

class PlanCreateWidgetState extends State<PlanCreateWidget> {


  String _route = "";
  String _minAltitude = Storage().route.altitude;
  String _maxAltitude = Storage().route.altitude;

  @override
  Widget build(BuildContext context) {

    return Container(padding: const EdgeInsets.all(0),
      child: Column(children: [
        Expanded(
          flex: 1,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 0), child: const Text("Create", style: TextStyle(fontWeight: FontWeight.w800),),)),
        Expanded(
          flex: 3,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
            child: Row(children:[
              Expanded(
                  flex: 9,
                  child: TextFormField(
                      onChanged: (value)  {
                        _route = value;
                      },
                      decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Route',)
                  )
              ),
              Expanded(
                  flex: 2,
                  child: TextButton(
                    onPressed: () {
                      PlanRoute.fromLine("New Plan", _route).then((value) {
                          Storage().route.copyFrom(value);
                          Storage().route.setCurrentWaypoint(0);
                          Navigator.pop(context);
                      });
                    },
                    child: const Text("Create"),)
              ),
            ]
            )
          )
        ),
        Expanded(
            flex: 3,
            child: Container(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                child: Row(children:[
                  Expanded(
                      flex: 5,
                      child: TextFormField(
                          onChanged: (value)  {
                            _route = value;
                          },
                          decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Preferred IFR Route',)
                      )
                  ),
                  const Padding(padding: EdgeInsets.all(10)),
                  Expanded(
                      flex: 2,
                      child: TextFormField(
                          onChanged: (value)  {
                            _minAltitude = value;
                          },
                          decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Min. Alt.',)
                      )
                  ),
                  const Padding(padding: EdgeInsets.all(10)),
                  Expanded(
                      flex: 2,
                      child: TextFormField(
                          onChanged: (value)  {
                            _maxAltitude = value;
                          },
                          decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Max. Alt.',)
                      )
                  ),
                  Expanded(
                      flex: 2,
                      child: TextButton(
                        onPressed: () {
                          PlanRoute.fromPreferred("New Plan", _route, _minAltitude, _maxAltitude).then((value) {
                            Storage().route.copyFrom(value);
                            Storage().route.setCurrentWaypoint(0);
                            Navigator.pop(context);
                          });
                        },
                        child: const Text("Create"),)
                  )
                ]
                )
            )
        )

      ])
    );
  }

}

