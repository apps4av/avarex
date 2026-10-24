import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:avaremp/aircraft/aircraft.dart';
import 'package:avaremp/aircraft/aircraft_performance.dart';
import 'package:avaremp/constants.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/destination/destination_calculations.dart';
import 'package:avaremp/main_screen.dart';
import 'package:avaremp/utils/toast.dart' show Toast;
import 'package:avaremp/utils/path_utils.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:universal_io/io.dart';
import 'best_cruise_altitude.dart';
import 'plan_create_widget.dart';
import 'waypoint.dart';
import 'plan_file_widget.dart';
import 'plan_item_widget.dart';
import 'plan_line_widget.dart';
import 'plan_load_save_widget.dart';
import 'plan_manage_widget.dart';
import 'plan_route.dart';
import 'plan_transfer_widget.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:avaremp/data/altitude_profile.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:avaremp/weather/winds_aloft.dart';
import 'package:avaremp/weather/winds_cache.dart';
import 'package:latlong2/latlong.dart';

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});
  @override
  State<StatefulWidget> createState() => PlanScreenState();
}

class PlanScreenState extends State<PlanScreen> {
  final ScrollController _scrollController = ScrollController();

  // null shows the plan (waypoint) editor; 0-4 show an action sub-page inline
  int? _actionTab;
  bool _findingBestAltitude = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentWaypoint();
      _loadPlanCruiseFromAircraft();
      if (Storage().route.applyEndpointFieldElevations()) {
        Storage().route.update();
      }
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

  /// Cruise speed and fuel flow from the selected aircraft. Once per visit, not on the one-second plan refresh.
  Future<void> _loadPlanCruiseFromAircraft() async {
    final String selector = _planAircraftSelector();
    if (selector.isEmpty || !mounted) {
      return;
    }
    final int alt = Storage().route.altitude;
    final int powerPct = Storage().settings.getPerformanceCruisePowerPercent();
    CruiseResult? cruise;
    try {
      final Aircraft dbAc = await UserDatabaseHelper.db.getAircraft(selector);
      cruise = PlanPerformanceHelper.cruiseAtPlanAltitude(dbAc, alt, powerPercent: powerPct);
    } catch (_) {}
    cruise ??= PlanPerformanceHelper.cruiseForBuiltInDisplayName(selector, alt, powerPercent: powerPct);
    if (cruise == null || !mounted) {
      return;
    }
    final double tas = cruise.ktas.roundToDouble();
    final double gph = (cruise.gph * 10).round() / 10.0;
    if (tas <= 0 || gph <= 0) {
      return;
    }
    final bool sameSpeed = Storage().settings.getTas().roundToDouble() == tas;
    final bool sameBurn = (Storage().settings.getFuelBurn() - gph).abs() < 0.05;
    if (sameSpeed && sameBurn) {
      return;
    }
    Storage().settings.setTas(tas);
    Storage().settings.setFuelBurn(gph);
    if (mounted) {
      Storage().route.update();
    }
  }

