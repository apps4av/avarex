import 'package:auto_size_text/auto_size_text.dart';
import 'package:avaremp/constants.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/destination/destination_calculations.dart';
import 'package:avaremp/utils/toast.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/services.dart';
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
                        Storage().route.altitude = pValue;
                      },
                      controller: TextEditingController()..text = Storage().route.altitude.toString(),
                      decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: "Alt")
                  ))),

                  DropdownButtonHideUnderline(
                      child:DropdownButton2<String>(
                        isDense: true,// plate selection
                        buttonStyleData: ButtonStyleData(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.transparent),
                        ),
                        dropdownStyleData: DropdownStyleData(
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                        ),
                        isExpanded: false,
                        value: "${Storage().route.fore.toString().padLeft(2, "0")}H",
                        items: ["06H", "12H", "24H"].map((String item) {
                          return DropdownMenuItem<String>(
                              value: item,
                              child: Text(item)
                          );
                        }).toList(),
                        onChanged: (value) {
                          value ??= ["06H", "12H", "24H"][0];
                          setState(() {
                            Storage().route.fore = int.parse(value!.substring(0, 2));
                          });
                        },
                      )
                  ),
                  IconButton(icon: const Icon(Icons.local_gas_station_rounded), tooltip: "See navigation log and terrain en route", onPressed: () => showDialog(context: context, builder: (BuildContext context) => Dialog.fullscreen(
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
          return Padding(padding: const EdgeInsets.fromLTRB(10, 5, 10, 0), child:SizedBox(width: Constants.screenWidth(context), height: Constants.screenHeight(context) / 4, child: makeChart(context, snapshot.data!)));
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
      Padding(padding: const EdgeInsets.fromLTRB(5, 48, 5, 5), child: Column(children:[Expanded(flex: 4, child:grid),             const Row( // nearby destinations
          children: <Widget>[
            Expanded(flex: 1, child: Divider()),
            Text("Terrain en route", style: TextStyle(fontSize: 10)),
            Expanded(flex: 16, child: Divider()),
          ]
      ),
           Expanded(flex:1, child: w)])),
      appBar: AppBar(title: const Text("Navigation Log"),
        actions: <Widget>[
          Padding(padding: const EdgeInsets.all(5), child: IconButton(icon: const Icon(Icons.copy), tooltip: "Copy plan to clipboard", onPressed: () {
            Clipboard.setData(ClipboardData(text: Storage().route.toString()));
            Toast.showToast(context, "Copied plan to Clipboard", null, 3);
          },),)
        ])
    );
  }

  Widget makeChart(BuildContext context, List<double> data) {
    return CustomPaint(painter: AltitudePainter(context, data),);
  }

}


class AltitudePainter extends CustomPainter {

  final BuildContext context;
  final List<double> data;
  double maxAltitude = 0;
  double minAltitude = 0;
  final double altitudeOfPlan = Storage().route.altitude.toDouble();
  List<Destination> destinations = Storage().route.getNextDestinations();
  int length = 0;
  final _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round
    ..color = Colors.green;

  AltitudePainter(this.context, this.data) {
    if(data.isEmpty) {
      return;
    }
    maxAltitude = data.reduce((value, element) => value > element ? value : element);
    minAltitude = data.reduce((value, element) => value < element ? value : element);
    // make minimum altitude in increments of 100
    minAltitude = (minAltitude / 100).floor() * 100;
    // make maximum altitude in increments of 100
    maxAltitude = (maxAltitude / 100).ceil() * 100;
    length = data.length;
  }

  @override
  void paint(Canvas canvas, Size size) {
    Color textColor = Colors.white;
    Color textBackColor = Colors.black;
    if(length == 0) {
      return;
    }

    // find width needed to display max altitude
    TextSpan span = TextSpan(style: TextStyle(fontSize: 10, color: textColor, backgroundColor: textBackColor), text: "88888");
    TextPainter tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
    tp.layout();
    double margin = tp.width;

    double width = size.width - margin;
    double height = size.height;
    double step = width / (length - 1);
    double stepY = height / (maxAltitude - minAltitude);

    List<Offset> points = [];
    for (int i = 0; i < length; i++) {
      double x = i * step;
      double y = height - (data[i] - minAltitude) * stepY;
      points.add(Offset(x, y));
    }

    double topAltitude = height - (altitudeOfPlan - minAltitude) * stepY;
    for (int i = 0; i < length - 1; i++) {
      // all areas into terrain mark red
      _paint.color = topAltitude < points[i].dy || topAltitude < points[i + 1].dy ? Colors.blue : Colors.orange;
      canvas.drawLine(points[i], points[i + 1], _paint);
    }

    // label text
    span = TextSpan(style: TextStyle(fontSize: 10, color: textColor, backgroundColor: textBackColor), text: maxAltitude.round().toString().padLeft(5, " "));
    tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, Offset(width, 0));

    span = TextSpan(style: TextStyle(fontSize: 10, color: textColor, backgroundColor: textBackColor), text: minAltitude.round().toString().padLeft(5, " "));
    tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, Offset(width, height - tp.height));

    // choose destinations based on width with one destination per 1/5 screen pixels
    double xx = 0;
    // draw no more than 5 points on screen
    double last = -width / 5;
    for(int index = 0; index < destinations.length; index++) {
      if(destinations[index].calculations == null) {
        continue;
      }
      double inc = destinations[index].calculations!.distance * step;
      xx += inc;
      if((xx - last) > (width / 5)) {
        last = xx;
        span = TextSpan(style: TextStyle(fontSize: 10, color: textColor, backgroundColor: textBackColor),
            text: destinations[index].locationID);
        tp = TextPainter(text: span, textAlign: TextAlign.left, textDirection: TextDirection.ltr);
        tp.layout();
        tp.paint(canvas, Offset(xx, height - tp.height));
      }
    }
  }

  @override
  bool shouldRepaint(oldDelegate) => false;


}

