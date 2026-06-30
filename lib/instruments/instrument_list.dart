import 'dart:math';

import 'package:avaremp/destination/destination_calculations.dart';
import 'package:avaremp/gdl90/adsb_status_screen.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:avaremp/instruments/pfd_painter.dart';
import 'package:avaremp/plan/plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/plan/waypoint.dart';
import 'package:avaremp/utils/toast.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../constants.dart';
import 'package:avaremp/destination/destination.dart';
import '../io/gps.dart';


class InstrumentList extends StatefulWidget {
  const InstrumentList({super.key});

  @override
  State<InstrumentList> createState() => InstrumentListState();

  static double angularDifference(double hdg, double brg) {
    double absDiff = (hdg - brg).abs();
    if(absDiff > 180) {
      return 360 - absDiff;
    }
    return absDiff;
  }

  static bool leftOfCourseLine(double bT, double bC) {
    if(bC <= 180) {
      return (bT >= bC && bT <= bC + 180);
    }

    // brgCourse will be > 180 at this point
    return (bT > bC || bT < bC - 180);
  }

}

class InstrumentListState extends State<InstrumentList> {
  static final DateFormat _hourMinuteFormatter = DateFormat('HH:mm');
  final List<String> _items = Storage().settings.getInstruments().split(","); // get instruments
  late List<Color> _itemsColors;
  // Fractional (0..1) top-left position of each tile, keyed by tile code.
  final Map<String, Offset> _positions = {};
  bool? _loadedPortrait; // orientation whose positions are currently loaded
  // Tiles currently shown, in the order they were added. The rest are hidden
  // and can be added one by one from the menu.
  final List<String> _visible = [];
  bool _visibleLoaded = false;
  static const int _defaultVisibleCount = 5;
  String _gndSpeed = "0";
  String _altitude = "0";
  String _magneticHeading = "0\u00b0";
  String _timerUp = "00:00";
  String _timerDown = "30:00";
  String _destination = "";
  String _previousDestination = "";
  String _bearing = "0\u00b0";
  String _distance = "";
  String _utc = "00:00";
  String _eta = "";
  String _ete = "";
  String _source = "Auto";
  String _vsr = "";
  String _flightTime = "00:00";
  String _gel = "DL";
  String _adsb = "\u25cb"; // empty circle
  Color? _adsbColor; // circle color: null=default, yellow=partial, green=connected

  @override
  void dispose() {
    Storage().gpsChange.removeListener(_gpsListener);
    Storage().route.change.removeListener(_routeListener);
    Storage().timeChange.removeListener(_timeListener);
    super.dispose();
  }

  String _distanceFormat(double distance) {
    // if distance is less than 10 then show 1 decimal place, otherwise round it
    return distance < 10 ? distance.toStringAsFixed(1) : distance.round().toString();
  }

  String _truncate(String value) {
    int maxLength = 10;
    return value.length > maxLength ? value.substring(0, maxLength) : value;
  }

  (double, double) _getDistanceBearing() {
    LatLng position = Gps.toLatLng(Storage().position);
    GeoCalculations calculations = GeoCalculations();

    Destination? d = Storage().route.getCurrentWaypoint()?.destination;
    if (d != null) {
      double distance = calculations.calculateDistance(
          position, d.coordinate);
      double bearing = GeoCalculations.getMagneticHeading(calculations.calculateBearing(
          position, d.coordinate), d.geoVariation?? 0);
      return (distance, bearing);
    }
    return (0, 0);
  }