  @override
  Widget build(BuildContext context) {
    final PlanRoute route = Storage().route;
    Storage().planSearch = false;

    double bottom = Constants.bottomPaddingSize(context);

    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, bottom),
      child: Column(
        children: [
          Expanded(
            child: _actionTab == null ? _buildPlanEditor(route) : _actionPage(_actionTab!),
          ),
          const SizedBox(height: 8),
          if (_actionTab == null)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _planToolButton(
                  icon: const Icon(Icons.add),
                  tooltip: "Insert waypoint",
                  onPressed: () {
                    Storage().planSearch = true;
                    MainScreenState.gotoFind();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: DropdownButtonHideUnderline(
                  child: DropdownButton2<String>(
                    buttonStyleData: ButtonStyleData(
                      height: _planToolExtent,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_planToolExtent / 2),
                        border: Border.all(color: Theme.of(context).colorScheme.outline),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    iconStyleData: IconStyleData(
                      iconSize: 20,
                      iconEnabledColor: Theme.of(context).colorScheme.onSurface,
                    ),
                    dropdownStyleData: DropdownStyleData(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
                    ),
                    menuItemStyleData: const MenuItemStyleData(height: 44),
                    style: Theme.of(context).textTheme.bodyLarge,
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
                ),
                _calcButton(),
                _planToolButton(
                  icon: const Icon(Icons.analytics_outlined),
                  tooltip: "Navigation log and terrain",
                  onPressed: () => showDialog(
                    context: context,
                    builder: (BuildContext context) => Dialog.fullscreen(child: _makeNavLog()),
                  ),
                ),
                if (route.length > 0)
                  _planToolButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: "Delete entire plan",
                    onPressed: _confirmDeleteEntirePlan,
                  ),
              ],
            ),
          ),
          if (_actionTab == null) const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _planButton(),
                _actionButton("Load & Save", 0),
                _actionButton("Create", 1),
                _actionButton("Brief & File", 2),
                _actionButton("Manage", 3),
                _actionButton("Transfer", 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _planAircraftSelector() {
    final String lastPerf = Storage().settings.getLastPerformanceAircraft().trim();
    if (lastPerf.isNotEmpty) {
      return lastPerf;
    }
    return Storage().settings.getAircraft().trim();
  }

  Future<AircraftPerformanceData?> _loadPlanPerformance(String selector) async {
    AircraftPerformanceData? perf;
    try {
      final Aircraft dbAc = await UserDatabaseHelper.db.getAircraft(selector);
      perf = PlanPerformanceHelper.performanceDataForAircraft(dbAc);
    } catch (_) {}
    if (perf != null && BestCruiseAltitude.altitudesFor(perf).isNotEmpty) {
      return perf;
    }
    for (final AircraftPerformanceData builtIn in CommonAircraftData.all) {
      if (builtIn.name == selector && BestCruiseAltitude.altitudesFor(builtIn).isNotEmpty) {
        return builtIn;
      }
    }
    return null;
  }

  Future<void> _applyBestCruiseAltitude() async {
    if (_findingBestAltitude) {
      return;
    }
    setState(() => _findingBestAltitude = true);
    try {
      final String selector = _planAircraftSelector();
      if (selector.isEmpty) {
        if (!mounted) return;
        Toast.showToast(
          context,
          'Select an aircraft in Menu → Aircraft & Performance (dropdown)',
          const Icon(Icons.info_outline),
          4,
        );
        return;
      }
      final List<PlanLegTarget> legs = Storage().route.cruiseLegs();
      if (legs.isEmpty) {
        if (!mounted) return;
        Toast.showToast(
          context,
          'Add a route with a destination first',
          const Icon(Icons.info_outline),
          4,
        );
        return;
      }
      final AircraftPerformanceData? perf = await _loadPlanPerformance(selector);
      if (!mounted) return;
      if (perf == null) {
        Toast.showToast(
          context,
          'No cruise data: set aircraft Type (e.g. C172) or add a cruise table in My Aircraft',
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          5,
        );
        return;
      }
      final List<int> altitudes = BestCruiseAltitude.altitudesFor(perf);
      final int powerPct = Storage().settings.getPerformanceCruisePowerPercent();
      final int fore = Storage().route.fore;
      double? climbKt;
      double? climbFpm;
      try {
        final Aircraft saved = await UserDatabaseHelper.db.getAircraft(selector);
        final double? speed = double.tryParse(saved.bestClimbSpeed);
        if (speed != null && speed > 0) {
          final double knotsTo = Storage().units.knotsTo;
          climbKt = knotsTo == 0 ? speed : speed / knotsTo;
        }
        final double? rate = double.tryParse(saved.bestClimbRate);
        if (rate != null && rate > 0) {
          climbFpm = rate;
        }
      } catch (_) {}
      if (!mounted) return;
      final List<Destination> planned = Storage().route.getAllDestinations();
      if (planned.length < 2) {
        return;
      }
      final RouteTrack track = BestCruiseAltitude.buildTrack([
        for (int index = 0; index < planned.length - 1; index++)
          (from: planned[index].coordinate, to: planned[index + 1].coordinate),
      ], spacingNm: BestCruiseAltitude.terrainSpacingNm);
      List<double?> terrain = [];
      try {
        terrain = await AltitudeProfile.getAltitudeProfile(
          track.points.map((({double nm, LatLng at}) point) => point.at).toList(),
        );
      } catch (_) {}
      if (!mounted) return;
      final int startAlt = legs.first.fromAltitudeFt;
      final bool arrive = Storage().route.isArrivalAirport(legs.last.waypoint);
      final int? field = arrive
          ? Waypoint.airportFieldElevationFt(
              legs.last.waypoint.planDestination.type,
              legs.last.waypoint.planDestination.elevation,
            )
          : null;
      final int endAlt = field ?? legs.last.waypoint.effectiveAltitude(Storage().route.altitude);
      final int topAltitude = altitudes.reduce((int a, int b) => a > b ? a : b);
      // Let the spinner paint before the route search runs on this isolate.
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      final String foreString = fore.toString().padLeft(2, "0");
      final Map<String, (double?, double?)> windMemo = {};
      (double?, double?) windFor(LatLng point, int altitude) {
        final String? station = WindsCache.locateNearestStation(point);
        final String key = "$station|$altitude";
        return windMemo.putIfAbsent(key, () {
          final Object? stored = Storage().winds.get("$station${foreString}H");
          return WindsCache.getWindAtAltitude(
            altitude.toDouble(),
            stored is WindsAloft ? stored : null,
          );
        });
      }

      final RouteCruiseResult result = BestCruiseAltitude.choose(
        track: track,
        terrainFt: terrain,
        altitudesFt: altitudes,
        startAltitudeFt: startAlt,
        endAltitudeFt: endAlt,
        arriveAtEnd: arrive,
        climbTrueAirspeedKt: climbKt,
        climbRateConstantFpm: climbFpm,
        topAltitudeFt: topAltitude,
        cruiseAt: (int altitude) => perf.getCruisePerformance(altitude, powerPct, 0),
        windAt: windFor,
        variationAt: (double nm) => _variationAlong(track, planned, nm),
      );
      final CruiseProfile? profile = result.profile;
      if (profile == null) {
        if (!mounted) return;
        Toast.showToast(
          context,
          result.terrainShort
              ? 'No cruise altitude clears terrain by 1,000 ft'
              : 'Wind is too strong for cruise speed on these legs',
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          5,
        );
        return;
      }
      if (legs.length == track.legEndNm.length) {
        for (int index = 0; index < legs.length; index++) {
          final PlanLegTarget leg = legs[index];
          final double startNm = index == 0 ? 0 : track.legEndNm[index - 1];
          final CruiseStep step = profile.stepAt(track.legEndNm[index]);
          if (leg.fixIndex == null) {
            leg.waypoint.navAltitudeFt = profile.stepAt((startNm + track.legEndNm[index]) / 2).altitudeFt;
          }
          if (leg.fixIndex == null && Storage().route.isArrivalAirport(leg.waypoint)) {
            continue;
          }
          leg.waypoint.setLegCruise(
            leg.fixIndex,
            altitudeFt: step.altitudeFt,
            ktas: step.ktas,
            gph: step.gph,
          );
        }
      }
      Storage().route.applyEndpointFieldElevations();
      Storage().route.cruiseProfile = profile;
      Storage().route.update();
      if (!mounted) return;
      if (result.terrainShort) {
        Toast.showToast(
          context,
          'No cruise altitude clears terrain by 1,000 ft',
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          5,
        );
        return;
      }
      Toast.showToast(
        context,
        'Calculated altitudes for shortest flight time based on winds aloft and performance of $selector',
        const Icon(Icons.check_circle, color: Colors.green),
        5,
      );
    } catch (e) {
      if (!mounted) return;
      Toast.showToast(
        context,
        'Could not find a best altitude: $e',
        const Icon(Icons.error, color: Colors.red),
        4,
      );
    } finally {
      if (mounted) {
        setState(() => _findingBestAltitude = false);
      }
    }
  }

  /// Magnetic variation along [track], interpolated between the fixes.
  double _variationAlong(RouteTrack track, List<Destination> fixes, double nm) {
    if (fixes.length < 2 || track.legEndNm.isEmpty) {
      return 0;
    }
    for (int index = 0; index < track.legEndNm.length && index + 1 < fixes.length; index++) {
      final double end = track.legEndNm[index];
      if (nm > end + 0.05 && index < track.legEndNm.length - 1) {
        continue;
      }
      final double start = index == 0 ? 0 : track.legEndNm[index - 1];
      final double? fromVariation = fixes[index].geoVariation;
      final double? toVariation = fixes[index + 1].geoVariation;
      final double begin = fromVariation ?? toVariation ?? 0;
      final double finish = toVariation ?? fromVariation ?? 0;
      final double span = end - start;
      final double fraction = span <= 0.05 ? 0 : ((nm - start) / span).clamp(0.0, 1.0);
      return begin + (finish - begin) * fraction;
    }
    return fixes.last.geoVariation ?? 0;
  }

  Widget _planButton() {
    final bool active = _actionTab == null;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TextButton(
        style: active
            ? TextButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primaryContainer)
            : null,
        onPressed: () => setState(() => _actionTab = null),
        child: const Text("Plan"),
      ),
    );
  }

