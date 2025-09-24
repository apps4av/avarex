import 'dart:core';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:intl/intl.dart' as intl;
import 'package:avaremp/gdl90/traffic_report_message.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:avaremp/gdl90/traffic_alerts.dart';
import 'package:avaremp/constants.dart';

import '../gps.dart';

const double _kDivBy180 = 1.0 / 180.0;
const double _kMinutesPerMillisecond =  1.0 / 60000.0;
const int _kTrafficAltDiffThresholdFt = 3000;
const int _kTrafficDistanceDiffThresholdNm = 10;

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

  Widget getIcon(bool northUp, bool isAudibleAlertsEnabled) {
    return Row(children:[
          Stack(children: [
            CustomPaint(painter: AlertBoxPainter(this)),
            Transform.rotate(
              angle: (message.heading + 180.0 /* Image painted down on coordinate plane */ 
                - (northUp ? 0 : Storage().position.heading)) * pi  * _kDivBy180,
              origin: const Offset(15, 15),
              child: CustomPaint(painter: TrafficPainter(this))
            ),
          ]),
          CustomPaint(painter: TrafficVerticalStatusPainter(this)),
          CustomPaint(painter: TrafficIdPainter(this))  // TODO: Maybe make this switchable config item down the line?
    ]);
  }

  LatLng getCoordinates() {
    return message.coordinates;
  }

  @override
  String toString() {
    return "${message.callSign}\n${message.altitude.toInt()} ft\n"
    "${(message.velocity * Storage().units.mpsTo).toInt()} ${Storage().settings.getUnits() == "Imperial" ? "mph" : "knots" }\n"
    "${(message.verticalSpeed * Storage().units.mToF).toInt()} fpm";
  }
}


class TrafficCache {
  static const int maxEntries = 20;
  final List<Traffic?> _traffic = List.filled(maxEntries + 1, null); // +1 is the empty slot where new traffic is added
  static const bool ac20_172Mode = true;

  bool _audibleAlertsRequested = false;
  bool _audibleAlertsHandling = false;

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

    // filter own report
    if(message.icao == Storage().ownshipMessageIcao 
      || Storage().myAircraftIcao == message.icao
      || Storage().myAircraftCallsign == message.callSign) 
    {
      // do not add ourselves
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
          return;
        }