  void _gpsListener() {
    // connect to GPS
    double variation = Storage().area.variation;
    setState(() {
      double q = GeoCalculations.convertSpeed(Storage().position.speed);
      _gndSpeed = _truncate(q.round().toString());
      q = GeoCalculations.convertAltitude(Storage().position.altitude);
      _altitude = _truncate(q.round().toString());
      q = GeoCalculations.getMagneticHeading(Storage().position.heading, variation);
      _magneticHeading = _truncate("${q.round()}\u00b0");
      var (distance, bearing) = _getDistanceBearing();
      _distance = _truncate(_distanceFormat(distance));
      _bearing = _truncate("${bearing.round().toString()}\u00b0");
      Storage().pfdData.to = bearing;

      // CDI
      Waypoint? next = Storage().route.getCurrentWaypoint();
      Waypoint? prev = Storage().route.getLastWaypoint();

      double cdi = 0;
      if (next != null && prev != null) {
        LatLng prevCoordinate = prev.destination.coordinate;
        LatLng nextCoordinate = next.destination.coordinate;

        // The bearing from our CURRENT location to the target
        double brgOrg = GeoCalculations.getMagneticHeading(GeoCalculations().calculateBearing(prevCoordinate, nextCoordinate), variation);
        double brgCur = bearing;
        double brgDif = InstrumentList.angularDifference(brgOrg, brgCur);
        // Distance from our CURRENT position to the destination
        double dstCur = distance;

        // calculate deviation based on bearing diff and distance
        double deviation = dstCur * sin(brgDif * pi / 180); // nm
        // now find course deviation in degrees based on distance and deviation
        cdi = atan2(deviation, dstCur) * 180 / pi;

        // if distance is less than 15 miles then multiple by 4 for LOC sensitivity
        cdi = dstCur < 15 ? min(cdi * 4, 5) : min(cdi, 5);

        // Now determine whether we are LEFT.
        // Account for REVERSE SENSING if we are already BEYOND the target (>90deg)
        bool bLeftOfCourseLine = InstrumentList.leftOfCourseLine(brgCur,  brgOrg);
        if ((bLeftOfCourseLine && brgDif <= 90) || (!bLeftOfCourseLine && brgDif >= 90)) {
          cdi = -cdi;
        }
      }
      Storage().pfdData.cdi = -cdi;

      // VDI

      double vdi = 0;
      double relativeAGL = 0;

      if(next != null) {
        // Fetch the elevation of our destination. If we can't find it
        // then we don't want to display any vertical information
        double? destElev = next.destination is AirportDestination ? (next.destination as AirportDestination).elevation : null;

        if(destElev != null) {
          // Calculate our relative AGL compared to destination. If we are
          // lower then no display info
          relativeAGL = Storage().units.mToF * Storage().position.altitude - destElev;

          // Convert the destination distance to feet.
          double destDist = distance;
          double destInFeet = destDist * 6076.12;

          // Figure out our glide slope now based on our AGL height and distance
          vdi = atan(relativeAGL / destInFeet) * 180 / pi;
          if(vdi >= PfdPainter.vnavHigh) {
            vdi = PfdPainter.vnavHigh;
          }
          else if(vdi <= PfdPainter.vnavLow) {
            vdi = PfdPainter.vnavLow;
          }
        }

        // find time to next, not interested in fuel
        Destination d = Destination.fromLatLng(Gps.toLatLng(Storage().position));
        DestinationCalculations calc = DestinationCalculations(d, next.destination,
            GeoCalculations.convertSpeed(Storage().position.speed), 0, GeoCalculations.convertAltitude(Storage().position.altitude));
        calc.calculateTo();
        if(calc.time.isFinite) {
          Duration time = Duration(seconds: calc.time.round());
          if(time > const Duration(hours: 23)) { // no flight more than this long and saves overflow in instrument
            _eta = "XX:XX";
            _ete = "XX:XX";
            _vsr = "0";
          }
          else {
            _eta =
                _truncate(
                    _hourMinuteFormatter.format(DateTime.now().add(time)));
            _ete = _truncate(
                "${time.inHours.toString().padLeft(2, '0')}:${time.inMinutes.remainder(60).toString().padLeft(2, '0')}");
            if(destElev == null) {
              _vsr = "-";
            }
            else {
              if(time.inMinutes.toDouble() == 0) {
                _vsr = "-";
              }
              else {
                _vsr = _truncate(
                    ((relativeAGL - 1000) / time.inMinutes.toDouble())
                        .round()
                        .toStringAsFixed(0));
              }
            }
          }
        }
        else {
          _eta = "-";
          _ete = "-";
          _vsr = "-";
        }
      }
      Storage().pfdData.vdi = vdi;
      double? elevation = Storage().area.elevation;
      _gel = elevation == null ? "DL" : _truncate(elevation.round().toString());
    });
  }

