import 'dart:core';
import 'dart:ui' as ui;
import 'package:avaremp/gdl90/traffic_report_message.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:avaremp/gdl90/traffic_alerts.dart';
import 'package:avaremp/constants.dart';

import '../io/gps.dart';

const double _kMinutesPerMillisecond =  1.0 / 60000.0;

enum TrafficAlertLevel { none, advisory, resolution }

// Delay to allow audible alerts to not be constantly called with no updates, wasting CPU (uses async future to wait)
const int _kAudibleAlertCallMinDelayMs = 100;

class Traffic {

  final TrafficReportMessage message;
  double horizontalOwnshipDistanceNmi = 0;
  double verticalOwnshipDistanceFt = 0;
  double closingInSeconds = -1;
  double closestApproachDistanceNmi = 999999;
  TrafficAlertLevel alertLevel = TrafficAlertLevel.none;

  Traffic(this.message) {
    updateOwnshipDistancesAndAlertFields();
  }

  /// Update traffic distinces (horizontal and vertical) to ownship
  void updateOwnshipDistancesAndAlertFields() {
    // Use Haversine distance for speed/battery-efficiency instead of Vicenty, as the margin of error at these 
    // distances (for these purposes) is neglible (0.3% max, within 100 miles)
    // horizontalOwnshipDistance = GeoCalculations().calculateDistance(Gps.toLatLng(Storage().position), message.coordinates);
    horizontalOwnshipDistanceNmi = GeoCalculations().calculateDistance(Gps.toLatLng(Storage().position), message.coordinates);
    // final double vicentyDist = GeoCalculations().calculateDistance(Gps.toLatLng(Storage().position), message.coordinates);
    // if (vicentyDist < 100 || horizontalOwnshipDistanceNmi < 100) {
    //   print("Haversine is $horizontalOwnshipDistanceNmi and Vicenty is $vicentyDist, for a diff of ${horizontalOwnshipDistanceNmi-vicentyDist} or ${(horizontalOwnshipDistanceNmi-vicentyDist)/vicentyDist*100}%");
    // }    
    verticalOwnshipDistanceFt = Storage().units.mToF * Storage().position.altitude - message.altitude;
    TrafficAlerts.setTrafficAlertFields(this, Storage().position, Storage().airborne, Storage().vSpeed);
  }

  bool isOld() {
    // old if more than 1 min
    //return DateTime.now().difference(message.time).inMinutes > 0;
    return (DateTime.now().millisecondsSinceEpoch - message.time.millisecondsSinceEpoch) * _kMinutesPerMillisecond > 1; // CPU flameshart => optimization
  }

  /// Pixel size of the [Marker] used to render this traffic icon.
  /// The [TrafficPainter] circle is centered exactly at the marker's anchor
  /// point so that the on-map projection line appears to emerge from the
  /// center of the circle (and is masked by the circle until it exits the
  /// dot).
  static const double iconWidth = 200;
  static const double iconHeight = 64;
  static const double _kCircleHalf = TrafficPainter._kCanvasSize / 2;
  static const double _kLabelLeft = iconWidth / 2 + _kCircleHalf;
  static const double _kCircleTop = iconHeight / 2 - _kCircleHalf;

  Widget getIcon(double angle) {
    return SizedBox(
      width: iconWidth,
      height: iconHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Vertical-status text label (flight-level diff + vertical-trend arrow)
          Positioned(
            left: _kLabelLeft,
            top: _kCircleTop,
            child: CustomPaint(
              painter: TrafficVerticalStatusPainter(this),
              size: const Size(96, 24),
            ),
          ),
          // Callsign / ID text label, sits below the vertical-status label
          Positioned(
            left: _kLabelLeft,
            top: _kCircleTop + 20,
            child: CustomPaint(
              painter: TrafficIdPainter(this),
              size: const Size(140, 24),
            ),
          ),
          // Centered Avare-style circle dot at the marker's anchor point
          Positioned(
            left: iconWidth / 2 - _kCircleHalf,
            top: iconHeight / 2 - _kCircleHalf,
            child: CustomPaint(
              painter: TrafficPainter(this),
              size: const Size(TrafficPainter._kCanvasSize, TrafficPainter._kCanvasSize),
            ),
          ),
        ],
      ),
    );
  }

  LatLng getCoordinates() {
    return message.coordinates;
  }

  /// Returns the projected position 1 minute in the future at current velocity/heading.
  /// Distance is in user units (nm or mi) per the active unit conversion.
  LatLng getOneMinuteProjection() {
    final double distanceInUserUnits = message.velocity * Storage().units.mpsTo / 60.0;
    return GeoCalculations().calculateOffset(message.coordinates, distanceInUserUnits, message.heading);
  }

  /// Whether this traffic should be highlighted as a threat (advisory or resolution alert).
  bool get isThreat => alertLevel != TrafficAlertLevel.none;

  @override
  String toString() {
    return "${message.callSign}\n${message.altitude.toInt()} ft\n"
    "${(message.velocity * Storage().units.mpsTo).toInt()} ${Storage().settings.getUnits() == "Imperial" ? "mph" : "knots" }\n"
    "${(message.verticalSpeed * Storage().units.mToF).toInt()} fpm";
  }
}