        _traffic[i] = trafficNew;

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
      return;
    }    
    _traffic[maxEntries] = trafficNew;

    // sort
    _traffic.sort(_trafficSort);

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
    if (Storage().settings.isAudibleAlertsEnabled()) {
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

enum _TrafficAircraftIconType { unmapped, light, large, rotorcraft }

/// Icon painter for different traffic aircraft types (ADSB emitter category) and flight status
class TrafficPainter extends AbstractCachedCustomPainter {

  // Preference control variables
  static const bool prefShowSpeedBarb = false;                    // Shows line/barb at tip of icon based on speed/velocity
  static const bool prefAltDiffOpacityGraduation = false;         // Gradually vary opacity of icon based on altitude diff from ownship
  static const bool prefUseDifferentDefaultIconThanLight = false; // Use a different default icon for unmapped or "0" emitter category ID traffic
  static const bool prefShowBoundingBox = false;                  // Display outlined bounding box around icon for higher visibility
  static const bool prefShowShadow = false;                       // Display shadow effect "under" aircraft for higher visibility
  static const bool prefShowShapeOutline = true;                  // Display solid outline around aircraft for higher visibility

  // Const's for magic #'s and division speedup
  static final double _kMetersToFeetCont = Storage().units.mToF;
  static final double _kMetersPerSecondToSpeed = Storage().units.mpsTo;
  static const double _kDivBy60Mult = 1.0 / 60.0;
  static const double _kDivBy1000Mult = 1.0 / 1000.0;
  // UI Default constants
  static const double _kTrafficOpacityMin = 0.2;
  static const double _kFlyingTrafficOpacityMax = 1.0;
  static const double _kGroundTrafficOpacityMax = 0.5;
  static const double _kFlightLevelOpacityReduction = 0.2;  // very few levels now, so up reduction to 20%
  static const double _kBoundingBoxOpacityReduction = 0.4;
  static const double _kBoundingBoxOpacityMin = 0.1;  
  static const int _kShadowDrawPasses = 2;
  static const double _kShadowElevation = 5.0;
  // Colors for different aircraft heights, and contrasting overlays
  static const Color _kLevelColor = Color(0xFFBDAED1);           // Level traffic = Purplish
  static const Color _kHighColor = Color(0xFF00DFFF);            // High traffic = Cyanish
  static const Color _kLowColor = Color(0xFF65FE08);             // Low traffic = Lime Green
  static const Color _kGroundColor = Color(0xFF836539);          // Ground traffic = Brown
  static const Color _kDarkForegroundColor = Color(0xFF000000);  // Overlay color = Black
  static const Color kAdvisoryColor = Colors.orange;
  static const Color kResolutionColor = Color(0xFFFF3535);
  static const Color kProximateColor = Colors.cyan;

  // Aircraft type outlines
  static final ui.Path _largeAircraft = _unionPaths([
    // body
    ui.Path()..addOval(const Rect.fromLTRB(12, 5, 19, 31)),
    ui.Path()..addRect(const Rect.fromLTRB(12, 11, 19, 20)),
    ui.Path()..addOval(const Rect.fromLTRB(12, 0, 19, 25)),
    // left wing
    ui.Path()..addPolygon([ const Offset(0, 13), const Offset(0, 16), const Offset(15, 22), const Offset(15, 14) ], true), 
    // left engine
    ui.Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(6, 17, 10, 24), const Radius.circular(1))),
    // left h-stabilizer
    ui.Path()..addPolygon([ const Offset(9, 0), const Offset(9, 3), const Offset(15, 7), const Offset(15, 1) ], true),
    // right wing
    ui.Path()..addPolygon([ const Offset(31, 13), const Offset(31, 16), const Offset(17, 22), const Offset(17, 14) ], true),
    // right engine
    ui.Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(21, 17, 25, 24), const Radius.circular(1))),
    // right h-stabilizer
    ui.Path()..addPolygon([ const Offset(22, 0), const Offset(22, 3), const Offset(16, 7), const Offset(16, 1) ], true)
  ]);
  static final ui.Path _defaultAircraft = ui.Path()  // old default icon if no ICAO ID--just a triangle
    ..addPolygon([ const Offset(5, 5), const Offset(15, 26), const Offset(16, 26), const Offset(26, 5), 
      const Offset(16, 13), const Offset(15, 13) ], true);
  static final ui.Path _lightAircraft = _unionPaths([
    ui.Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(12, 18, 19, 31), const Radius.circular(2))), // body
    ui.Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(0, 18, 31, 25), const Radius.circular(1))), // wings
    ui.Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(10, 0, 21, 5), const Radius.circular(1))),  // h-stabilizer
    ui.Path()..addPolygon([ const Offset(12, 20), const Offset(14, 4), const Offset(17, 4), const Offset(19, 20)], true) // rear body
  ]);
  static final ui.Path _rotorcraft = _unionPaths([
    // body
    ui.Path()..addOval(const Rect.fromLTRB(9, 11, 22, 31)), 
    // rotor blades
    ui.Path()..addPolygon([const Offset(27, 11), const Offset(29, 13), const Offset(4, 31), const Offset(2, 29)], true),
    ui.Path()..addPolygon([const Offset(4, 11), const Offset(2, 13), const Offset(27, 31), const Offset(29, 29) ], true),
    // tail
    ui.Path()..addRect(const Rect.fromLTRB(14, 0, 17, 12)),
    // horizontal stabilizer
    ui.Path()..addRRect(RRect.fromLTRBR(10, 3, 21, 7, const Radius.circular(1)))
  ]);
  // vertical speed plus/minus overlays
  static final ui.Path _plusSign = _unionPaths([
    ui.Path()..addPolygon([ const Offset(14, 13), const Offset(14, 22), const Offset(17, 22), const Offset(17, 13) ], true),  // downstroke
    ui.Path()..addPolygon([ const Offset(11, 16), const Offset(20, 16), const Offset(20, 19), const Offset(11, 19) ], true)   // cross-stroke
  ]);
  static final ui.Path _minusSign = ui.Path()
    ..addPolygon([ const Offset(11, 16), const Offset(20, 16), const Offset(20, 19), const Offset(11, 19) ], true);
  static final ui.Path _lowerPlusSign = _unionPaths([
    ui.Path()..addPolygon([ const Offset(14, 17), const Offset(14, 26), const Offset(17, 26), const Offset(17, 17) ], true),  // downstroke
    ui.Path()..addPolygon([ const Offset(11, 20), const Offset(20, 20), const Offset(20, 23), const Offset(11, 23) ], true)   // cross-stroke
  ]);
  static final ui.Path _lowerMinusSign = ui.Path()
    ..addPolygon([ const Offset(11, 20), const Offset(20, 20), const Offset(20, 23), const Offset(11, 23) ], true);
  // Translucent bounding box shape
  static final ui.Path _boundingBox = ui.Path()
    ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(0, 0, 31, 31), const Radius.circular(3)));    
  
  // Discrete icon state variables used to determine UI
  final _TrafficAircraftIconType _aircraftType;
  final TrafficAlertLevel _alertLevel;
  final bool _isAirborne;
  final int _flightLevelDiff;
  final int _vspeedDirection;
  final int _velocityLevel;

  TrafficPainter(Traffic traffic) 
    : _aircraftType = _getAircraftIconType(traffic.message.emitter), 
      _isAirborne = traffic.message.airborne,
      _flightLevelDiff = prefAltDiffOpacityGraduation || !TrafficCache.ac20_172Mode ? _getGrossFlightLevelDiff(traffic) : 0, 
      _vspeedDirection = !TrafficCache.ac20_172Mode ? getVerticalSpeedDirection(traffic.message.verticalSpeed) : 0,
      _velocityLevel = prefShowSpeedBarb ? _getVelocityLevel(traffic.message.velocity) : 0,
      _alertLevel = traffic.alertLevel,
      super([ _getAircraftIconType(traffic.message.emitter).index, traffic.message.airborne ? 1 : 0, 
        prefAltDiffOpacityGraduation || !TrafficCache.ac20_172Mode ? _getGrossFlightLevelDiff(traffic) : 0, // no variation on alt diff if no opacity gradation or in AC 20-172 mode
        !TrafficCache.ac20_172Mode ? getVerticalSpeedDirection(traffic.message.verticalSpeed) : 0, // No variation for +/- overlay if AC 20-172 mode 
        prefShowSpeedBarb ? _getVelocityLevel(traffic.message.velocity) : 0, traffic.alertLevel.index ], prefShowShadow, const Size(32, 32));

  /// Paint arcraft, vertical speed direction overlay, and optionially (horizontal) speed barb
  @override 
  void freshPaint(Canvas canvas) {

    final double opacity;
    if (prefAltDiffOpacityGraduation) {
      // Decide opacity, based on vertical distance from ownship and whether traffic is on the ground. 
      // Traffic far above or below ownship will be quite transparent, to avoid clutter, and 
      // ground traffic has a 50% max opacity / min transparency to avoid taxiing or stationary (ADSB-initilized)
      // traffic from flooding the map. Opacity decrease is 10% for every 1000 foot diff above or below, with a 
      // floor of 20% total opacity (i.e., max 80% transparency)        
      opacity = min(max(_kTrafficOpacityMin, 
          (_isAirborne ? _kFlyingTrafficOpacityMax : _kGroundTrafficOpacityMax) - _flightLevelDiff * _kFlightLevelOpacityReduction), 
          _isAirborne ? _kFlyingTrafficOpacityMax : _kGroundTrafficOpacityMax);
    } else {
      opacity = _isAirborne ? 1.0 : _kGroundTrafficOpacityMax;
    }    

    // Define aircraft, barb, accent/overlay colors and paint using above opacity
    final Paint aircraftPaint;
    if (!_isAirborne) {
      aircraftPaint = Paint()..color = _kGroundColor.withValues(alpha: opacity);
    } else if (TrafficCache.ac20_172Mode) {
      if (_alertLevel == TrafficAlertLevel.advisory) {
        aircraftPaint = Paint()..color = kAdvisoryColor.withValues(alpha: opacity);
      } else if (_alertLevel == TrafficAlertLevel.resolution) {
        aircraftPaint = Paint()..color = kResolutionColor.withValues(alpha: opacity);
      } else {
        aircraftPaint = Paint()..color = kProximateColor.withValues(alpha: opacity);
      }
    } else if (_flightLevelDiff < 0) {
      aircraftPaint = Paint()..color = _kHighColor.withValues(alpha: opacity);
    } else if (_flightLevelDiff > 0) {
      aircraftPaint = Paint()..color = _kLowColor.withValues(alpha: opacity);
    } else {
      aircraftPaint = Paint()..color = _kLevelColor.withValues(alpha: opacity);
    }
    final Color darkAccentColor = _kDarkForegroundColor.withValues(alpha: opacity);

    // Set aircraft shape
    final ui.Path baseIconShape;
    switch(_aircraftType) {
      case _TrafficAircraftIconType.light:
        baseIconShape = ui.Path.from(_lightAircraft);
        break;           
      case _TrafficAircraftIconType.large:
        baseIconShape = ui.Path.from(_largeAircraft);
        break;
      case _TrafficAircraftIconType.rotorcraft:
        baseIconShape = ui.Path.from(_rotorcraft);
        break;
      default:
        baseIconShape = (prefUseDifferentDefaultIconThanLight || TrafficCache.ac20_172Mode 
          ? ui.Path.from(_defaultAircraft) : ui.Path.from(_lightAircraft));
    }            

    if (prefShowSpeedBarb && _velocityLevel > 0) {
      // Create speed barb based on current velocity and add to plane shape, for one-shot rendering (saves time/resources)
      baseIconShape.addPath(ui.Path()..addRect(Rect.fromLTWH(14, 31, 3, _velocityLevel*2.0)), const Offset(0, 0));
    }

    if (prefShowBoundingBox) {
      // Draw translucent bounding box for greater visibility (especially sectionals)
      canvas.drawPath(_boundingBox, 
        Paint()..color = _kDarkForegroundColor.withValues(alpha:
          // Have box fill opacity be a certain % less, but track main icon, with a floor of the traffic opacity min
          max(opacity - _kBoundingBoxOpacityReduction, _kBoundingBoxOpacityMin)));                 
    }

    if (prefShowShadow) {
      // Draw shadow for contrast on detailed backgrounds (especially sectionals)
      for (int i = 0; i < _kShadowDrawPasses; i++) {
        canvas.drawShadow(baseIconShape, darkAccentColor, _kShadowElevation, true);  
      }
    }

    // Draw aircraft (and speed barb, if feature enabled)
    canvas.drawPath(baseIconShape, aircraftPaint);

    if (prefShowShapeOutline) {
      // Draw solid outline on edge of aircraft for higher visibility
      canvas.drawPath(baseIconShape, Paint()
        ..color = darkAccentColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
      );
    }

    // Draw vspeed ("+/-") overlay if not level
    if (!TrafficCache.ac20_172Mode && _vspeedDirection != 0) {
      if (_aircraftType == _TrafficAircraftIconType.light || _aircraftType == _TrafficAircraftIconType.rotorcraft 
        || (!prefUseDifferentDefaultIconThanLight && _aircraftType == _TrafficAircraftIconType.unmapped)
      ) {
        canvas.drawPath(_vspeedDirection > 0 ? _lowerPlusSign : _lowerMinusSign, Paint()..color = darkAccentColor);
      } else {
        canvas.drawPath(_vspeedDirection > 0 ? _plusSign : _minusSign, Paint()..color = darkAccentColor);    
      }
    }  
  }

  @pragma("vm:prefer-inline")
  static _TrafficAircraftIconType _getAircraftIconType(int adsbEmitterCategoryId) {
    if (TrafficCache.ac20_172Mode) {
      return _TrafficAircraftIconType.unmapped;
    }
    switch(adsbEmitterCategoryId) {
      case 1: // Light (ICAO) < 15,500 lbs 
      case 2: // Small - 15,500 to 75,000 lbs 
        return _TrafficAircraftIconType.light;
      case 3: // Large - 75,000 to 300,000 lbs
      case 4: // High Vortex Large (e.g., aircraft such as B757) 
      case 5: // Heavy (ICAO) - > 300,000 lbs
        return _TrafficAircraftIconType.large;
      case 7: // Rotorcraft 
        return _TrafficAircraftIconType.rotorcraft;
      default:
        return _TrafficAircraftIconType.unmapped;
    }
  }

  /// Break flight levels into 1K chunks (bounding upper/lower to relevent opcacity limits to make image caching more efficient)
  @pragma("vm:prefer-inline")
  static int _getGrossFlightLevelDiff(final Traffic traffic) {
    return max(min((traffic.verticalOwnshipDistanceFt * _kDivBy1000Mult).round(), 8), -8);
  }

  @pragma("vm:prefer-inline")
  static int getVerticalSpeedDirection(double verticalSpeedMps) {
    if (verticalSpeedMps*_kMetersToFeetCont < -100) {
      return -1;
    } else if (verticalSpeedMps*_kMetersToFeetCont > 100) {
      return 1;
    } else {
      return 0;
    }
  }

  @pragma("vm:prefer-inline")
  static int _getVelocityLevel(double veloMps) {
    return (veloMps * _kMetersPerSecondToSpeed * _kDivBy60Mult).round();
  }  

  /// Recursive helper to join multiple paths together via a chained union operation
  static ui.Path _unionPaths(final List<ui.Path> paths) {
    if (paths.isEmpty) {
      throw "Illegal argument: List of paths must have at least one";
    }
    if (paths.length == 1) {
      return paths[0];
    }
    final ui.Path path1 = paths.removeAt(0);
    return ui.Path.combine(PathOperation.union, path1, _unionPaths(paths));
  }
}