  String _formatDestination(Destination? d) {
    if(d == null) {
      return "";
    }
    if(Destination.typeGps == d.type) {
      return _truncate(d.facilityName);
    }
    else if((Destination.isAirway(d.type) || (Destination.isProcedure(d.type))) && d.secondaryName != null) {
      return _truncate(d.secondaryName!);
    }
    else {
      return _truncate(d.locationID);
    }
  }

  void _routeListener() {
    setState(() {
      PlanRoute? route = Storage().route;
      Destination? d = route.getCurrentWaypoint()?.destination;
      if(d == null) {
        _eta = "";
        _ete = "";
        _vsr = "";
        _destination = "";
      }
      else {
        _destination = _formatDestination(d);
      }
      var (distance, bearing) = _getDistanceBearing();
      _distance = _truncate(_distanceFormat(distance));
      _bearing = _truncate("${bearing.round().toString()}\u00b0");

      // previous destination
      d = Storage().route.getPreviousDestination();
      if(d == null) {
        _previousDestination = "";
      }
      else {
        _previousDestination = _formatDestination(d);
      }
    });


  }

  void _timeListener() {
    setState(() {
      _timerUp = _truncate(Storage().flightTimer.getTime().toString().substring(2, 7));
      _timerDown = _truncate(Storage().flightDownTimer.getTime().toString().substring(2, 7));
      Color defaultColor = Theme.of(context).cardColor.withValues(alpha: 0.6);
      // DNT: red when expired, green when counting, default otherwise
      _itemsColors[_items.indexOf("DNT")] = Storage().flightDownTimer.isExpired()
          ? Colors.red
          : (Storage().flightDownTimer.isStarted() ? Colors.green : defaultColor);
      // UPT: green when counting, default otherwise
      _itemsColors[_items.indexOf("UPT")] = Storage().flightTimer.isStarted() ? Colors.green : defaultColor;
      _utc = _truncate(_hourMinuteFormatter.format(DateTime.now().toUtc()));
      _source = Storage().getGpsSourceModeString();
      // Auto = default tile color, Green = Internal, Blue = External
      defaultColor = Theme.of(context).cardColor.withValues(alpha: 0.6);
      _itemsColors[_items.indexOf("SRC")] = {"Auto": defaultColor, "Internal": Colors.green, "External": Colors.blue}[Storage().gpsSourceMode] ?? defaultColor;
      // ADSB: filled circle when connected (green with GPS, yellow without GPS),
      // empty circle when disconnected. Only the circle is colored, not the tile.
      bool connected = Storage().adsbStatus.connected;
      bool gpsValid = Storage().adsbStatus.gpsValid;
      _adsb = connected ? "\u25cf" : "\u25cb"; // filled vs empty circle
      _adsbColor = !connected ? null : (gpsValid ? Colors.green : Colors.yellow);
      _flightTime = _truncate((Storage().flightStatus.flightTime.toDouble() / 3600).toStringAsFixed(2));
    });
  }

  InstrumentListState() {
    Storage().gpsChange.addListener(_gpsListener);
    // connect to dest change
    Storage().route.change.addListener(_routeListener);
    // up timer
    Storage().timeChange.addListener(_timeListener);
  }

  // up timer
  void _startUpTimer() {
    if(Storage().flightTimer.isStarted()) {
      Storage().flightTimer.stop();
    }
    else {
      Storage().flightTimer.reset();
      Storage().flightTimer.start();
    }
    setState(() {
      _timerUp = _truncate(Storage().flightTimer.getTime().toString().substring(2, 7));
    });
  }

  // skip waypoint
  void _planNextWaypoint() {
    Storage().route.advance();
  }

  // skip waypoint
  void _planPreviousWaypoint() {
    Storage().route.back();
  }

  // down timer
  void _startDownTimer() {

    if(Storage().flightDownTimer.isStarted()) {
      Storage().flightDownTimer.stop();
    }
    else {
      Storage().flightDownTimer.reset();
      Storage().flightDownTimer.start();
    }
    setState(() {
      _timerDown = _truncate(Storage().flightDownTimer.getTime().toString().substring(2, 7));
    });
  }