class TrafficCache {

  List<Traffic?> _traffic = [];
  late int _kTrafficAltDiffThresholdFt;
  late int _kTrafficDistanceDiffThresholdNm;
  late int maxEntries;

  void changeArea(String size) {
    // puck size S, M, L
    maxEntries =                        size == "S" ? 20    : (size == "M" ? 200   : 1000);
    _kTrafficAltDiffThresholdFt =       size == "S" ? 3000  : (size == "M" ? 6000  : 30000);
    _kTrafficDistanceDiffThresholdNm =  size == "S" ? 10    : (size == "M" ? 50    : 500);
    List<Traffic?> t = List.filled(maxEntries + 1, null);
    if(t.length < _traffic.length) {
      // shrink
      for(int i = 0; i < t.length; i++) {
        t[i] = _traffic[i];
      }
    } else {
      // expand
      for(int i = 0; i < _traffic.length; i++) {
        t[i] = _traffic[i];
      }
    }
    _traffic = t;
  }

  TrafficCache(String size) {
    changeArea(size);
  }

  static final bool ac20_172Mode = true;
  bool _audibleAlertsRequested = false;
  bool _audibleAlertsHandling = false;

  static String adjustPuck(String input) {
    String output = "S";
    switch (input) {
      case "S":
        output = "M";
        break;
      case "M":
        output = "L";
        break;
      case "L":
        output = "S";
        break;
    }
    return output;
  }

  // Moving the raw calculation into constructor of Traffic, and the vertical distance heuristic into the sort method
  // where it is used
  // double findDistance(LatLng coordinate, double altitude) {
  //   // find 3d distance between current position and airplane
  //   // treat 1 mile of horizontal distance as 500 feet of vertical distance (C182 120kts, 1000 fpm)
  //   LatLng current = Gps.toLatLng(Storage().position);
  //   double horizontalDistance = GeoCalculations().calculateDistance(current, coordinate) * 500;
  //   double verticalDistance   = (Storage().position.altitude * 3.28084 - altitude).abs();
  //   double fac = horizontalDistance + verticalDistance;
  //   return fac;
  // }

