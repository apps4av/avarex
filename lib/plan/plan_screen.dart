import 'package:auto_size_text/auto_size_text.dart';
import 'package:avaremp/constants.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/destination/destination_calculations.dart';
import 'package:flutter/services.dart';
import 'package:toastification/toastification.dart';
import 'plan_item_widget.dart';
import 'plan_line_widget.dart';
import 'plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:avaremp/data/altitude_profile.dart';

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});
  @override
  State<StatefulWidget> createState() => PlanScreenState();
}

class PlanScreenState extends State<PlanScreen> {


  @override
  Widget build(BuildContext context) {
    final PlanRoute route = Storage().route;

    double height = 0;
    double bottom = Constants.bottomPaddingSize(context);

    // user can rearrange widgets
    return Container(padding: EdgeInsets.fromLTRB(5, height + 10, 5, bottom),
      child: Stack(children:[
        Column(
          children: [
            Expanded(flex: 1,
              child: ValueListenableBuilder<int>( // update in plan change
                valueListenable: route.change,
                builder: (context, value, _) {
                  return ListTile( // header
                    key: Key(Storage().getKey()),
                    leading: const Icon(Icons.add),
                    title: PlanLineWidgetState.getHeading(),
                    subtitle: PlanLineWidgetState.getFieldsFromCalculations(Storage().route.totalCalculations));
                }
              )
            ), // heading for dist, time etc.
            Expanded(flex: 5, child: ReorderableListView(
              scrollDirection: Axis.vertical,
              buildDefaultDragHandles: false,
              children: <Widget>[
                for(int index = 0; index < route.length; index++)
                ReorderableDelayedDragStartListener(
                  index: index,
                  key: Key(index.toString()),
                  child: GestureDetector(child:
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
                  ))),
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
              Expanded(flex: 1, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child:Row(
                children:[ // header
                  TextButton(
                    onPressed: () async {
                      await Navigator.pushNamed(context, "/plan_actions");
                      setState(() {}); // to update this screen
                    },
                    child: const Text("Actions"),),
                  Padding(padding: const EdgeInsets.all(5), child:SizedBox(width: Constants.screenWidth(context) / 10, child: TextFormField(
                      keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                      onChanged: (value) {
                        double? pValue = double.tryParse(value);
                        Storage().settings.setTas(pValue ?? Storage().settings.getTas());
                      },
                      controller: TextEditingController()..text = Storage().settings.getTas().round().toString(),
                      decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: "ASpd")
                  ))),
                  Padding(padding: const EdgeInsets.all(5), child: SizedBox(width: Constants.screenWidth(context) / 10, child: TextFormField(
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    onChanged: (value) {
                      double? pValue = double.tryParse(value);
                      Storage().settings.setFuelBurn(pValue ?? Storage().settings.getFuelBurn());
                    },
                    controller: TextEditingController()..text = Storage().settings.getFuelBurn().toString(),
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: "GPH")
                  ))),
                  Padding(padding: const EdgeInsets.all(5), child: SizedBox(width: Constants.screenWidth(context) / 10, child: TextFormField(
                      keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                      onChanged: (value) {
                        int? pValue = int.tryParse(value);
                        pValue ??= 3000;
                        Storage().route.altitude = pValue.toString();
                      },
                      controller: TextEditingController()..text = Storage().route.altitude,
                      decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: "Alt")
                  ))),

                  IconButton(icon: const Icon(Icons.local_gas_station_rounded), onPressed: () => showDialog(context: context, builder: (BuildContext context) => Dialog.fullscreen(
                      child: _makeNavLog()
                  ))),
                ]
              )
            ))
          ]
        )
      ]
      ),
    );
  }

  Widget _makeNavLog() {
    Widget w = FutureBuilder(
      future: AltitudeProfile.getAltitudeProfile(Storage().route.getPathNextHighResolution()),
      builder: (BuildContext context, var snapshot) {
        if(snapshot.hasData) {
          // draw the altitude profile
          return Padding(padding: const EdgeInsets.fromLTRB(10, 5, 10, 0), child:SizedBox(width: Constants.screenWidth(context), height: Constants.screenHeight(context) / 4, child:AltitudeProfile.makeChart(context, snapshot.data!)));
        }
        return const Center(child: CircularProgressIndicator());
      }
    );

    List<Widget> values = [];
    values.addAll(DestinationCalculations.labels.map((String s) =>
        Padding(padding: const EdgeInsets.all(3), child: AutoSizeText(s, minFontSize: 4, style: const TextStyle(fontWeight: FontWeight.bold)))));

    for (Destination d in Storage().route.getAllDestinations()) {
      if(d.calculations == null) {
        continue;
      }
      values.addAll(d.calculations!.getLog().map((String s) =>
          Padding(padding: const EdgeInsets.all(3), child: AutoSizeText(s, minFontSize: 4, ))));
    }

    if(Storage().route.totalCalculations != null) {
      List<String> total = Storage().route.totalCalculations!.getLog();
      // blank out total fields that do not make sense
      total[DestinationCalculations.labels.indexOf("FM")] =
        total[DestinationCalculations.labels.indexOf("TO")] =
        total[DestinationCalculations.labels.indexOf("AL")] =
        total[DestinationCalculations.labels.indexOf("TC")] =
        total[DestinationCalculations.labels.indexOf("VR")] =
        total[DestinationCalculations.labels.indexOf("MC")] =
        total[DestinationCalculations.labels.indexOf("WD")] =
        total[DestinationCalculations.labels.indexOf("CA")] =
        total[DestinationCalculations.labels.indexOf("MH")] =
        total[DestinationCalculations.labels.indexOf("GS")] = "";
      values.addAll(total.map((String s) =>
          Padding(padding: const EdgeInsets.all(3), child: AutoSizeText(s, minFontSize: 4, style: const TextStyle(fontWeight: FontWeight.bold)))));
    }

    Widget grid = GridView.count(
      crossAxisCount: DestinationCalculations.columns,
      children: values,
    );

    return Scaffold(body:
      Padding(padding: const EdgeInsets.fromLTRB(5, 48, 5, 5), child: Column(children:[Expanded(flex: 4, child:grid), Expanded(flex:1, child: w)])),
      appBar: AppBar(title: const Text("Nav Log"),
        actions: <Widget>[
          Padding(padding: const EdgeInsets.all(5), child: TextButton(child: const Text("Copy"), onPressed: () {
            Clipboard.setData(ClipboardData(text: Storage().route.toString()));
            Toastification().show(context: context, description: const Text("Copied plan to Clipboard"), autoCloseDuration: const Duration(seconds: 3), icon: const Icon(Icons.info));
          },),)
        ])
    );
  }
}