  // down timer
  void _resetTacTimer() {
    Storage().flightStatus.resetFlightTime();
  }

  void _cycleGpsSourceMode() {
    Storage().cycleGpsSourceMode();
    setState(() {
      _source = Storage().getGpsSourceModeString();
    });
  }

  // ADS-B tile tap: open the receiver status screen.
  void _showAdsbDetails() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdsbStatusScreen()),
    );
  }

  // tile dimensions, scaled by the user adjustable factor
  double _tileWidth() {
    bool portrait = Constants.isPortrait(context);
    double factor = Storage().settings.getInstrumentScaleFactor();
    return (portrait ? Constants.screenWidth(context) / 5.7 : Constants.screenWidth(context) / 9.7) / factor;
  }

  double _tileHeight() {
    bool portrait = Constants.isPortrait(context);
    double factor = Storage().settings.getInstrumentScaleFactor();
    return (portrait ? Constants.screenHeight(context) / 12 : Constants.screenHeight(context) / 8) / factor;
  }

  // default layout: a row of tiles near the top that wraps onto new rows
  Map<String, Offset> _defaultPositions() {
    double w = Constants.screenWidth(context);
    double h = Constants.screenHeight(context);
    double tw = _tileWidth();
    double th = _tileHeight();
    const double gap = 4;
    const double startX = 5;
    const double startY = 42; // leave room for the corner menu button
    Map<String, Offset> pos = {};
    double x = startX;
    double y = startY;
    for(String code in _items) {
      if(x + tw > w) { // wrap to next row
        x = startX;
        y += th + gap;
      }
      pos[code] = Offset(x / w, y / h);
      x += tw + gap;
    }
    return pos;
  }

  // load saved positions for the current orientation, filling any gaps with defaults
  void _loadPositions() {
    bool portrait = Constants.isPortrait(context);
    String raw = Storage().settings.getInstrumentPositions(portrait);
    Map<String, Offset> parsed = {};
    if(raw.isNotEmpty) {
      for(String part in raw.split(",")) {
        List<String> f = part.split(":");
        if(f.length == 3) {
          double? dx = double.tryParse(f[1]);
          double? dy = double.tryParse(f[2]);
          if(dx != null && dy != null) {
            parsed[f[0]] = Offset(dx, dy);
          }
        }
      }
    }
    Map<String, Offset> defaults = _defaultPositions();
    _positions.clear();
    for(String code in _items) {
      _positions[code] = parsed[code] ?? defaults[code] ?? const Offset(0, 0);
    }
    _loadedPortrait = portrait;
  }

  void _savePositions() {
    bool portrait = Constants.isPortrait(context);
    String raw = _positions.entries
        .map((e) => "${e.key}:${e.value.dx.toStringAsFixed(4)}:${e.value.dy.toStringAsFixed(4)}")
        .join(",");
    Storage().settings.setInstrumentPositions(portrait, raw);
  }

  List<String> _defaultVisible() {
    return _items.where((c) => c.isNotEmpty).take(_defaultVisibleCount).toList();
  }

  // load which tiles are shown; first run / empty falls back to the default few
  void _loadVisible() {
    String raw = Storage().settings.getInstrumentVisible();
    _visible.clear();
    if(raw.isEmpty) {
      _visible.addAll(_defaultVisible());
    }
    else {
      for(String c in raw.split(",")) {
        if(c.isNotEmpty && _items.contains(c) && !_visible.contains(c)) {
          _visible.add(c);
        }
      }
    }
    _visibleLoaded = true;
  }

  void _saveVisible() {
    Storage().settings.setInstrumentVisible(_visible.join(","));
  }

  // show/hide a tile from the menu; added tiles get their default slot
  void _toggleTile(String code) {
    setState(() {
      if(_visible.contains(code)) {
        _visible.remove(code);
      }
      else {
        _visible.add(code);
        _positions[code] ??= _defaultPositions()[code] ?? const Offset(0, 0);
      }
    });
    _saveVisible();
    _savePositions();
  }

  void _resetLayout() {
    setState(() {
      _visible
        ..clear()
        ..addAll(_defaultVisible());
      _positions
        ..clear()
        ..addAll(_defaultPositions());
    });
    _saveVisible();
    _savePositions();
  }

  // make a draggable instrument tile
  Widget _makeInstrument(String code) {
    double width = _tileWidth();
    double height = _tileHeight();
    double screenW = Constants.screenWidth(context);
    double screenH = Constants.screenHeight(context);
    int index = _items.indexOf(code);
    Offset frac = _positions[code] ?? const Offset(0, 0);

    String value = "";
    Color? valueColor; // override the value text color (used by the ADSB tile)
    Function() cb = () {};

    // set callbacks and connect values
    switch(code) {
      case "GS":
        value = _gndSpeed;
        break;
      case "ALT":
        value = _altitude;
        break;
      case "MT":
        value = _magneticHeading;
        break;
      case "PRV":
        value = _previousDestination;
        cb = _planPreviousWaypoint;
        break;
      case "NXT":
        value = _destination;
        cb = _planNextWaypoint;
        break;
      case "BRG":
        value = _bearing;
        break;
      case "DIS":
        value = _distance;
        break;
      case "GEL":
        value = _gel;
        break;
      case "ETA":
        value = _eta;
        break;
      case "ETE":
        value = _ete;
        break;
      case "VSR":
        value = _vsr;
        break;
      case "UTC":
        value = _utc;
        break;
      case "UPT":
        value = _timerUp;
        cb = _startUpTimer;
        break;
      case "DNT":
        value = _timerDown;
        cb = _startDownTimer;
        break;
      case "SRC":
        value = _source;
        cb = _cycleGpsSourceMode;
        break;
      case "FLT":
        value = _flightTime;
        cb = _resetTacTimer;
        break;
      case "ADSB":
        value = _adsb;
        valueColor = _adsbColor;
        cb = _showAdsbDetails;
        break;
    }

    return Positioned(
      left: frac.dx * screenW,
      top: frac.dy * screenH,
      width: width,
      height: height,
      child: GestureDetector(
        onTap: cb,
        onPanUpdate: Storage().settings.isInstrumentsLocked() ? null : (details) {
          Offset cur = _positions[code] ?? const Offset(0, 0);
          double nx = (cur.dx * screenW + details.delta.dx).clamp(0.0, max(0.0, screenW - width));
          double ny = (cur.dy * screenH + details.delta.dy).clamp(0.0, max(0.0, screenH - height));
          setState(() {
            _positions[code] = Offset(nx / screenW, ny / screenH);
          });
        },
        onPanEnd: Storage().settings.isInstrumentsLocked() ? null : (_) => _savePositions(),
        child: Container(
          width: width,
          decoration: BoxDecoration(borderRadius: const BorderRadius.all(Radius.circular(20)), color: _itemsColors[index]),
          child: Column(
            children: [
              Expanded(flex: 2, child: SizedBox(width: width - 10, child: FittedBox(child: Text(_items[index], style: const TextStyle( ), maxLines: 1,)))),
              Expanded(flex: 3, child: SizedBox(width: width - 10, child: FittedBox(child: Text(value,         style: TextStyle(color: valueColor), maxLines: 1,)))),
            ]),
        ),
      ),
    );
  }

  // corner menu: tile sizing, reset layout, and help. Lives top-left and is fixed.
  Widget _makeMenu() {
    return Positioned(
      left: 5,
      top: 5,
      child: DropdownButtonHideUnderline(
        child: DropdownButton2<String>(
          dropdownStyleData: DropdownStyleData(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
            width: Constants.screenWidth(context) / 2,
          ),
          isExpanded: false,
          customButton: CircleAvatar(radius: 16, backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.7), child: const Icon(Icons.arrow_drop_down),),
          onChanged: (value) {
            setState(() {
            });
          },
          items: [
            DropdownMenuItem(
              value: "4",
              onTap:() {
                // Make a toast and show
                Toast.showToast(context,
                    "You may adjust the size of the tiles using Expand/Contract.\n"
                    "You may drag any tile to move it anywhere on the screen.\n"
                    "Use Lock Tiles to prevent accidentally moving tiles, and Unlock Tiles to move them again.\n"
                    "Each tile is listed in this menu: tap + to show it, or - to hide it.\n"
                    "Use Reset Layout to restore the default tiles and positions.\n\n"
                    "Available Tiles:\n"
                    "GS  - Ground speed.\n"
                    "ALT - GPS altitude.\n"
                    "MT  - Magnetic track.\n"
                    "PRV - Tap to go to the previous waypoint as shown.\n"
                    "NXT - Tap to go to the next waypoint as shown.\n"
                    "DIS - Distance to the next waypoint.\n"
                    "BRG - Bearing to the next waypoint.\n"
                    "GEL - Ground elevation. Needs Elevation charts.\n"
                    "ETA - Estimated time of arrival at the next waypoint.\n"
                    "ETE - Estimated time en-route to the next waypoint.\n"
                    "VSR - VSI required to arrive at the NXT airport 1000ft above its elevation.\n"
                    "UPT - Tap to start/stop the up timer.\n"
                    "DNT - Tap to start/stop the down timer.\n"
                    "UTC - Coordinated Universal Time.\n"
                    "SRC - GPS source. Tap to cycle modes. Green=Internal, Blue=External, otherwise auto switch.\n"
                    "FLT - Total flight time in hours. Tap to reset.\n"
                    "ADSB- ADS-B receiver status. Green \u25cf=connected, yellow \u25cf=connected without GPS, \u25cb=disconnected. Click on the tile to open the status screen.\n",
                    null, 30);
                },
                child: _menuRow(Icons.help_outline, "Help"),
            ),
            DropdownMenuItem(
              value: "1",
              onTap:() {
                Storage().settings.setInstrumentScaleFactor(Storage().settings.getInstrumentScaleFactor() - 0.1);
              },
              child: _menuRow(Icons.zoom_in, "Expand"),
            ),
            DropdownMenuItem(
              value: "2",
              onTap:() {
                Storage().settings.setInstrumentScaleFactor(Storage().settings.getInstrumentScaleFactor() + 0.1);
              },
              child: _menuRow(Icons.zoom_out, "Contract"),
            ),
            DropdownMenuItem(
              value: "lock",
              onTap:() {
                setState(() {
                  Storage().settings.setInstrumentsLocked(!Storage().settings.isInstrumentsLocked());
                });
              },
              child: Storage().settings.isInstrumentsLocked()
                  ? _menuRow(Icons.lock_open, "Unlock Tiles")
                  : _menuRow(Icons.lock_outline, "Lock Tiles"),
            ),
            DropdownMenuItem(
              value: "3",
              onTap: _resetLayout,
              child: _menuRow(Icons.restart_alt, "Reset Layout"),
            ),
            for(final String code in _items.where((c) => c.isNotEmpty))
              DropdownMenuItem(
                value: "toggle-$code",
                onTap: () => _toggleTile(code),
                child: _menuRow(_visible.contains(code) ? Icons.remove_circle_outline : Icons.add_circle_outline, code),
              ),
          ],
        )
      ),
    );
  }

  // a dropdown menu entry with a leading icon
  Widget _menuRow(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _itemsColors = List.generate(_items.length, (index) => Theme.of(context).cardColor.withValues(alpha: 0.6));

    // init everything
    _gpsListener();
    _routeListener();
    _timeListener();

    // (re)load tile positions when first built or when orientation changes
    bool portrait = Constants.isPortrait(context);
    if(_loadedPortrait != portrait || _positions.length != _items.length) {
      _loadPositions();
    }
    if(!_visibleLoaded) {
      _loadVisible();
    }

    // Full screen overlay. The Stack itself does not absorb touches in empty
    // areas, so the underlying map remains fully interactive; only the tiles
    // and the menu button receive gestures.
    return Stack(
      children: <Widget>[
        for(final String code in _visible)
          _makeInstrument(code),
        _makeMenu(),
      ],
    );
  }
}