  void putTraffic(TrafficReportMessage message) {

    // filter own report. Guard against unset defaults (ICAO 0 / empty callsign)
    // so anonymous TIS-B targets (track-file targets often report ICAO 0 and no
    // callsign) are not mistaken for ownship and discarded.
    final int icao = message.icao;
    final int ownshipIcao = Storage().ownshipMessageIcao;
    final int myAircraftIcao = Storage().myAircraftIcao;
    final String myAircraftCallsign = Storage().myAircraftCallsign;
    if((icao != 0 && (icao == ownshipIcao || icao == myAircraftIcao))
      || (myAircraftCallsign.isNotEmpty && message.callSign.isNotEmpty && myAircraftCallsign == message.callSign))
    {
      // do not add ourselves
      message.filter = TrafficFilter.ownship;
      return;
    }

    for(int i = 0; i < _traffic.length; i++) {
      if(_traffic[i] == null) {
        continue;
      }
      if(_traffic[i]?.isOld() ?? false) {
        _traffic[i] = null;
        // purge old
        continue;
      }

      // update
      if(_traffic[i]?.message.icao == message.icao) {
        // call sign not available. use last one
        if(message.callSign.isEmpty) {
          message.callSign = _traffic[i]?.message.callSign ?? "";
        }
        final Traffic trafficNew = Traffic(message);
        // only display/alert traffic that isn't too far from ownship
        if (trafficNew.verticalOwnshipDistanceFt.abs() > _kTrafficAltDiffThresholdFt ||
          trafficNew.horizontalOwnshipDistanceNmi > _kTrafficDistanceDiffThresholdNm) {
           _traffic[i] = null;
           message.filter = TrafficFilter.range;
           Storage().trafficChange.value++; // traffic removed
          return;
        }

        _traffic[i] = trafficNew;
        Storage().trafficChange.value++; // traffic updated

        // process any audible alerts from traffic (if enabled)
        handleAudibleAlerts();

        return;
      }
    }

    // put it in the end
    final Traffic trafficNew = Traffic(message);
    // only display/alert traffic that isn't too far from ownship
    if (trafficNew.verticalOwnshipDistanceFt.abs() > _kTrafficAltDiffThresholdFt ||
      trafficNew.horizontalOwnshipDistanceNmi > _kTrafficDistanceDiffThresholdNm) {
      message.filter = TrafficFilter.range;
      return;
    }    
    _traffic[maxEntries] = trafficNew;

    // sort
    _traffic.sort(_trafficSort);
    Storage().trafficChange.value++; // new traffic added

    // process any audible alerts from traffic (if enabled)
    handleAudibleAlerts();

  }

  int _trafficSort(Traffic? left, Traffic? right) {
    if(null == left && null != right) {
      return 1;
    }
    if(null != left && null == right) {
      return -1;
    }
    if(null == left && null == right) {
      return 0;
    }
    if(null != left && null != right) {
      // Use 3d distance between current position and airplane
      // treat 1 mile of horizontal distance as 500 feet of vertical distance (C182 120kts, 1000 fpm)      
      double l = left.horizontalOwnshipDistanceNmi * 500 + left.verticalOwnshipDistanceFt.abs();
      double r = right.horizontalOwnshipDistanceNmi * 500 + right.verticalOwnshipDistanceFt.abs();
      if(l > r) {
        return 1;
      }
      if(l < r) {
        return -1;
      }
    }
    return 0;
  }

  void handleAudibleAlerts() {
    // If alerts are running or in the required delay, don't kick off processing again--just note that we want another run later
    if (_audibleAlertsHandling) {
      _audibleAlertsRequested = true;
      return;
    }
    // process when traffic layer is on
    if (Storage().settings.isAudibleAlertsEnabled() && Storage().cachedTrafficLayerOn) {
      _audibleAlertsHandling = true;   
      TrafficAlerts.getAndStartTrafficAlerts().then((alerts) {
        // TODO: Set all of the "pref" settings from new Storage params (which in turn have a config UI?)
        alerts?.processTrafficForAudibleAlerts(_traffic, Storage().position, Storage().lastMsGpsSignal, Storage().vSpeed,
          Storage().airborne);
        _audibleAlertsRequested = false;
        Future.delayed(const Duration(milliseconds: _kAudibleAlertCallMinDelayMs), () {
          _audibleAlertsHandling = false;
          if (_audibleAlertsRequested) {
            Future(handleAudibleAlerts);
          }
        });
      });
    } else {
      TrafficAlerts.stopAudibleTrafficAlerts();
    }
  }

  /// Recalcs all traffic cache distances (e.g., from an ownship position update), then calls audible alerts
  void updateTrafficDistancesAndAlerts() {
    // Make async event to avoid blocking UI thread for recalcs and alerts
    Future(() {
      for (int i = 0; i < _traffic.length; i++) {
        _traffic[i]?.updateOwnshipDistancesAndAlertFields();
        // only display/alert traffic that isn't too far from ownship
        if ((_traffic[i]?.verticalOwnshipDistanceFt.abs() ?? 0) > _kTrafficAltDiffThresholdFt) {
          _traffic[i] = null;
        }        
      }
      // refresh traffic map layers (also carries ownship heading changes that
      // rotate the icons in track-up); runs ~1 Hz as a gpsChange listener
      Storage().trafficChange.value++;
    }).then((value) => handleAudibleAlerts());
  }

