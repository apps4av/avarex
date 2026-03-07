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
    return _NavLogContent();
  }
}

class _NavLogContent extends StatefulWidget {
  const _NavLogContent();

  @override
  State<_NavLogContent> createState() => _NavLogContentState();
}

class _NavLogContentState extends State<_NavLogContent> {
  Offset? _tapPosition;
  List<double?>? _cachedElevationData;
  Future<List<double?>?>? _elevationFuture;
  final GlobalKey _navLogKey = GlobalKey();
  final TransformationController _tableZoomController = TransformationController();

  @override
  void dispose() {
    _tableZoomController.dispose();
    super.dispose();
  }

  void _resetTableZoom() {
    _tableZoomController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    final List<Destination> destinations = Storage().route.getAllDestinations();
    final bool hasRoute = destinations.isNotEmpty;

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
        ? GestureDetector(
            onDoubleTap: _resetTableZoom,
            child: InteractiveViewer(
              transformationController: _tableZoomController,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.3,
              maxScale: 4.0,
              child: SizedBox(
                width: Constants.screenWidth(context),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: DestinationCalculations.columns,
                    mainAxisExtent: 28,
                  ),
                  itemCount: values.length,
                  itemBuilder: (context, index) => values[index],
                ),
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

    // Cache the elevation future to avoid re-fetching on each rebuild
    _elevationFuture ??= AltitudeProfile.getAltitudeProfile(Storage().route.getPathNextHighResolution());
    
    Widget windDiagram = FutureBuilder<List<double?>?>(
      future: _elevationFuture,
      builder: (BuildContext context, var snapshot) {
        if (snapshot.hasData) {
          _cachedElevationData = snapshot.data;
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 5, 10, 0),
          child: _makeWindFieldDiagram(elevationData: _cachedElevationData),
        );
      },
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
                    "Winds & Terrain En Route",
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
              flex: 3,
              child: Stack(
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    child: windDiagram,
                  ),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTapDown: (details) {
                        // Adjust for padding inside windDiagram (10, 5, 10, 0)
                        final adjustedPosition = Offset(
                          details.localPosition.dx - 10,
                          details.localPosition.dy - 5,
                        );
                        setState(() {
                          _tapPosition = adjustedPosition;
                        });
                      },
                    ),
                  ),
                  if (_tapPosition != null)
                    Positioned(
                      left: _tapPosition!.dx + 10 - 6,
                      top: _tapPosition!.dy + 5 - 6,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.yellow.withAlpha(150),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.yellow, width: 1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

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

  Widget _makeWindFieldDiagram({List<double?>? elevationData}) {
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
    final int planAltitude = Storage().route.altitude;
    final int fore = Storage().route.fore;
    
    // Get waypoints with their positions along the route
    final List<(String, double)> waypoints = _getWaypointPositions(path);
    
    return SizedBox.expand(
      child: CustomPaint(
        painter: _WindFieldDiagramPainter(
          samples: field.samples,
          columns: field.columns,
          altitudes: altitudes,
          textColor: textColor,
          gridColor: gridColor,
          elevationData: elevationData,
          planAltitude: planAltitude,
          tapPosition: _tapPosition,
          path: path,
          fore: fore,
          waypoints: waypoints,
        ),
      ),
    );
  }
  
  List<(String, double)> _getWaypointPositions(List<LatLng> path) {
    final List<(String, double)> result = [];
    final List<Destination> destinations = Storage().route.getAllDestinations();
    if (destinations.isEmpty || path.isEmpty) return result;
    
    // Calculate total path length
    double totalLength = 0;
    final List<double> cumulativeDistances = [0];
    for (int i = 1; i < path.length; i++) {
      totalLength += GeoCalculations().calculateDistance(path[i - 1], path[i]);
      cumulativeDistances.add(totalLength);
    }
    if (totalLength == 0) return result;
    
    // Find position of each waypoint along the path
    for (final Destination dest in destinations) {
      final LatLng coord = dest.coordinate;
      
      // Find the closest point on the path to this waypoint
      double minDist = double.infinity;
      int closestIndex = 0;
      for (int i = 0; i < path.length; i++) {
        final double dist = GeoCalculations().calculateDistance(path[i], coord);
        if (dist < minDist) {
          minDist = dist;
          closestIndex = i;
        }
      }
      
      // Calculate position as fraction (0.0 to 1.0)
      final double position = cumulativeDistances[closestIndex] / totalLength;
      result.add((dest.locationID, position));
    }
    
    return result;
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
        double? windFrom;
        double? windSpeed;
        (windFrom, windSpeed) = WindsCache.getWindsAt(
            coordinate, altitude.toDouble(), fore);
        if(windFrom == null || windSpeed == null) {
          continue;
        }
        
        // Calculate tailwind component (positive = tailwind, negative = headwind)
        // windFrom = direction wind is coming FROM (aviation standard)
        // Wind blows TO direction: windFrom + 180
        // course = direction aircraft is flying TO
        // Component = windSpeed * cos(windBlowsTo - course)
        final double windBlowsTo = windFrom + 180;
        final double angleRad = (windBlowsTo - course) * math.pi / 180;
        final double tailwindComponent = windSpeed * math.cos(angleRad);
        
        samples.add(_WindFieldSample(
          column: column,
          altitude: altitude,
          component: tailwindComponent,
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
  final List<double?>? elevationData;
  final int planAltitude;
  final Offset? tapPosition;
  final List<LatLng>? path;
  final int fore;
  final List<(String, double)> waypoints;

  const _WindFieldDiagramPainter({
    required this.samples,
    required this.columns,
    required this.altitudes,
    required this.textColor,
    required this.gridColor,
    this.elevationData,
    this.planAltitude = 0,
    this.tapPosition,
    this.path,
    this.fore = 0,
    this.waypoints = const [],
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
      // Use a fixed scale for consistent colors (50 knots = full color)
      const double maxWindScale = 50.0;
      final double intensity = (sample.component.abs() / maxWindScale).clamp(0.0, 1.0);
      
      // Positive component = tailwind (wind pushing from behind) = green
      // Negative component = headwind (wind pushing against) = red
      Color color;
      if (sample.component > 0) {
        // Tailwind: dark -> bright green
        color = Color.lerp(
          const Color(0xFF1A1A1A),
          const Color(0xFF00E676),
          intensity,
        ) ?? Colors.green;
      } else if (sample.component < 0) {
        // Headwind: dark -> bright red
        color = Color.lerp(
          const Color(0xFF1A1A1A),
          const Color(0xFFFF5252),
          intensity,
        ) ?? Colors.red;
      } else {
        // No wind component: neutral gray
        color = const Color(0xFF1A1A1A);
      }
      final Paint cellPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      final double x = leftPadding + sample.column * cellWidth;
      canvas.drawRect(
        Rect.fromLTWH(x, bandTop, cellWidth, bandBottom - bandTop),
        cellPaint,
      );
    }

    // Draw plan altitude line
    if(planAltitude > 0) {
      final double planY = topPadding + (maxAltitude - planAltitude) /
          (maxAltitude - minAltitude) * chartHeight;
      if(planY >= topPadding && planY <= topPadding + chartHeight) {
        final Paint planLinePaint = Paint()
          ..color = Colors.cyan
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawLine(
          Offset(leftPadding, planY),
          Offset(leftPadding + chartWidth, planY),
          planLinePaint,
        );
      }
    }

    // Draw elevation curve overlay with color based on plan altitude
    if(elevationData != null && elevationData!.isNotEmpty) {
      final int length = elevationData!.length;
      final double step = chartWidth / (length - 1);
      
      final Paint elevationPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      
      // Draw segments colored by whether terrain is above or below plan altitude
      double? lastX;
      double? lastY;
      double? lastElevation;
      
      for(int i = 0; i < length; i++) {
        final double? elevation = elevationData![i];
        if(elevation == null) continue;
        
        final double x = leftPadding + i * step;
        final double y = topPadding + (maxAltitude - elevation) /
            (maxAltitude - minAltitude) * chartHeight;
        final double clampedY = y.clamp(topPadding, topPadding + chartHeight);
        
        if(lastX != null && lastY != null && lastElevation != null) {
          // Color based on whether terrain is above or below plan altitude
          // Red if terrain is at or above plan altitude (dangerous)
          // Green if terrain is below plan altitude (safe)
          final bool currentAbove = elevation >= planAltitude;
          final bool lastAbove = lastElevation >= planAltitude;
          
          if(currentAbove || lastAbove) {
            elevationPaint.color = Colors.red;
          } else {
            elevationPaint.color = Colors.green;
          }
          
          canvas.drawLine(Offset(lastX, lastY), Offset(x, clampedY), elevationPaint);
        }
        
        lastX = x;
        lastY = clampedY;
        lastElevation = elevation;
      }
    }

    // Draw waypoint labels at the bottom
    _drawWaypoints(canvas, leftPadding, topPadding, chartWidth, chartHeight);

    // Draw tap indicator and tooltip
    _drawTapTooltip(canvas, size, leftPadding, topPadding, chartWidth, chartHeight, minAltitude, maxAltitude);
  }
  
  void _drawWaypoints(Canvas canvas, double leftPadding, double topPadding, 
      double chartWidth, double chartHeight) {
    if (waypoints.isEmpty) return;
    
    final double bottomY = topPadding + chartHeight;
    
    for (final (String _, double position) in waypoints) {
      final double x = leftPadding + position * chartWidth;
      
      // Draw vertical tick mark at waypoint position
      final Paint tickPaint = Paint()
        ..color = Colors.cyan
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(x, bottomY - 8),
        Offset(x, bottomY + 4),
        tickPaint,
      );
    }
  }

  void _drawTapTooltip(Canvas canvas, Size size, double leftPadding, double topPadding, 
      double chartWidth, double chartHeight, double minAltitude, double maxAltitude) {
    if(tapPosition == null) return;
    
    final double tapX = tapPosition!.dx;
    final double tapY = tapPosition!.dy;
    
    // Check if path is valid for detailed tooltip
    if(path == null || path!.length < 2) return;
    
    // Check if tap is within chart area for detailed info
    if(tapX < leftPadding || tapX > leftPadding + chartWidth ||
       tapY < topPadding || tapY > topPadding + chartHeight) {
      return;
    }
    
    // Calculate which column was tapped (same indexing as chart drawing)
    final double cellWidth = chartWidth / columns;
    final int tappedColumn = ((tapX - leftPadding) / cellWidth).floor().clamp(0, columns - 1);
    
    // Calculate path index using the same formula as _buildWindFieldData
    final int lastIndex = path!.length - 1;
    final double step = columns > 1 ? lastIndex / (columns - 1) : 0;
    final int pathIndex = columns == 1 ? 0 : (tappedColumn * step).round().clamp(0, lastIndex);
    final LatLng coordinate = path![pathIndex];
    
    // Calculate altitude at tap position and snap to nearest altitude band
    final double rawAltitude = maxAltitude - (tapY - topPadding) / chartHeight * (maxAltitude - minAltitude);
    
    // Snap to nearest altitude from the altitude list (0, 3000, 6000, 9000, 12000, 18000)
    const List<int> altitudeLevels = [0, 3000, 6000, 9000, 12000, 18000];
    int altitudeAtTap = altitudeLevels[0];
    double minDiff = (rawAltitude - altitudeLevels[0]).abs();
    for (final int alt in altitudeLevels) {
      final double diff = (rawAltitude - alt).abs();
      if (diff < minDiff) {
        minDiff = diff;
        altitudeAtTap = alt;
      }
    }
    
    // Get terrain elevation at this position
    double? terrainElevation;
    if(elevationData != null && elevationData!.isNotEmpty) {
      final double progress = (tapX - leftPadding) / chartWidth;
      final int elevIndex = (progress * (elevationData!.length - 1)).round().clamp(0, elevationData!.length - 1);
      terrainElevation = elevationData![elevIndex];
    }
    
    // Get wind at this position and altitude (use the snapped altitude)
    double? windDir;
    double? windSpeed;
    (windDir, windSpeed) = WindsCache.getWindsAt(coordinate, altitudeAtTap.toDouble(), fore);
    
    // Calculate tailwind component using the same formula as _buildWindFieldData
    double? windComponent;
    double? course;
    if (windDir != null && windSpeed != null && path!.length >= 2) {
      // Calculate course at this position (same as _courseAtPathIndex)
      int startIdx = pathIndex;
      int endIdx = pathIndex + 1;
      if (endIdx >= path!.length) {
        endIdx = pathIndex;
        startIdx = pathIndex - 1;
      }
      if (startIdx < 0 || startIdx == endIdx) {
        startIdx = 0;
        endIdx = 1;
      }
      course = GeoCalculations().calculateBearing(path![startIdx], path![endIdx]);
      
      // Calculate tailwind component (positive = tailwind, negative = headwind)
      // windDir = direction wind is coming FROM
      // Wind blows TO direction: windDir + 180
      final double windBlowsTo = windDir + 180;
      final double angleRad = (windBlowsTo - course) * math.pi / 180;
      windComponent = windSpeed * math.cos(angleRad);
    }
    
    // Draw vertical line at tap position
    final Paint linePaint = Paint()
      ..color = Colors.white.withAlpha(150)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(tapX, topPadding),
      Offset(tapX, topPadding + chartHeight),
      linePaint,
    );
    
    // Draw horizontal line at tap altitude
    canvas.drawLine(
      Offset(leftPadding, tapY),
      Offset(leftPadding + chartWidth, tapY),
      linePaint,
    );
    
    // Draw crosshair circle
    final Paint circlePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(Offset(tapX, tapY), 6, circlePaint);
    
    // Find nearest waypoint to tap position
    String? nearestWaypoint;
    if (waypoints.isNotEmpty) {
      final double tapProgress = (tapX - leftPadding) / chartWidth;
      double minWaypointDist = 0.05; // Must be within 5% of route length
      for (final (String name, double position) in waypoints) {
        final double dist = (position - tapProgress).abs();
        if (dist < minWaypointDist) {
          minWaypointDist = dist;
          nearestWaypoint = name;
        }
      }
    }
    
    // Build tooltip text
    final List<String> tooltipLines = [];
    if (nearestWaypoint != null) {
      tooltipLines.add("Waypoint: $nearestWaypoint");
    }
    tooltipLines.add("Alt: $altitudeAtTap ft");
    if(terrainElevation != null) {
      tooltipLines.add("Terrain: ${terrainElevation.round()} ft");
    }
    if(course != null) {
      tooltipLines.add("Course: ${course.round()}°");
    }
    if(windDir != null && windSpeed != null) {
      tooltipLines.add("Wind: ${windDir.round()}° @ ${windSpeed.round()} kt");
    }
    if(windComponent != null) {
      if(windComponent > 0) {
        tooltipLines.add("Tailwind: ${windComponent.round()} kt");
      } else if(windComponent < 0) {
        tooltipLines.add("Headwind: ${(-windComponent).round()} kt");
      } else {
        tooltipLines.add("Crosswind only");
      }
    }
    
    // Draw tooltip background
    final TextStyle tooltipStyle = TextStyle(fontSize: 11, color: Colors.white);
    double maxTextWidth = 0;
    double totalTextHeight = 0;
    final List<TextPainter> painters = [];
    
    for(final String line in tooltipLines) {
      final TextPainter tp = TextPainter(
        text: TextSpan(text: line, style: tooltipStyle),
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
      )..layout();
      painters.add(tp);
      if(tp.width > maxTextWidth) maxTextWidth = tp.width;
      totalTextHeight += tp.height;
    }
    
    const double padding = 6;
    const double spacing = 2;
    final double tooltipWidth = maxTextWidth + padding * 2;
    final double tooltipHeight = totalTextHeight + padding * 2 + spacing * (tooltipLines.length - 1);
    
    // Position tooltip to avoid going off screen
    double tooltipX = tapX + 10;
    double tooltipY = tapY - tooltipHeight - 10;
    if(tooltipX + tooltipWidth > size.width) {
      tooltipX = tapX - tooltipWidth - 10;
    }
    if(tooltipY < 0) {
      tooltipY = tapY + 10;
    }
    
    // Draw tooltip box
    final Paint bgPaint = Paint()
      ..color = Colors.black.withAlpha(200)
      ..style = PaintingStyle.fill;
    final RRect tooltipRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(tooltipX, tooltipY, tooltipWidth, tooltipHeight),
      const Radius.circular(4),
    );
    canvas.drawRRect(tooltipRect, bgPaint);
    
    // Draw tooltip border
    final Paint borderPaint = Paint()
      ..color = Colors.white.withAlpha(100)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(tooltipRect, borderPaint);
    
    // Draw tooltip text
    double textY = tooltipY + padding;
    for(final TextPainter tp in painters) {
      tp.paint(canvas, Offset(tooltipX + padding, textY));
      textY += tp.height + spacing;
    }
  }

  static String _formatAltitudeLabel(int altitude) {
    if(altitude == 0) {
      return "0";
    }
    return "${(altitude / 1000).round()}k";
  }

  @override
  bool shouldRepaint(covariant _WindFieldDiagramPainter oldDelegate) {
    return oldDelegate.elevationData != elevationData ||
           oldDelegate.planAltitude != planAltitude ||
           oldDelegate.samples != samples ||
           oldDelegate.columns != columns ||
           oldDelegate.tapPosition != tapPosition;
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
