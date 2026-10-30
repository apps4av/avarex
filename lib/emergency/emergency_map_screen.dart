import 'dart:async';
import 'dart:math' as math;

import 'package:auto_size_text/auto_size_text.dart';
import 'package:avaremp/aircraft/aircraft.dart';
import 'package:avaremp/aircraft/aircraft_performance.dart';
import 'package:avaremp/chart/chart.dart';
import 'package:avaremp/constants.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/emergency/emergency_logic.dart';
import 'package:avaremp/emergency/emergency_profile.dart';
import 'package:avaremp/instruments/glide_profile.dart';
import 'package:avaremp/io/gps.dart';
import 'package:avaremp/map_screen.dart' show ChartTileProvider, Plane;
import 'package:avaremp/storage.dart';
import 'package:avaremp/weather/metar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;

/// Emergency mode: engine out, fire or no fuel. A simple north-up map on the
/// ownship with the glide ring, plus four cards:
///   A best glide speed (top left)     B best runway (top right)
///   D declare (bottom left)           C checklist (bottom right)
/// The screen only reads app settings. It never writes the map center, zoom,
/// layers, checklist or any other setting, so leaving it returns to the normal
/// map exactly as it was.
class EmergencyMapScreen extends StatefulWidget {
  const EmergencyMapScreen({super.key});

  @override
  State<EmergencyMapScreen> createState() => _EmergencyMapScreenState();
}

class _EmergencyMapScreenState extends State<EmergencyMapScreen> with SingleTickerProviderStateMixin {
  static const double _msToKnots = 1.94384;
  static const double _metersToFeet = 3.28084;
  static const double _recomputeMoveNm = 0.5;
  static const Duration _minInterval = Duration(seconds: 4);

  final MapController _controller = MapController();
  late final AnimationController _blink;
  late final String _chartType;
  late final int _zoom;

  SelectedAircraft? _aircraft;
  double _bestGlideKt = 0;
  List<String> _steps = [];
  int _step = 0;

  RunwaySelection _selection = const RunwaySelection(null, false);
  bool _computed = false;
  bool _busy = false;
  LatLng? _computedAt;
  int _glideKey = -1;
  DateTime _lastCompute = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _pending;

  /// Keeps the chosen runway from changing while the airplane flies on.
  bool _locked = false;

  bool _mapReady = false;
  bool _recentering = false;