  List<Traffic> getTraffic() {
    List<Traffic> ret = [];

    for(Traffic? check in _traffic) {
      if(null != check) {
        if(check.isOld()) {
          // do not show old
          continue;
        }
        ret.add(check);
      }
    }
    return ret;
  }
}

/// Avare-style simple traffic icon: a small filled circle with a black outline.
/// Cyan for normal/proximate traffic, red for threat (advisory or resolution) traffic,
/// brown for ground traffic. The directional/1-minute projection line is rendered
/// separately on the map (in real coordinates) by the traffic layer in `map_screen.dart`.
class TrafficPainter extends AbstractCachedCustomPainter {

  static const double _kCanvasSize = 32;
  static const double _kCenter = _kCanvasSize / 2;
  static const double _kCircleRadius = 7;
  static const double _kOutlineWidth = 2;

  static const double _kMetersToFeetCont = 3.28084;
  static const double _kGroundTrafficOpacity = 0.5;

  // Avare-style fill colors
  static const Color kProximateColor = Colors.cyan;       // normal, no alert
  static const Color kAdvisoryColor = Color(0xFFFF3535);  // threat
  static const Color kResolutionColor = Color(0xFFFF3535); // threat
  static const Color _kGroundColor = Color(0xFF836539);   // brown for ground traffic
  static const Color _kOutlineColor = Color(0xFF000000);  // black outline

  final TrafficAlertLevel _alertLevel;
  final bool _isAirborne;

  TrafficPainter(Traffic traffic)
    : _alertLevel = traffic.alertLevel,
      _isAirborne = traffic.message.airborne,
      super([traffic.alertLevel.index, traffic.message.airborne ? 1 : 0],
        false, const Size(_kCanvasSize, _kCanvasSize));

  @override
  void freshPaint(Canvas canvas) {
    final double opacity = _isAirborne ? 1.0 : _kGroundTrafficOpacity;

    final Color fillColor;
    if (!_isAirborne) {
      fillColor = _kGroundColor;
    } else if (_alertLevel == TrafficAlertLevel.none) {
      fillColor = kProximateColor;
    } else {
      fillColor = kAdvisoryColor;
    }

    const Offset center = Offset(_kCenter, _kCenter);
    canvas.drawCircle(center, _kCircleRadius,
      Paint()..color = fillColor.withValues(alpha: opacity));
    canvas.drawCircle(center, _kCircleRadius,
      Paint()
        ..color = _kOutlineColor.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _kOutlineWidth);
  }

  @pragma("vm:prefer-inline")
  static int getVerticalSpeedDirection(double verticalSpeedMps) {
    if (verticalSpeedMps * _kMetersToFeetCont < -100) {
      return -1;
    } else if (verticalSpeedMps * _kMetersToFeetCont > 100) {
      return 1;
    } else {
      return 0;
    }
  }
}

/// Painter for traffic vertical status text box (+/- flight level, and vertical speed direction arrows)
class TrafficVerticalStatusPainter extends AbstractCachedCustomPainter {
  static const double _vertLocationFontSize = 16, _vertSpeedArrowFontSize = 24;
  static const _vertLocationTextStyle = TextStyle(shadows: [Shadow(offset: Offset(2, 2))], color: Colors.white, fontWeight: FontWeight.w600, fontSize: _vertLocationFontSize);
  static const _vertSpeedArrowStyle = TextStyle(shadows: [Shadow(offset: Offset(2, 2))], color: Colors.white, fontWeight: FontWeight.w900, fontSize: _vertSpeedArrowFontSize);
  static final _boundingBoxPaint = Paint()..color = const Color.fromRGBO(0, 0, 0, .2);
  static const double _offsetX = 0, _offsetY = 0;
  static const double _charPixeslWidth = 10;

  /// Bumped whenever the rendered text format changes so that the static
  /// in-memory image cache (in [AbstractCachedCustomPainter]) does not return a
  /// stale rasterization across hot reloads. Increment when the format string,
  /// fonts, sizes, or layout offsets are changed.
  static const int _formatVersion = 2;

  final int _flightLevelDiff;
  final int _vspeedDirection;
  final bool _isAirborne;