  Widget _actionButton(String label, int tab) {
    final bool active = _actionTab == tab;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TextButton(
        style: active
            ? TextButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primaryContainer)
            : null,
        onPressed: () => setState(() => _actionTab = tab),
        child: Text(label),
      ),
    );
  }

  void _returnToPlan() {
    setState(() => _actionTab = null);
  }

  Widget _actionPage(int tab) {
    switch (tab) {
      case 0:
        return PlanLoadSaveWidget(onDone: _returnToPlan);
      case 1:
        return PlanCreateWidget(onDone: _returnToPlan);
      case 2:
        return const PlanFileWidget();
      case 3:
        return const PlanManageWidget();
      case 4:
      default:
        return const PlanTransferWidget();
    }
  }

  Future<void> _confirmDeleteEntirePlan() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete plan?"),
        content: const Text(
            "Delete the entire plan? All waypoints will be removed. This cannot be undone."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      Storage().route.clear();
    });
  }

  static const double _planToolExtent = 40;

  ButtonStyle get _planToolStyle {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return IconButton.styleFrom(
      iconSize: 22,
      minimumSize: const Size(_planToolExtent, _planToolExtent),
      fixedSize: const Size(_planToolExtent, _planToolExtent),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: scheme.onSurface,
      disabledForegroundColor: scheme.onSurface.withAlpha(120),
      side: BorderSide(color: scheme.outline),
      shape: const CircleBorder(),
    );
  }

  Widget _planToolButton({
    required Widget icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: IconButton(
        style: _planToolStyle,
        tooltip: tooltip,
        onPressed: onPressed,
        icon: icon,
      ),
    );
  }

  Widget _calcButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: IconButton(
        style: _planToolStyle,
        tooltip: "Calculate altitudes",
        onPressed: _findingBestAltitude ? null : _applyBestCruiseAltitude,
        icon: _findingBestAltitude
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.height),
      ),
    );
  }

  Widget _buildPlanEditor(PlanRoute route) {
    return Column(
      children: [
        Expanded(
          flex: 1,
          child: ValueListenableBuilder<int>( // update in plan change
            valueListenable: route.change,
            builder: (context, value, _) {
              return ListTile(
                key: Key(Storage().getKey()),
                title: PlanLineWidgetState.getHeading(),
                subtitle: PlanLineWidgetState.getFieldsFromCalculations(
                  Storage().route.totalCalculations,
                ),
              );
            }),
        ),
        Expanded(
          flex: 5,
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
                        "Use the buttons below to create or load a plan",
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
                  onReorderItem : (int oldIndex, int newIndex) {
                    setState(() {
                      route.moveWaypoint(oldIndex, newIndex);
                    });
                  },
                ),
        ),
      ],
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
  void initState() {
    super.initState();
    Storage().winds.change.addListener(_onWinds);
  }

  void _onWinds() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    Storage().winds.change.removeListener(_onWinds);
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
            title: fileName,
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
    final List<double> planAltitudes = Storage().route.getPathNextAltitudes();
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
          planAltitudes: planAltitudes,
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
      final LatLng coordinate = dest.coordinate;
      
      // Find the closest point on the path to this waypoint
      double minDist = double.infinity;
      int closestIndex = 0;
      for (int i = 0; i < path.length; i++) {
        final double dist = GeoCalculations().calculateDistance(path[i], coordinate);
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
  final List<double> planAltitudes;
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
    this.planAltitudes = const [],
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

    // Draw the altitude flown. A short leg rises only as far as the climb has reached.
    final Paint planLinePaint = Paint()
      ..color = Colors.cyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if(planAltitudes.length >= 2) {
      final double step = chartWidth / (planAltitudes.length - 1);
      double? lastX;
      double? lastY;
      for(int i = 0; i < planAltitudes.length; i++) {
        final double x = leftPadding + i * step;
        final double y = (topPadding + (maxAltitude - planAltitudes[i]) /
            (maxAltitude - minAltitude) * chartHeight)
            .clamp(topPadding, topPadding + chartHeight);
        if(lastX != null && lastY != null) {
          canvas.drawLine(Offset(lastX, lastY), Offset(x, y), planLinePaint);
        }
        lastX = x;
        lastY = y;
      }
    } else if(planAltitude > 0) {
      final double planY = topPadding + (maxAltitude - planAltitude) /
          (maxAltitude - minAltitude) * chartHeight;
      if(planY >= topPadding && planY <= topPadding + chartHeight) {
        canvas.drawLine(
          Offset(leftPadding, planY),
          Offset(leftPadding + chartWidth, planY),
          planLinePaint,
        );
      }
    }

    // Draw elevation curve overlay with color based on plan altitude
    if(elevationData != null && elevationData!.length >= 2) {
      final int length = elevationData!.length;
      final double step = chartWidth / (length - 1);
      
      final Paint elevationOutline = Paint()
        ..color = const Color(0xFF101418)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round;
      final Paint elevationPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;

      // A missing sample breaks the line. X still follows the route, so a gap
      // stays where the sample is missing instead of sliding the rest left.
      final List<Offset> outline = [];
      final List<Color> segmentColors = [];
      Offset? previous;
      double? lastElevation;
      double? lastPlanAltitude;
      for(int i = 0; i < length; i++) {
        final double? elevation = elevationData![i];
        if(elevation == null) {
          previous = null;
          lastElevation = null;
          lastPlanAltitude = null;
          continue;
        }
        final double x = leftPadding + i * step;
        final double y = (topPadding + (maxAltitude - elevation) /
            (maxAltitude - minAltitude) * chartHeight)
            .clamp(topPadding, topPadding + chartHeight);
        final Offset point = Offset(x, y);
        final double legAltitude = _planAltitudeAt(i, length);
        if(previous != null && lastElevation != null && lastPlanAltitude != null) {
          final bool currentAbove = elevation >= legAltitude;
          final bool lastAbove = lastElevation >= lastPlanAltitude;
          outline.add(previous);
          outline.add(point);
          segmentColors.add((currentAbove || lastAbove) ? Colors.red : Colors.green);
        }
        previous = point;
        lastElevation = elevation;
        lastPlanAltitude = legAltitude;
      }
      for(int i = 0; i < segmentColors.length; i++) {
        canvas.drawLine(outline[i * 2], outline[i * 2 + 1], elevationOutline);
      }
      for(int i = 0; i < segmentColors.length; i++) {
        elevationPaint.color = segmentColors[i];
        canvas.drawLine(outline[i * 2], outline[i * 2 + 1], elevationPaint);
      }
    }

    // Draw waypoint labels at the bottom
    _drawWaypoints(canvas, leftPadding, topPadding, chartWidth, chartHeight);

    // Draw tap indicator and tooltip
    _drawTapTooltip(canvas, size, leftPadding, topPadding, chartWidth, chartHeight, minAltitude, maxAltitude);
  }
  
  double _planAltitudeAt(int index, int length) {
    if(planAltitudes.length == length && length > 0) {
      return planAltitudes[index.clamp(0, length - 1)];
    }
    if(planAltitudes.length >= 2 && length > 1) {
      final double fraction = index / (length - 1);
      final int sample = (fraction * (planAltitudes.length - 1)).round().clamp(0, planAltitudes.length - 1);
      return planAltitudes[sample];
    }
    return planAltitude.toDouble();
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

  static bool _sameAltitudes(List<double> a, List<double> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
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
           !_sameAltitudes(oldDelegate.planAltitudes, planAltitudes) ||
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
