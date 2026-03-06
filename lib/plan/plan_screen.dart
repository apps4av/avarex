import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:avaremp/constants.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/destination/destination_calculations.dart';
import 'package:avaremp/main_screen.dart';
import 'package:avaremp/utils/toast.dart';
import 'package:avaremp/utils/path_utils.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:universal_io/io.dart';
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
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentWaypoint();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrentWaypoint() {
    final int currentIndex = Storage().route.currentWaypointIndex;
    if (currentIndex > 0 && _scrollController.hasClients) {
      const double itemHeight = 72.0;
      final double targetOffset = currentIndex * itemHeight;
      final double maxScroll = _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        targetOffset.clamp(0.0, maxScroll),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final PlanRoute route = Storage().route;
    Storage().planSearchIndex = null;

    double bottom = Constants.bottomPaddingSize(context);

    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, bottom),
      child: Column(
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
            })),
          Expanded(flex: 5,
            child: route.length == 0
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_location_alt, size: 64, color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(
                          "No waypoints in plan",
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Use Actions to create or load a plan",
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  )
                : ReorderableListView(
                    scrollController: _scrollController,
                    scrollDirection: Axis.vertical,
                    buildDefaultDragHandles: false,
                    children: <Widget>[
                      for (int index = 0; index < route.length; index++)
                        ReorderableDelayedDragStartListener(
                          index: index,
                          key: Key(index.toString()),
                          child: Dismissible(
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16),
                              decoration: BoxDecoration(
                                color: Colors.red.withAlpha(30),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.delete, color: Colors.red),
                            ),
                            key: Key(Storage().getKey()),
                            direction: DismissDirection.endToStart,
                            onDismissed: (direction) {
                              setState(() {
                                route.removeWaypointAt(index);
                              });
                            },
                            child: ValueListenableBuilder<int>(
                              valueListenable: route.change,
                              builder: (context, value, _) {
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 2),
                                  color: route.isCurrent(index)
                                      ? Theme.of(context).colorScheme.primaryContainer.withAlpha(100)
                                      : null,
                                  child: PlanItemWidget(
                                    waypoint: route.getWaypointAt(index),
                                    current: route.isCurrent(index),
                                    onLongPress: () {
                                      Storage().planSearchIndex = index;
                                      MainScreenState.gotoFind();
                                    },
                                    onTap: () {
                                      setState(() {
                                        Storage().route.setCurrentWaypoint(index);
                                      });
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                    onReorder: (int oldIndex, int newIndex) {
                      setState(() {
                        if (oldIndex < newIndex) {
                          newIndex -= 1;
                        }
                        route.moveWaypoint(oldIndex, newIndex);
                      });
                    },
                  ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                TextButton(
                  onPressed: () async {
                    await Navigator.pushNamed(context, "/plan_actions");
                    setState(() {});
                  },
                  child: const Text("Actions"),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 60,
                  child: TextFormField(
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    onChanged: (value) {
                      double? pValue = double.tryParse(value);
                      Storage().settings.setTas(pValue ?? Storage().settings.getTas());
                    },
                    controller: TextEditingController()..text = Storage().settings.getTas().round().toString(),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: "ASpd",
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 60,
                  child: TextFormField(
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    onChanged: (value) {
                      double? pValue = double.tryParse(value);
                      Storage().settings.setFuelBurn(pValue ?? Storage().settings.getFuelBurn());
                    },
                    controller: TextEditingController()..text = Storage().settings.getFuelBurn().toString(),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: "GPH",
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 70,
                  child: TextFormField(
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    onChanged: (value) {
                      int? pValue = int.tryParse(value);
                      pValue ??= 3000;
                      Storage().route.altitude = pValue;
                    },
                    controller: TextEditingController()..text = Storage().route.altitude.toString(),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: "Alt",
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton2<String>(
                    isDense: true,
                    buttonStyleData: ButtonStyleData(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Theme.of(context).colorScheme.outline),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    dropdownStyleData: DropdownStyleData(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
                    ),
                    isExpanded: false,
                    value: "${Storage().route.fore.toString().padLeft(2, "0")}H",
                    items: ["06H", "12H", "24H"].map((String item) {
                      return DropdownMenuItem<String>(
                        value: item,
                        child: Text(item),
                      );
                    }).toList(),
                    onChanged: (value) {
                      value ??= ["06H", "12H", "24H"][0];
                      setState(() {
                        Storage().route.fore = int.parse(value!.substring(0, 2));
                      });
                    },
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.analytics_outlined),
                  tooltip: "Navigation log and terrain",
                  onPressed: () => showDialog(
                    context: context,
                    builder: (BuildContext context) => Dialog.fullscreen(child: _makeNavLog()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _makeNavLog() {
    final List<Destination> destinations = Storage().route.getAllDestinations();
    final bool hasRoute = destinations.isNotEmpty;

    Widget terrainProfile = FutureBuilder(
      future: AltitudeProfile.getAltitudeProfile(Storage().route.getPathNextHighResolution()),
      builder: (BuildContext context, var snapshot) {
        if (snapshot.hasData) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(10, 5, 10, 0),
            child: SizedBox(
              width: Constants.screenWidth(context),
              height: Constants.screenHeight(context) / 4,
              child: makeChart(context, snapshot.data),
            ),
          );
        }
        return const Center(child: CircularProgressIndicator());
      },
    );

    List<Widget> values = [];
    values.addAll(DestinationCalculations.labels.map((String s) => Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
      ),
      child: AutoSizeText(
        s,
        minFontSize: 4,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    )));

    bool isEvenRow = true;
    for (Destination d in destinations) {
      if (d.calculations == null) {
        continue;
      }
      final bgColor = isEvenRow
          ? Theme.of(context).colorScheme.surface
          : Theme.of(context).colorScheme.surfaceContainerHighest;
      values.addAll(d.calculations!.getLog().map((String s) => Container(
        padding: const EdgeInsets.all(4),
        color: bgColor,
        child: AutoSizeText(s, minFontSize: 4),
      )));
      isEvenRow = !isEvenRow;
    }

    if (Storage().route.totalCalculations != null) {
      List<String> total = Storage().route.totalCalculations!.getLog();
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
      values.addAll(total.map((String s) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
        ),
        child: AutoSizeText(
          s,
          minFontSize: 4,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
        ),
      )));
    }

    Widget grid = hasRoute
        ? InteractiveViewer(
            constrained: false,
            boundaryMargin: const EdgeInsets.all(20),
            minScale: 0.5,
            maxScale: 4.0,
            child: SizedBox(
              width: Constants.screenWidth(context),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: DestinationCalculations.columns,
                childAspectRatio: 2.5,
                children: values,
              ),
            ),
          )
        : Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.route, size: 48, color: Theme.of(context).colorScheme.outline),
                const SizedBox(height: 8),
                Text("No route created", style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                const SizedBox(height: 4),
                Text("Add waypoints to see navigation log", style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
              ],
            ),
          );

    Widget windDiagram = Padding(
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 0),
      child: _makeWindFieldDiagram(),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Navigation Log"),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.image_outlined),
            tooltip: "Save as PNG image",
            onPressed: hasRoute ? () => _captureNavLogToPng() : null,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: "Copy plan to clipboard",
            onPressed: () {
              Clipboard.setData(ClipboardData(text: Storage().route.toString()));
              Toast.showToast(context, "Copied plan to Clipboard", null, 3);
            },
          ),
          const SizedBox(width: 5),
        ],
      ),
      body: RepaintBoundary(
        key: _navLogKey,
        child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Expanded(
              flex: 4,
              child: Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: grid,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Icon(Icons.air, size: 14, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(
                    "Winds Aloft En Route",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(child: Divider()),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              flex: 2,
              child: Card(
                margin: EdgeInsets.zero,
                child: windDiagram,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Icon(Icons.terrain, size: 14, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(width: 4),
                  Text(
                    "Terrain En Route",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(child: Divider()),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              flex: 1,
              child: Card(
                margin: EdgeInsets.zero,
                child: terrainProfile,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  final GlobalKey _navLogKey = GlobalKey();

  Future<void> _captureNavLogToPng() async {
    try {
      RenderRepaintBoundary boundary = _navLogKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        if (mounted) {
          Toast.showToast(context, "Failed to capture image", const Icon(Icons.error, color: Colors.red), 3);
        }
        return;
      }
      
      final Uint8List pngBytes = byteData.buffer.asUint8List();
      final String routeName = Storage().route.name.isNotEmpty 
          ? Storage().route.name 
          : "NavLog";
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = "${routeName}_$timestamp.png";
      final String filePath = PathUtils.getFilePath(Storage().dataDir, fileName);
      
      final file = File(filePath);
      await file.writeAsBytes(pngBytes);
      
      if (mounted) {
        if (Constants.shouldShare) {
          final params = ShareParams(
            files: [XFile(file.path)],
            sharePositionOrigin: const Rect.fromLTWH(128, 128, 1, 1),
          );
          SharePlus.instance.share(params);
        } else {
          Toast.showToast(context, "Saved to $fileName", const Icon(Icons.check, color: Colors.green), 3);
        }
      }
    } catch (e) {
      if (mounted) {
        Toast.showToast(context, "Error: $e", const Icon(Icons.error, color: Colors.red), 3);
      }
    }
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
    // find axis limits
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
    // handle case where no valid altitude data was found
    if(minAltitude.isInfinite || maxAltitude.isInfinite || minAltitude.isNaN || maxAltitude.isNaN) {
      minAltitude = 0;
      maxAltitude = 1000;
      return;
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