  TrafficVerticalStatusPainter(Traffic t):
    _flightLevelDiff = getFlightLevelDiff(t),
    _vspeedDirection = TrafficPainter.getVerticalSpeedDirection(t.message.verticalSpeed),
    _isAirborne = t.message.airborne,
    super([_formatVersion, getFlightLevelDiff(t), TrafficPainter.getVerticalSpeedDirection(t.message.verticalSpeed), t.message.airborne ? 1 : 0], false,
      const Size(96, 32));

  /// Format a flight-level diff as a signed, zero-padded 3-digit string.
  /// Examples: 60 -> "+060", -60 -> "-060", 6 -> "+006", 0 -> "000", 100 -> "+100", -1234 -> "-1234".
  static String formatFlightLevelDiff(int flightLevelDiff) {
    final int absVal = flightLevelDiff.abs();
    final String absStr = absVal < 100 ? absVal.toString().padLeft(3, '0') : absVal.toString();
    if (flightLevelDiff > 0) {
      return '+$absStr';
    } else if (flightLevelDiff < 0) {
      return '-$absStr';
    }
    return absStr;
  }

  @override
  void freshPaint(ui.Canvas canvas) {
    if (!_isAirborne) {
      return;
    }

    final String vertLocationMsg = formatFlightLevelDiff(_flightLevelDiff);
    final String directionText = (_vspeedDirection > 0 ? "↑" : (_vspeedDirection < 0 ? "↓": ""));
    // Draw transluscent bounding box for greater visibility (especially sectionals)
    final ui.Path statusBoundingBox = ui.Path()
      ..addRect(Rect.fromLTRB(_offsetX, _offsetY, _offsetX+(vertLocationMsg.length+directionText.length)*_charPixeslWidth+_charPixeslWidth, _offsetY+24));
    canvas.drawPath(statusBoundingBox, _boundingBoxPaint);
    // Paint vertical position. Use unbounded maxWidth so text never wraps and
    // hides a leading-zero digit (e.g. "+060" being collapsed to "+06" / "+0").
    final vertLocationTextPainter = TextPainter(text: TextSpan(text: vertLocationMsg, style: _vertLocationTextStyle), textDirection: TextDirection.ltr);
    vertLocationTextPainter.layout(
      minWidth: 0,
      maxWidth: double.infinity,
    );
    vertLocationTextPainter.paint(canvas, const Offset(_offsetX, _offsetY));
    // Paint ascending/descending direction arrows (if not flying level)
    if (directionText.isNotEmpty) {
      final verticalSpeedTextPainter = TextPainter(text: TextSpan(text: directionText, style: _vertSpeedArrowStyle), textDirection: TextDirection.ltr);
      verticalSpeedTextPainter.layout(
        minWidth: 0,
        maxWidth: double.infinity,
      );
      verticalSpeedTextPainter.paint(canvas, Offset(_offsetX + vertLocationTextPainter.width + 2, _offsetY-(_vertSpeedArrowFontSize-_vertLocationFontSize)));
    }
  }

  /// get flight level
  @pragma("vm:prefer-inline")
  static int getFlightLevelDiff(final Traffic traffic) {
    return -(traffic.verticalOwnshipDistanceFt / 100).round();
  }
}

/// Painter for traffic identifier (N-number if in ADSB message, ICAO number if not)
class TrafficIdPainter extends AbstractCachedCustomPainter {
  static const double _trafficIdFontSize = 16;
  static final _boundingBoxPaint = Paint()..color = const Color.fromRGBO(0, 0, 0, .2);
  static const _trafficIdTextStyle = TextStyle(shadows: [Shadow(offset: Offset(2, 2))], color: Colors.white, fontWeight: FontWeight.w600, fontSize: _trafficIdFontSize);
  static const double _offsetX = 0, _offsetY = 0;
  static const double _charPixeslWidth = 12;

  final String _trafficId;
  final bool _isAirborne;

  TrafficIdPainter(final Traffic t): 
    _trafficId = t.message.callSign.isNotEmpty ? t.message.callSign : t.message.icao.toString(),
    _isAirborne = t.message.airborne,
    super([ (t.message.callSign.isNotEmpty ? t.message.callSign : t.message.icao.toString()).hashCode, t.message.airborne ? 1 : 0 ], 
      false, Size((t.message.callSign.isNotEmpty ? t.message.callSign : t.message.icao.toString()).length*_charPixeslWidth+24, 42));
    