/// Painter for traffic vertical status text box (+/- flight level, and vertical speed direction arrows)
class TrafficVerticalStatusPainter extends AbstractCachedCustomPainter {
  static const double _vertLocationFontSize = 16, _vertSpeedArrowFontSize = 24;
  static const _vertLocationTextStyle = TextStyle(shadows: [Shadow(offset: Offset(2, 2))], color: Colors.white, fontWeight: FontWeight.w600, fontSize: _vertLocationFontSize);
  static const _vertSpeedArrowStyle = TextStyle(shadows: [Shadow(offset: Offset(2, 2))], color: Colors.white, fontWeight: FontWeight.w900, fontSize: _vertSpeedArrowFontSize);
  static final _boundingBoxPaint = Paint()..color = const Color.fromRGBO(0, 0, 0, .2);
  static final _leadingZeroFmt = intl.NumberFormat("00");
  static const double _offsetX = 24, _offsetY = 0;
  static const double _charPixeslWidth = 10;

  final int _flightLevelDiff;
  final int _vspeedDirection;
  final bool _isAirborne;

  TrafficVerticalStatusPainter(Traffic t):  
    _flightLevelDiff = getFlightLevelDiff(t),
    _vspeedDirection = TrafficPainter.getVerticalSpeedDirection(t.message.verticalSpeed),
    _isAirborne = t.message.airborne,
    super([getFlightLevelDiff(t), TrafficPainter.getVerticalSpeedDirection(t.message.verticalSpeed), t.message.airborne ? 1 : 0], false, 
      const Size(96, 32));

