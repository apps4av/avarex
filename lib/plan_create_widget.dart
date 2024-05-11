import 'package:avaremp/plan_lmfs.dart';
import 'package:avaremp/plan_route.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/widgets.dart';

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
        Container(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 0), child: const Text("Create", style: TextStyle(fontWeight: FontWeight.w800),),),
        const Padding(padding: EdgeInsets.all(10)),
        Visibility(visible: _getting, child: const CircularProgressIndicator(),),
        const Padding(padding: EdgeInsets.all(10)),
        Container(padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child:Row(children:[
            Flexible(
              flex: 6,
              child: TextFormField(
                onChanged: (value)  {
                  _route = value;
                },
                initialValue: _route,
                decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Route',)
              )
            ),
            Flexible(
                flex: 1,
                child: Tooltip(triggerMode: TooltipTriggerMode.tap, message: "Create As Entered: Enter all the waypoints separated by spaces in the Route box.\n\nCreate IFR Preferred Route/Show IFR ATC Routes: Enter the departure and the destination separated by a space in the Route box. Using 1800wxbrief.com account '${Storage().settings.getEmail()}'", child: Icon(Icons.info))
            ),
            Flexible(
              flex: 1,
              child:PopupMenuButton(
                tooltip: "",
                itemBuilder: (BuildContext context)  => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    child: const Text('Create As Entered'),
                    onTap: () {
                      if(_getting) {
                        return;
                      }
                      Storage().settings.setLastRouteEntry(_route);
                      setState(() {_getting = true;});
                      PlanRoute.fromLine("New Plan", _route).then((value) {
                        Storage().route.copyFrom(value);
                        Storage().route.setCurrentWaypoint(0);
                        setState(() {_getting = false;});
                        Navigator.pop(context);
                      });
                    },
                  ),
                  PopupMenuItem<String>(
                    child: const Text('Create IFR Preferred Route'),
                    onTap: () {
                      if(_getting) {
                        return;
                      }
                      Storage().settings.setLastRouteEntry(_route);
                      setState(() {_getting = true;});
                      PlanRoute.fromPreferred("New Plan", _route, Storage().route.altitude, Storage().route.altitude).then((value) {
                        Storage().route.copyFrom(value);
                        Storage().route.setCurrentWaypoint(0);
                        setState(() {_getting = false;});
                        Navigator.pop(context);
                      });
                    },
                  ),
                  PopupMenuItem<String>(
                    child: const Text('Show IFR ATC Routes'),
                    onTap: () {
                      if(_getting) {
                        return;
                      }
                      Storage().settings.setLastRouteEntry(_route);
                      setState(() {_getting = true;});
                      LmfsInterface interface = LmfsInterface();
                      List<String> wps = _route.split(" ");
                      if(wps.length < 2) {
                        setState(() {_getting = false;});
                        return;
                      }
                      interface.getRoute(wps[0], wps[1]).then((value) {
                        setState(() {_getting = false;});
                        // create a dialog then show routes in a list
                        showDialog<String>(
                            context: context,
                            builder: (BuildContext context) => Dialog.fullscreen(
                            child: Stack(
                                children:[
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
                                  Align(alignment: Alignment.topRight, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 36, color: Colors.white)))
                                ])
                            )
                        );
                      });
                    },
                  ),
                ],
              ),
            ),
          ])
        ),
      ])
    );
  }
}

