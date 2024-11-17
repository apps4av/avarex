
import 'plan_lmfs.dart';
import 'plan_route.dart';
import 'package:flutter/material.dart';
import 'package:avaremp/storage.dart';

class PlanCreateWidget extends StatefulWidget {
  const PlanCreateWidget({super.key});

  @override
  State<StatefulWidget> createState() => PlanCreateWidgetState();
}

class PlanCreateWidgetState extends State<PlanCreateWidget> {

  String _route = Storage().settings.getLastRouteEntry();
  bool _getting = false;

  @override
  Widget build(BuildContext context) {

    return Container(padding: const EdgeInsets.all(0),
      child: Column(children: [
          Expanded(flex: 1,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 0), child: const Text("Create", style: TextStyle(fontWeight: FontWeight.w800),),
            )
          ),
          Visibility(visible: _getting, child: const CircularProgressIndicator(),),
          Expanded(flex: 1,
            child: Container(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Row(children:[
                  Flexible(
                    flex: 6,
                    child: TextFormField(
                      onChanged: (value)  {
                        _route = value.toUpperCase(); // all input is upper case
                      },
                      initialValue: _route.trim(),
                      decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Route',)
                    )
                  ),
                  Flexible(
                      flex: 1,
                      child: Tooltip(showDuration: const Duration(seconds: 30), triggerMode: TooltipTriggerMode.tap, message: "Create As Entered: Enter all the waypoints separated by spaces in the Route box.\nCreate IFR Preferred Route/Show IFR ATC Routes: Enter the departure and the destination separated by a space in the Route box.\n\nUsing 1800wxbrief.com account \"${Storage().settings.getEmail()}\".", child: const Icon(Icons.info))
                  ),
                ])
            )
          ),
          const Padding(padding: EdgeInsets.fromLTRB(0, 0, 0, 10)),
          Expanded(flex: 5,
              child: Column(children:[
              TextButton(
                child: const Text('Create As Entered'),
                onPressed: () {
                  if(_getting) {
                    return;
                  }
                  String input = _route.trim();

                  Storage().settings.setLastRouteEntry(input);
                  setState(() {_getting = true;});
                  PlanRoute.fromLine("New Plan", input).then((value) {
                    Storage().route.copyFrom(value);
                    Storage().route.setCurrentWaypoint(0);
                    setState(() {_getting = false; Navigator.pop(context);});
                  });
                },
              ),
              TextButton(
                child: const Text('Create IFR Preferred Route'),
                onPressed: () {
                  String input = _route.trim();
                  if(_getting) {
                    return;
                  }
                  Storage().settings.setLastRouteEntry(input);
                  setState(() {_getting = true;});
                  PlanRoute.fromPreferred("New Plan", input, Storage().route.altitude, Storage().route.altitude).then((value) {
                    Storage().route.copyFrom(value);
                    Storage().route.setCurrentWaypoint(0);
                    setState(() {_getting = false; Navigator.pop(context);});
                  });
                },
              ),
              TextButton(
                child: const Text('Show IFR ATC Routes'),
                onPressed: () {
                  if(_getting) {
                    return;
                  }
                  String input = _route.trim();

                  Storage().settings.setLastRouteEntry(input);
                  setState(() {_getting = true;});
                  LmfsInterface interface = LmfsInterface();
                  List<String> wps = input.split(" ");
                  if(wps.length < 2) {
                    setState(() {_getting = false;});
                    return;
                  }
                  interface.getRoute(wps[0], wps[1]).then((value) {
                    setState(() {
                      _getting = false;
                      // create a dialog then show routes in a list
                      showDialog<String>(
                        context: context,
                        builder: (BuildContext context) => Dialog.fullscreen(
                        child: Stack(children:[
                          Padding(padding: const EdgeInsets.fromLTRB(40, 40, 50, 0),
                            child: ListView.builder(
                              itemCount: value.length,
                              itemBuilder: (context, index) {
                                return ListTile(
                                  leading: const Icon(Icons.route),
                                  subtitle: Text("Last Departure at ${value[index].lastDepartureTime.toString().substring(0, 16)}"),
                                  title: SelectableText(value[index].route),);
                              })
                          ),
                          Align(alignment: Alignment.topRight,
                            child: IconButton(
                              onPressed: () =>
                                setState(() {
                                  Navigator.pop(context);
                                }),
                                icon: const Icon(Icons.close, size: 36)))
                        ])
                      ));
                    });
                  });
                }),
            ])
          ),
        ]
      )
    );
  }
}