  @override
  void freshPaint(ui.Canvas canvas) {
    if (!_isAirborne) { // Don't clutter UI with ID's of aircraft on the ground--airports would be a mess
      return;
    }
    // paint transluscent bounding box
    final ui.Path statusBoundingBox = ui.Path()
      ..addRect(Rect.fromLTRB(_offsetX, _offsetY, _offsetX+(_trafficId.length)*_charPixeslWidth+_charPixeslWidth, _offsetY+32));
    canvas.drawPath(statusBoundingBox, _boundingBoxPaint);
    // paint traffic ID
    final trafficIdTextPainter = TextPainter(text: TextSpan(text: _trafficId, style: _trafficIdTextStyle), textDirection: TextDirection.ltr);
    trafficIdTextPainter.layout(
      minWidth: 0,
      maxWidth: _trafficId.length*_charPixeslWidth,
    );    
    trafficIdTextPainter.paint(canvas, const Offset(_offsetX, _offsetY));    
  }
}

/// Abstract custom painter helper that maintains a picture (graphical ops) or raster (image pixels) cache, as configured
abstract class AbstractCachedCustomPainter extends CustomPainter {

  /// Static caches, for faster rendering of the same icons, based on UI state
  static final Map<int,ui.Picture> _pictureCache = {};  // Graphical operations cache (for realtime rasterization config, e.g., shadow on)
  static final Map<int,ui.Image> _imageCache = {};      // Rasterized pixel image cache (for non-realtime config, e.g., no shadow off)

  /// Unique key of icon state based on flight properties above that define the icon appearance, per the current
  /// configuration of enabled features.  This is used to determine UI-relevant state changes for repainting,
  /// as well as the key to the picture cache  
  int _uiStateKey = 0;
  /// Can we use a raster/image cache, or does each image need to re-rasterize (i.e., we can only cache the picture, which is the graphical ops)
  final bool _isRealtimeRasterizationRequired;
  final ui.Size _maxSize;

  AbstractCachedCustomPainter(final List<int> stateKeyComponents, bool isRealtimeRasterizationRequired,
    ui.Size maxSize):
    _isRealtimeRasterizationRequired = isRealtimeRasterizationRequired,
    _maxSize = maxSize
  {
    _uiStateKey = Constants.hashInts([ runtimeType.hashCode ] + stateKeyComponents);
  }

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    // Used cached rasterized (pixel) image if possible
    if (!_isRealtimeRasterizationRequired) {
      final ui.Image? cachedImage = _imageCache[_uiStateKey];  
      if (cachedImage != null) {
        paintImage(canvas: canvas, rect: Rect.fromLTWH(0, 0, cachedImage.width*1.0, cachedImage.height*1.0), image: cachedImage);
        return;
      }
    }

    // ...otherwise, use cached picture (pre-rasterization graphical operations) if possible
    final ui.Picture? cachedPicture = _pictureCache[_uiStateKey];
    final ui.Picture picture;
    if (cachedPicture != null) {
      picture = cachedPicture;        
    } else {
      // ...otherwise, create a new picture, and save it to the raster/image caches as appropriate
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas drawingCanvas = Canvas(recorder);   

      freshPaint(drawingCanvas); 

      // store this fresh image to the cache(s) for quick and efficient rendering next time
      final ui.Picture newPicture = recorder.endRecording();
      _pictureCache[_uiStateKey] = newPicture;
      picture = newPicture;
    } 
    
    // Cache pixels of image to image cache, to save rasterization next time, if possible, and paint image
    if (!_isRealtimeRasterizationRequired) {
      picture.toImage(_maxSize.width.ceil(), _maxSize.height.ceil()).then((newImage) {
        _imageCache[_uiStateKey] = newImage;
      });
    }
    canvas.drawPicture(picture);
  }

  /// Abstract hook for implementing painter to paint the custom UI
  void freshPaint(ui.Canvas canvas);

  @override
  bool shouldRepaint(covariant AbstractCachedCustomPainter oldDelegate) {
    return oldDelegate._uiStateKey != _uiStateKey;
  }
}