  @override 
  void freshPaint(ui.Canvas canvas) {
    if (!_isAirborne) {
      return;
    }
    
    final String vertLocationMsg = (_flightLevelDiff > 0 ? "+" : "") + _leadingZeroFmt.format(_flightLevelDiff);
    final String directionText = (_vspeedDirection > 0 ? "↑" : (_vspeedDirection < 0 ? "↓": ""));
    // Draw transluscent bounding box for greater visibility (especially sectionals)
    final ui.Path statusBoundingBox = ui.Path()
      ..addRect(Rect.fromLTRB(_offsetX, _offsetY, _offsetX+(vertLocationMsg.length+directionText.length)*_charPixeslWidth+_charPixeslWidth, _offsetY+24)); 
    canvas.drawPath(statusBoundingBox, _boundingBoxPaint);   
    // Paint vertical position  
    final vertLocationTextPainter = TextPainter(text: TextSpan(text: vertLocationMsg, style: _vertLocationTextStyle), textDirection: TextDirection.ltr);
    vertLocationTextPainter.layout(
      minWidth: 0,
      maxWidth: vertLocationMsg.length*_charPixeslWidth,
    );    
    vertLocationTextPainter.paint(canvas, const Offset(_offsetX, _offsetY));
    // Paint ascending/descending direction arrows (if not flying level)
    if (directionText.isNotEmpty) {
      final verticalSpeedTextPainter = TextPainter(text: TextSpan(text: directionText, style: _vertSpeedArrowStyle), textDirection: TextDirection.ltr);
      verticalSpeedTextPainter.layout(
        minWidth: 0,
        maxWidth: directionText.length*_charPixeslWidth+_charPixeslWidth,
      );   
      verticalSpeedTextPainter.paint(canvas, Offset(_offsetX+(vertLocationMsg.length*_charPixeslWidth), _offsetY-(_vertSpeedArrowFontSize-_vertLocationFontSize)));  
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
  static const double _offsetX = 24, _offsetY = 24;
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

/// Paints an AC 20-172 alert overlay (orange circle for nearby alert, red box for critical resolution alert)
class AlertBoxPainter extends AbstractCachedCustomPainter {
  static const _alertRect = Rect.fromLTRB(-10, -10, 40, 40);
  static final _alertCircle = ui.Path()..addOval(_alertRect);
  static final _resolutionBox = ui.Path()..addRect(_alertRect);
  static final Paint _outlinePaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2; 
  static final _nearbyWarningAlertPaint = Paint()..color = TrafficPainter.kAdvisoryColor;
  static final _criticalResolutionAlertPaint = Paint()..color = TrafficPainter.kResolutionColor;

  final TrafficAlertLevel _alertLevel;
  final bool _isAirborne;      

  AlertBoxPainter(Traffic t): 
    _alertLevel = t.alertLevel, 
    _isAirborne = t.message.airborne,
    super([ t.alertLevel.index, t.message.airborne ? 1 : 0 ], true, 
      const Size(64, 64));
    
  @override
  void freshPaint(ui.Canvas canvas) {
    if (!_isAirborne || !TrafficCache.ac20_172Mode || _alertLevel == TrafficAlertLevel.none) {
      return;
    }
    if (_alertLevel == TrafficAlertLevel.advisory) {
      canvas.drawPath(_alertCircle, _nearbyWarningAlertPaint);
      canvas.drawPath(_alertCircle, _outlinePaint);
    } else if (_alertLevel == TrafficAlertLevel.resolution) {
      canvas.drawPath(_resolutionBox, _criticalResolutionAlertPaint);
      canvas.drawPath(_resolutionBox, _outlinePaint);    
    }
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