  @override
  void initState() {
    super.initState();
    // Same zoom as long pressing Center on the map.
    _chartType = Storage().settings.getChartType();
    _zoom = ChartCategory.chartTypeToZoom(_chartType);
    _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))
      ..repeat(reverse: true);
    Storage().gpsChange.addListener(_onGps);
    Storage().area.change.addListener(_onGlide);
    _load();
  }

  @override
  void dispose() {
    Storage().gpsChange.removeListener(_onGps);
    Storage().area.change.removeListener(_onGlide);
    _pending?.cancel();
    _blink.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final SelectedAircraft aircraft = await Aircraft.resolveSelected();
    final List<String> steps = await EmergencyProfile.loadSteps();
    if (!mounted) {
      return;
    }
    final double glideApp = GlideProfile.glideSpeedAppUnits(aircraft);
    setState(() {
      _aircraft = aircraft;
      _bestGlideKt = glideApp / (Storage().units.knotsTo == 0 ? 1 : Storage().units.knotsTo);
      _steps = steps;
    });
    // Make sure the glide ring matches the aircraft and position now.
    Storage().area.glideProfile.updateGlide();
    _recompute();
  }

  LatLng get _ownship => Gps.toLatLng(Storage().position);

  void _onGps() {
    // Zoom is allowed, pan is not: put the ownship back in the center.
    if (_mapReady && !_recentering) {
      _recentering = true;
      try {
        _controller.move(_ownship, _controller.camera.zoom);
      } catch (_) {}
      _recentering = false;
    }
    final LatLng? at = _computedAt;
    if (at != null && EmergencyLogic.distanceNm(at, _ownship) > _recomputeMoveNm) {
      _recompute();
    }
  }

  /// The glide ring is refreshed every few seconds. Looking up airports for
  /// each refresh is more than needed, so at most one lookup per few seconds.
  void _onGlide() {
    if (_glideKey == Storage().area.change.value || _pending != null) {
      return;
    }
    final Duration wait = _minInterval - DateTime.now().difference(_lastCompute);
    if (wait <= Duration.zero) {
      _recompute();
    } else {
      _pending = Timer(wait, () {
        _pending = null;
        _recompute();
      });
    }
  }

  Future<void> _recompute() async {
    if (_busy || _aircraft == null || _locked) {
      return;
    }
    _busy = true;
    _lastCompute = DateTime.now();
    try {
      _glideKey = Storage().area.change.value;
      final LatLng here = _ownship;
      final List<LatLng> ring = Storage().area.glideProfile.getGlideCircle();
      RunwaySelection selection = const RunwaySelection(null, false);
      if (ring.length >= 4) {
        double minLat = 90, maxLat = -90, minLon = 180, maxLon = -180;
        for (final LatLng p in ring) {
          minLat = math.min(minLat, p.latitude);
          maxLat = math.max(maxLat, p.latitude);
          minLon = math.min(minLon, p.longitude);
          maxLon = math.max(maxLon, p.longitude);
        }
        final List<AirportDestination> airports =
            await MainDatabaseHelper.db.findAirportsInBounds(minLat, maxLat, minLon, maxLon);
        // Runways with no published heading use the ident and magnetic variation.
        // The variation is looked up with the airport, so make sure it is there.
        for (final AirportDestination a in airports) {
          if (a.geoVariation == null && a.runways.any(_lacksHeading)) {
            final (double, double) geo = await MainDatabaseHelper.db.getGeoInfo(a.coordinate);
            a.geoVariation = geo.$2;
          }
        }
        final AircraftPerformanceData? performance = _aircraft!.landingPerformance;
        final List<RunwayCandidate> found = EmergencyLogic.findCandidates(
          airports: airports.map(_toEmergencyAirport).toList(),
          glidePolygon: ring,
          position: here,
          windFor: _windAtAirport,
          requiredLanding: (double elevationFt, double headwindKt) =>
              _requiredLanding(performance, elevationFt, headwindKt),
        );
        final List<EmergencyAirport> converted = airports.map(_toEmergencyAirport).toList();
        selection = EmergencyLogic.select(
          found,
          noData: found.isNotEmpty
              ? const []
              : EmergencyLogic.findNoDataAirports(
                  airports: converted, glidePolygon: ring, position: here, windFor: _windAtAirport),
        );
      }
      _computedAt = here;
      if (mounted && !_locked) {
        setState(() {
          _selection = selection;
          _computed = true;
        });
      }
    } catch (_) {
      // keep the last answer
    } finally {
      _busy = false;
    }
  }

  bool _lacksHeading(Map<String, dynamic> row) {
    return (double.tryParse((row['LEHeadingT'] ?? '').toString()) ?? 0) <= 0;
  }

  EmergencyAirport _toEmergencyAirport(AirportDestination a) {
    return EmergencyAirport(
      id: a.locationID,
      name: a.facilityName,
      coordinate: a.coordinate,
      elevationFt: a.elevation ?? 0,
      variation: a.geoVariation,
      ctaf: a.ctaf,
      unicom: a.unicom,
      runways: a.runways,
    );
  }

  /// Wind at the airport, knots: its METAR if there is one, else winds aloft.
  (double?, double?) _windAtAirport(EmergencyAirport airport) {
    try {
      final Metar? metar = Storage().metar.get(airport.id) as Metar?;
      if (metar != null) {
        final double? direction = metar.getWindDirection();
        final double? speed = metar.getWindSpeed();
        if (direction != null && speed != null) {
          return (direction, speed);
        }
      }
    } catch (_) {}
    return _windAloft(airport.elevationFt);
  }

  (double?, double?) _windAloft(double altitudeFt) {
    if (Storage().area.windsAloft == null) {
      return (null, null);
    }
    return Storage().area.getWind(altitudeFt);
  }

  /// Landing distance over 50 ft, a standard day at field elevation, at max
  /// gross weight. Null when the aircraft has no landing data.
  double? _requiredLanding(AircraftPerformanceData? performance, double elevationFt, double headwindKt) {
    if (performance == null) {
      return null;
    }
    try {
      final double distance = performance.getLandingOver50ft(
          elevationFt,
          PerformanceCalculator.isaTemperatureCelsius(elevationFt),
          performance.maxGrossWeight,
          headwindKt,
          false);
      return distance > 0 ? distance : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _confirmExit() async {
    final bool? exit = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Exit emergency mode?'),
        content: const Text('You will return to the map as you left it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Stay')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Exit')),
        ],
      ),
    );
    if (exit == true && mounted) {
      Navigator.pop(context);
    }
  }

  // ---------------------------------------------------------------- map

  Widget _buildMap() {
    final LatLng start = _ownship;
    final MapOptions options = MapOptions(
      initialCenter: start,
      initialZoom: _zoom.toDouble(),
      minZoom: 2,
      maxZoom: 20,
      initialRotation: 0, // always north up
      backgroundColor: Storage().settings.isLightMode()
          ? Constants.mapBackgroundColorLight
          : Constants.mapBackgroundColorDark,
      // Zoom only. No pan, no rotate, no tilt.
      interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.scrollWheelZoom | InteractiveFlag.doubleTapZoom),
      onMapReady: () {
        _mapReady = true;
      },
      onMapEvent: (MapEvent event) {
        if (_recentering) {
          return;
        }
        final LatLng own = _ownship;
        final LatLng center = _controller.camera.center;
        if ((center.latitude - own.latitude).abs() > 1e-7 || (center.longitude - own.longitude).abs() > 1e-7) {
          _recentering = true;
          try {
            _controller.move(own, _controller.camera.zoom);
          } catch (_) {}
          _recentering = false;
        }
      },
    );

    final Size screen = MediaQuery.of(context).size;
    final Listenable updates = Listenable.merge([Storage().gpsChange, Storage().area.change]);

    return FlutterMap(
      mapController: _controller,
      options: options,
      children: [
        TileLayer(
          tms: true,
          maxNativeZoom: _zoom,
          keepBuffer: 1,
          tileProvider: ChartTileProvider(),
          urlTemplate: "${Storage().dataDir}/tiles/"
              "${ChartCategory.chartTypeToIndex(_chartType)}/"
              "{z}/{x}/{y}."
              "${ChartCategory.chartTypeToExtension(_chartType)}",
        ),
        IgnorePointer(
          child: AnimatedBuilder(
            animation: updates,
            builder: (BuildContext context, _) {
              final RunwayCandidate? runway = _selection.runway;
              return PolylineLayer(
                polylines: [
                  Polyline(
                    points: Storage().area.glideProfile.getGlideCircle(),
                    color: Constants.glideCircleColor,
                    strokeWidth: 3,
                    borderColor: Constants.glideCircleHaloColor,
                    borderStrokeWidth: 4,
                  ),
                  if (runway != null)
                    Polyline(
                      points: [_ownship, runway.threshold],
                      color: Colors.red,
                      strokeWidth: 4,
                      borderColor: Colors.white,
                      borderStrokeWidth: 1,
                    ),
                ],
              );
            },
          ),
        ),
        IgnorePointer(
          child: AnimatedBuilder(
            animation: Storage().area.change,
            builder: (BuildContext context, _) {
              final RunwayCandidate? runway = _selection.runway;
              if (runway == null) {
                return const SizedBox.shrink();
              }
              return MarkerLayer(
                markers: [
                  Marker(
                    point: runway.threshold,
                    width: 96,
                    height: 96,
                    child: Transform.rotate(
                      angle: runway.heading * math.pi / 180,
                      child: CustomPaint(painter: _LandingArrowPainter()),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        IgnorePointer(
          child: ValueListenableBuilder<int>(
            valueListenable: Storage().planeIconChange,
            builder: (BuildContext context, _, __) {
              return ValueListenableBuilder<Position>(
                valueListenable: Storage().gpsChange,
                builder: (BuildContext context, Position value, _) {
                  return MarkerLayer(
                    markers: [
                      Marker(
                        width: 48,
                        height: (screen.width + screen.height) / 2,
                        point: LatLng(value.latitude, value.longitude),
                        child: Transform.rotate(
                          angle: value.heading * math.pi / 180,
                          child: CustomPaint(painter: Plane(Storage().imagePlane)),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------- cards

  /// Dark card that flashes red when [alert] is set.
  Widget _card({required Widget child, required bool alert, VoidCallback? onTap, double maxWidth = 200}) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: AnimatedBuilder(
        animation: _blink,
        builder: (BuildContext context, Widget? content) {
          final bool on = alert && _blink.value > 0.5;
          return Material(
            color: on ? Colors.red.shade900 : Colors.black.withValues(alpha: 0.82),
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: alert ? Colors.red : Colors.white24, width: alert ? 3 : 1),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Padding(padding: const EdgeInsets.all(10), child: content),
            ),
          );
        },
        child: child,
      ),
    );
  }

  static const TextStyle _label = TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold);
  static const TextStyle _warn = TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.bold);
  static const TextStyle _big = TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold, height: 1.1);
  static const TextStyle _text = TextStyle(color: Colors.white, fontSize: 15, height: 1.25);

  String get _speedUnit => Storage().units.knotsTo == 1 ? 'kt' : 'mph';

  String _speedText(double knots) => (knots * Storage().units.knotsTo).round().toString();

  Widget _cardA() {
    return ValueListenableBuilder<Position>(
      valueListenable: Storage().gpsChange,
      builder: (BuildContext context, Position p, _) {
        final double altitudeFt = p.altitude * _metersToFeet;
        final (double? windFrom, double? windKt) = _windAloft(altitudeFt);
        final double ias = EmergencyLogic.indicatedAirspeedKt(
          groundSpeedKt: p.speed * _msToKnots,
          trackDeg: p.heading,
          altitudeFt: altitudeFt,
          windFromDeg: windFrom,
          windSpeedKt: windKt,
        );
        final bool off = _aircraft != null && EmergencyLogic.airspeedOff(ias, _bestGlideKt);
        return _card(
          alert: off,
          maxWidth: 170,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('A  BEST GLIDE', style: _label),
              Text(_aircraft == null ? '--' : '${_speedText(_bestGlideKt)} $_speedUnit', style: _big),
              Text('Now ${_speedText(ias)} $_speedUnit', style: _text),
              if (_aircraft != null)
                Text(_aircraft!.name, style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ),
        );
      },
    );
  }

  /// A locked runway that the glide ring no longer reaches.
  bool _lockedOutOfRange(RunwayCandidate runway) {
    return _locked &&
        !EmergencyLogic.pointInPolygon(runway.threshold, Storage().area.glideProfile.getGlideCircle());
  }

  void _toggleLock() {
    setState(() => _locked = !_locked);
    if (!_locked) {
      _recompute(); // unlocked: pick again from where we are now
    }
  }

  /// B title with the lock button. Locked, the runway stays as it is.
  Widget _bHeader(String label) {
    return Row(
      children: [
        Expanded(child: AutoSizeText(label, style: _label, maxLines: 1, minFontSize: 9)),
        const SizedBox(width: 6),
        InkWell(
          onTap: _toggleLock,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: _locked ? Colors.amber : Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_locked ? Icons.lock : Icons.lock_open, size: 16, color: Colors.black),
                const SizedBox(width: 3),
                Text(_locked ? 'LOCKED' : 'LOCK',
                    style: const TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _cardB() {
    final RunwayCandidate? runway = _selection.runway;
    if (runway == null) {
      return ValueListenableBuilder<Position>(
        valueListenable: Storage().gpsChange,
        builder: (BuildContext context, Position p, _) {
          final (double? windFrom, double? windKt) = _windAloft(p.altitude * _metersToFeet);
          final OffFieldDirection direction = EmergencyLogic.offFieldDirection(
              windFromDeg: windFrom, windSpeedKt: windKt, trackDeg: p.heading);
          return _card(
            alert: true,
            maxWidth: 190,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('B  LAND', style: _label),
                Text(_computed ? 'No runway identified' : 'Looking for runways...',
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    // The map is always north up, so the heading is the angle.
                    Transform.rotate(
                      angle: direction.heading * math.pi / 180,
                      child: const Icon(Icons.navigation, color: Colors.red, size: 52),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(direction.label, style: _text)),
                  ],
                ),
              ],
            ),
          );
        },
      );
    }
    return ValueListenableBuilder<Position>(
      valueListenable: Storage().gpsChange,
      builder: (BuildContext context, Position p, _) {
        final LatLng here = Gps.toLatLng(p);
        final double distance = EmergencyLogic.distanceNm(here, runway.threshold);
        final double bearing = EmergencyLogic.bearingDeg(here, runway.threshold);
        final double headwind = runway.headwindKt;
        final double crosswind = runway.crosswindKt;
        final String required = runway.requiredFt == null ? '' : '  need ${runway.requiredFt!.round()}';
        final bool outOfRange = _lockedOutOfRange(runway);
        if (runway.noRunwayData) {
          // The airport publishes no runway. Land on the field, into the wind.
          final String heading = runway.heading.round().toString().padLeft(3, '0');
          return _card(
            alert: true,
            maxWidth: 240,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _bHeader('B  LAND - NO RUNWAY DATA'),
                Text(runway.airport.id, style: _big),
                Text(runway.headwindKt >= 1 ? 'Land into wind $heading\u00b0' : 'Land straight in $heading\u00b0',
                    style: _text),
                Text('${distance.toStringAsFixed(1)} nm  brg ${bearing.round().toString().padLeft(3, '0')}\u00b0',
                    style: _text),
                if (outOfRange) const Text('OUTSIDE GLIDE RING', style: _warn),
              ],
            ),
          );
        }
        return _card(
          alert: _selection.lessThanIdeal || outOfRange,
          maxWidth: 240,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _bHeader(_selection.lessThanIdeal ? 'B  LAND - SHORT RUNWAY' : 'B  LAND'),
              Text('${runway.airport.id}  RW ${runway.runwayIdent}', style: _big),
              Text('${runway.lengthFt.round()} ft$required', style: _text),
              Text(
                  '${headwind >= 0 ? 'Headwind' : 'Tailwind'} ${headwind.abs().round()} kt'
                  '  XW ${crosswind.abs().round()}',
                  style: _text),
              Text('${distance.toStringAsFixed(1)} nm  brg ${bearing.round().toString().padLeft(3, '0')}\u00b0'
                  '  hdg ${runway.heading.round().toString().padLeft(3, '0')}\u00b0',
                  style: _text),
              if (outOfRange) const Text('OUTSIDE GLIDE RING', style: _warn),
            ],
          ),
        );
      },
    );
  }

  Widget _cardC() {
    final int total = _steps.length;
    final String step = total == 0 ? '' : _steps[_step % total];
    return _card(
      alert: false,
      maxWidth: 240,
      // Tapping goes to the next step and wraps back to the first.
      onTap: total == 0 ? null : () => setState(() => _step = (_step + 1) % total),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('C  CHECKLIST  ${total == 0 ? '' : '${_step + 1}/$total'}', style: _label),
              const Spacer(),
              InkWell(
                onTap: _confirmExit,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                  child: const Text('EXIT', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 70, maxHeight: 130),
            child: AutoSizeText(step,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600),
                minFontSize: 12,
                maxLines: 6),
          ),
          const Text('Tap for next step', style: TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _cardD() {
    final EmergencyAirport? airport = _selection.runway?.airport;
    final List<String> lines = [];
    if (airport != null) {
      if (airport.ctaf.isNotEmpty) {
        lines.add('CTAF ${airport.ctaf}');
      }
      if (airport.unicom.isNotEmpty) {
        lines.add('UNICOM ${airport.unicom}');
      }
      if (lines.isEmpty) {
        lines.add('${airport.id} no CTAF/UNICOM');
      }
    }
    return _card(
      alert: false,
      maxWidth: 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('D  DECLARE', style: _label),
          for (final String line in lines)
            Text(line, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
          const Text('121.5', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
          const Text('SQUAWK 7700',
              style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          _confirmExit();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(child: RepaintBoundary(child: _buildMap())),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Stack(
                  children: [
                    Align(alignment: Alignment.topLeft, child: _cardA()),
                    Align(alignment: Alignment.topRight, child: _cardB()),
                    Align(alignment: Alignment.bottomLeft, child: _cardD()),
                    Align(alignment: Alignment.bottomRight, child: _cardC()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Large red outlined arrow pointing up. The marker rotates it to the landing heading.
class _LandingArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final double h = size.height * 0.46;
    final double w = size.width * 0.30;
    final Path path = Path()
      ..moveTo(cx, cy - h)
      ..lineTo(cx + w, cy - h * 0.1)
      ..lineTo(cx + w * 0.35, cy - h * 0.1)
      ..lineTo(cx + w * 0.35, cy + h)
      ..lineTo(cx - w * 0.35, cy + h)
      ..lineTo(cx - w * 0.35, cy - h * 0.1)
      ..lineTo(cx - w, cy - h * 0.1)
      ..close();
    // Outline only, so the airport and runway underneath stay visible.
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 8);
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.red
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 4);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
