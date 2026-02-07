import 'dart:math' as math;

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
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:latlong2/latlong.dart';

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
                          Storage().route.setAltitude(pValue);
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
            return Padding(padding: const EdgeInsets.fromLTRB(10, 5, 10, 0), child:SizedBox(width: Constants.screenWidth(context), height: Constants.screenHeight(context) / 4, child: makeChart(context, snapshot.data)));
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

    Widget windDiagram = Padding(
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 0),
      child: _makeWindFieldDiagram(),
    );

    return Scaffold(body:
    Padding(padding: const EdgeInsets.fromLTRB(5, 48, 5, 5), child: Column(children:[
      Expanded(flex: 4, child:grid),
      const Row( // nearby destinations
          children: <Widget>[
            Expanded(flex: 1, child: Divider()),
            Text("Winds aloft en route", style: TextStyle(fontSize: 10)),
            Expanded(flex: 16, child: Divider()),
          ]
      ),
      Expanded(flex: 2, child: windDiagram),
      const Row( // nearby destinations
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

  Widget _makeWindFieldDiagram() {
    final List<LatLng> path = Storage().route.getPathNextHighResolution();
    if(path.length < 2) {
      return const Center(child: Text("No route for winds aloft"));
    }

    final List<int> altitudes = _windFieldAltitudes();
    final _WindFieldData field = _buildWindFieldData(path, altitudes);
    if(field.samples.isEmpty) {
      return const Center(child: Text("No winds aloft available"));
    }

    final Color textColor = Theme.of(context).colorScheme.onSurface;
    final Color gridColor = textColor.withAlpha(50);
    return SizedBox.expand(
      child: CustomPaint(
        painter: _WindFieldDiagramPainter(
          samples: field.samples,
          columns: field.columns,
          altitudes: altitudes,
          textColor: textColor,
          gridColor: gridColor,
        ),
      ),
    );
  }

  List<int> _windFieldAltitudes() {
    return const [
      0,
      3000,
      6000,
      9000,
      12000,
      18000,
    ];
  }

  _WindFieldData _buildWindFieldData(
      List<LatLng> path, List<int> altitudes) {
    if(path.length < 2 || altitudes.isEmpty) {
      return const _WindFieldData([], 0);
    }

    const int maxColumns = 40;
    final int columnCount = math.min(maxColumns, path.length).toInt();
    final int fore = Storage().route.fore;
    final int lastIndex = path.length - 1;
    final double step = columnCount > 1 ? lastIndex / (columnCount - 1) : 0;
    final List<_WindFieldSample> samples = [];

    for(int column = 0; column < columnCount; column++) {
      final int index = columnCount == 1 ? 0 : (column * step).round();
      final LatLng coordinate = path[index];
      final double course = _courseAtPathIndex(path, index);
      for(final int altitude in altitudes) {
        double? wd;
        double? ws;
        (wd, ws) = WindsCache.getWindsAt(
            coordinate, altitude.toDouble(), fore);
        if(wd == null || ws == null) {
          continue;
        }
        final double angleRad = (wd - course) * math.pi / 180;
        final double headwindComponent = ws * math.cos(angleRad);
        samples.add(_WindFieldSample(
          column: column,
          altitude: altitude,
          component: headwindComponent,
        ));
      }
    }
    return _WindFieldData(samples, columnCount);
  }

  double _courseAtPathIndex(List<LatLng> path, int index) {
    if(path.length < 2) {
      return 0;
    }
    int startIndex = index;
    int endIndex = index + 1;
    if(endIndex >= path.length) {
      endIndex = index;
      startIndex = index - 1;
    }
    if(startIndex < 0 || startIndex == endIndex) {
      startIndex = 0;
      endIndex = 1;
    }
    return GeoCalculations().calculateBearing(path[startIndex], path[endIndex]);
  }

  Widget makeChart(BuildContext context, List<double?>? data) {
    if(data == null) {
      return const Center(child: Text("Elevation charts not downloaded"));
    }
    return CustomPaint(painter: AltitudePainter(context, data),);
  }

}


class AltitudePainter extends CustomPainter {

  final BuildContext context;
  final List<double?> data;
  double maxAltitude = double.negativeInfinity;
  double minAltitude = double.infinity;
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
    // find axix limits
    for(int count = 0; count < data.length; count++) {
      if(data[count] == null) {
        continue;
      }
      else if(data[count]! > maxAltitude) {
        maxAltitude = data[count]!;
      }
      else if(data[count]! <= minAltitude) {
        minAltitude = data[count]!;
      }
    }
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
      double y = data[i] == null ?
      double.nan : // treat nulls as minimum altitude
      height - (data[i]! - minAltitude) * stepY;
      points.add(Offset(x, y));
    }

    double topAltitude = height - (altitudeOfPlan - minAltitude) * stepY;
    for (int i = 0; i < length - 1; i++) {
      // all areas into terrain mark red
      if(points[i].dy.isNaN) {
        points[i] = Offset(points[i].dx, height);
        _paint.color = Color.fromARGB(255, 255, 0, 255); // magenta for nulls
      }
      else {
        _paint.color =
        topAltitude < points[i].dy || topAltitude < points[i + 1].dy ? Colors
            .blue : Colors.orange;
      }
      if(points[i + 1].dy.isNaN) {
        points[i + 1] = Offset(points[i + 1].dx, height);
        _paint.color = Color.fromARGB(255, 255, 0, 255); // magenta for nulls
      }
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

class _WindFieldData {
  final List<_WindFieldSample> samples;
  final int columns;

  const _WindFieldData(this.samples, this.columns);
}

class _WindFieldSample {
  final int column;
  final int altitude;
  final double component;

  const _WindFieldSample({
    required this.column,
    required this.altitude,
    required this.component,
  });
}

class _WindFieldDiagramPainter extends CustomPainter {
  final List<_WindFieldSample> samples;
  final int columns;
  final List<int> altitudes;
  final Color textColor;
  final Color gridColor;

  const _WindFieldDiagramPainter({
    required this.samples,
    required this.columns,
    required this.altitudes,
    required this.textColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if(altitudes.isEmpty || columns <= 0) {
      return;
    }

    final List<int> sortedAltitudes = altitudes.toList()..sort();
    final double minAltitude = sortedAltitudes.first.toDouble();
    final double maxAltitude = sortedAltitudes.last.toDouble();
    if(minAltitude == maxAltitude) {
      return;
    }

    const double topPadding = 4;
    const double bottomPadding = 16;
    const double rightPadding = 4;
    final TextStyle labelStyle = TextStyle(fontSize: 10, color: textColor);
    final TextPainter labelSizer = TextPainter(
      text: TextSpan(text: _formatAltitudeLabel(sortedAltitudes.last), style: labelStyle),
      textAlign: TextAlign.left,
      textDirection: TextDirection.ltr,
    )..layout();
    final double leftPadding = labelSizer.width + 6;

    final double chartWidth = size.width - leftPadding - rightPadding;
    final double chartHeight = size.height - topPadding - bottomPadding;
    if(chartWidth <= 0 || chartHeight <= 0) {
      return;
    }

    final Paint backgroundPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(leftPadding, topPadding, chartWidth, chartHeight),
      backgroundPaint,
    );

    final Paint gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final Map<int, double> altitudeY = {};
    for(final int altitude in sortedAltitudes) {
      final double y = topPadding + (maxAltitude - altitude) /
          (maxAltitude - minAltitude) * chartHeight;
      altitudeY[altitude] = y;
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(leftPadding + chartWidth, y),
        gridPaint,
      );
      final String label = _formatAltitudeLabel(altitude);
      final TextPainter labelPainter = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textAlign: TextAlign.right,
        textDirection: TextDirection.ltr,
      )..layout();
      labelPainter.paint(
          canvas, Offset(leftPadding - labelPainter.width - 4, y - labelPainter.height / 2));
    }

    if(samples.isEmpty) {
      return;
    }

    final Map<int, (double, double)> altitudeBands =
    _computeAltitudeBands(sortedAltitudes, altitudeY, topPadding, chartHeight);
    final double cellWidth = chartWidth / columns;
    double maxComponent = 0;
    for(final _WindFieldSample sample in samples) {
      final double magnitude = sample.component.abs();
      if(magnitude > maxComponent) {
        maxComponent = magnitude;
      }
    }
    if(maxComponent <= 0) {
      maxComponent = 1;
    }

    for(final _WindFieldSample sample in samples) {
      final (double bandTop, double bandBottom) = altitudeBands[sample.altitude] ??
          (topPadding, topPadding + chartHeight);
      final double intensity = (sample.component.abs() / maxComponent).clamp(0.0, 1.0);
      final Color target = sample.component >= 0 ? Colors.red : Colors.green;
      final Color color = Color.lerp(Colors.black, target, intensity) ?? target;
      final Paint cellPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      final double x = leftPadding + sample.column * cellWidth;
      canvas.drawRect(
        Rect.fromLTWH(x, bandTop, cellWidth, bandBottom - bandTop),
        cellPaint,
      );
    }
  }

  static String _formatAltitudeLabel(int altitude) {
    if(altitude == 0) {
      return "0";
    }
    return "${(altitude / 1000).round()}k";
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

Map<int, (double, double)> _computeAltitudeBands(
    List<int> sortedAltitudes,
    Map<int, double> altitudeY,
    double topPadding,
    double chartHeight) {
  final Map<int, (double, double)> bands = {};
  final List<int> altitudesByY = sortedAltitudes
      .where((altitude) => altitudeY.containsKey(altitude))
      .toList()
    ..sort((a, b) => altitudeY[a]!.compareTo(altitudeY[b]!));
  if(altitudesByY.isEmpty) {
    return bands;
  }
  final int lastIndex = altitudesByY.length - 1;
  final double bottom = topPadding + chartHeight;
  for(int i = 0; i < altitudesByY.length; i++) {
    final int altitude = altitudesByY[i];
    final double y = altitudeY[altitude]!;
    double bandTop;
    double bandBottom;
    if(altitudesByY.length == 1) {
      bandTop = topPadding;
      bandBottom = bottom;
    }
    else if(i == 0) {
      final double nextY = altitudeY[altitudesByY[i + 1]] ?? y;
      bandTop = topPadding;
      bandBottom = (y + nextY) / 2;
    }
    else if(i == lastIndex) {
      final double prevY = altitudeY[altitudesByY[i - 1]] ?? y;
      bandTop = (prevY + y) / 2;
      bandBottom = bottom;
    }
    else {
      final double prevY = altitudeY[altitudesByY[i - 1]] ?? y;
      final double nextY = altitudeY[altitudesByY[i + 1]] ?? y;
      bandTop = (prevY + y) / 2;
      bandBottom = (y + nextY) / 2;
    }
    if(bandBottom < bandTop) {
      final double swap = bandTop;
      bandTop = bandBottom;
      bandBottom = swap;
    }
    bands[altitude] = (bandTop, bandBottom);
  }
  return bands;
}
