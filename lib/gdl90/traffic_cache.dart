import 'dart:core';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:avaremp/gdl90/traffic_report_message.dart';
import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:avaremp/gdl90/audible_traffic_alerts.dart';
import 'package:avaremp/constants.dart';

import '../gps.dart';

const double _kDivBy180 = 1.0 / 180.0;

// Delay to allow audible alerts to not be constantly called with no updates, wasting CPU (uses async future to wait)
const int _kAudibleAlertCallMinDelayMs = 100;

class Traffic {

  final TrafficReportMessage message;
  double horizontalOwnshipDistanceNmi = 0;
  double verticalOwnshipDistanceFt = 0;

  Traffic(this.message) {
    updateOwnshipDistances();
  }

  /// Update traffic distinces (horizontal and vertical) to ownship
  void updateOwnshipDistances() {
    // Use Haversine distance for speed/battery-efficiency instead of Vicenty, as the margin of error at these 
    // distances (for these purposes) is neglible (0.3% max, within 100 miles)
    // horizontalOwnshipDistance = GeoCalculations().calculateDistance(Gps.toLatLng(Storage().position), message.coordinates);
    horizontalOwnshipDistanceNmi = GeoCalculations.calculateFastDistance(Gps.toLatLng(Storage().position), message.coordinates);
    // final double vicentyDist = GeoCalculations().calculateDistance(Gps.toLatLng(Storage().position), message.coordinates);
    // if (vicentyDist < 100 || horizontalOwnshipDistanceNmi < 100) {
    //   print("Haversine is $horizontalOwnshipDistanceNmi and Vicenty is $vicentyDist, for a diff of ${horizontalOwnshipDistanceNmi-vicentyDist} or ${(horizontalOwnshipDistanceNmi-vicentyDist)/vicentyDist*100}%");
    // }    
    verticalOwnshipDistanceFt = Constants.mToFt(Storage().position.altitude) - message.altitude;
  }

  bool isOld() {
    // old if more than 1 min
    return DateTime.now().difference(message.time).inMinutes > 0;
  }

  Widget getIcon() {
    // return Transform.rotate(angle: message.heading * pi / 180,
    //      child: Container(
    //        decoration: BoxDecoration(
    //            borderRadius: BorderRadius.circular(5),
    //            color: Colors.black),
    //        child:const Icon(Icons.arrow_upward_rounded, color: Colors.white,)));
    return Transform.rotate(angle: (message.heading + 180.0 /* Image painted down on coordinate plane */) * pi  * _kDivBy180,
      child: CustomPaint(painter: _TrafficPainter(this)));
  }

  LatLng getCoordinates() {
    return message.coordinates;
  }

  @override
  String toString() {
    return "${message.callSign}\n${message.altitude.toInt()} ft\n"
    "${(message.velocity * 1.94384).toInt()} knots\n"
    "${(message.verticalSpeed * 3.28).toInt()} fpm";
  }
}


class TrafficCache {
  static const int maxEntries = 20;
  final List<Traffic?> _traffic = List.filled(maxEntries + 1, null); // +1 is the empty slot where new traffic is added

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
    if(message.icao == Storage().myIcao) {
      // do not add ourselves
      return;
    }

    for(Traffic? traffic in _traffic) {
      int index = _traffic.indexOf(traffic);
      if(traffic == null) {
        continue;
      }
      if(traffic.isOld()) {
        _traffic[index] = null;
        // purge old
        continue;
      }

      // update
      if(traffic.message.icao == message.icao) {
        // call sign not available. use last one
        if(message.callSign.isEmpty) {
          message.callSign = traffic.message.callSign;
        }
        final Traffic trafficNew = Traffic(message);
        _traffic[index] = trafficNew;

        // process any audible alerts from traffic (if enabled)
        handleAudibleAlerts();

        return;
      }
    }

    // put it in the end
    final Traffic trafficNew = Traffic(message);
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
    _audibleAlertsHandling = true;   
    if (Storage().settings.isAudibleAlertsEnabled()) {
      AudibleTrafficAlerts.getAndStartAudibleTrafficAlerts().then((aa) {
        // TODO: Set all of the "pref" settings from new Storage params (which in turn have a config UI?)
        aa?.processTrafficForAudibleAlerts(_traffic, Storage().position, Storage().lastMsGpsSignal, Storage().vspeed, Storage().airborne);
        _audibleAlertsRequested = false;
        Future.delayed(const Duration(milliseconds: _kAudibleAlertCallMinDelayMs), () {
          _audibleAlertsHandling = false;
          if (_audibleAlertsRequested) {
            Future(handleAudibleAlerts);
          }
        });
      });
    } else {
      AudibleTrafficAlerts.stopAudibleTrafficAlerts();
    }
  }

  /// Recalcs all traffic cache distances (e.g., from an ownship position update), then calls audible alerts
  void updateTrafficDistancesAndAlerts() {
    // Make async event to avoid blocking UI thread for recalcs and alerts
    Future(() {
      for(Traffic? t in _traffic) {
        t?.updateOwnshipDistances;
      }   
    }).then((value) => handleAudibleAlerts());
  }

  List<Traffic> getTraffic() {
    List<Traffic> ret = [];

    for(Traffic? check in _traffic) {
      if(null != check) {
        ret.add(check);
      }
    }
    return ret;
  }
}

enum _TrafficAircraftIconType { unmapped, light, large, rotorcraft }

/// Icon painter for different traffic aircraft (ADSB emitter) types and flight status, with graduated opacity for vertically distant traffic
class _TrafficPainter extends CustomPainter {

  // Static picture cache, for faster rendering of the same image for another marker, based on flight state
  static final Map<String,ui.Picture> _pictureCache = {};

  // Const's for magic #'s and division speedup
  static const double _kMetersToFeetCont = 3.28084;
  static const double _kMetersPerSecondToKnots = 1.94384;
  static const double _kDivBy60Mult = 1.0 / 60.0;
  static const double _kDivBy1000Mult = 1.0 / 1000.0;
  // Colors for different aircraft heights, and contrasting overlays
  static const Color _levelColor = Color(0xFF505050);           // Level traffic = Dark grey
  static const Color _highColor = Color(0xFF2940FF);            // High traffic = Mild dark blue
  static const Color _lowColor = Color(0xFF50D050);             // Low traffic = Limish green
  static const Color _groundColor = Color(0xFF836539);          // Ground traffic = Brown
  static const Color _lightForegroundColor = Color(0xFFFFFFFF); // Overlay for darker backgrounds = White
  static const Color _darkForegroundColor = Color(0xFF000000);  // Overlay for light backgrounds = Black

  // Aircraft type outlines
  static final ui.Path _largeAircraft = ui.Path()
    // body
    ..addOval(const Rect.fromLTRB(12, 5, 19, 31))
    ..addRect(const Rect.fromLTRB(12, 11, 19, 20))..addRect(const Rect.fromLTRB(12, 11, 19, 20)) // duped, for forcing opacity
    ..addOval(const Rect.fromLTRB(12, 0, 19, 25))..addOval(const Rect.fromLTRB(12, 0, 19, 25)) // duped, for forcing opacity
    // left wing
    ..addPolygon([ const Offset(0, 13), const Offset(0, 16), const Offset(15, 22), const Offset(15, 14) ], true) 
    ..addRect(const Rect.fromLTRB(12, 14, 16, 17))  // splash of paint to cover an odd alias artifact
    ..addPolygon([ const Offset(0, 13), const Offset(0, 16), const Offset(15, 22), const Offset(15, 14) ], true) // duped, for forcing opacity
    // left engine
    ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(6, 17, 10, 24), const Radius.circular(1)))  
    // left h-stabilizer
    ..addPolygon([ const Offset(9, 0), const Offset(9, 3), const Offset(15, 7), const Offset(15, 1) ], true) 
    // right wing
    ..addPolygon([ const Offset(31, 13), const Offset(31, 16), const Offset(17, 22), const Offset(17, 14) ], true)
    ..addPolygon([ const Offset(31, 13), const Offset(31, 16), const Offset(17, 22), const Offset(17, 14) ], true) // duped, for forcing opacity
    // right engine
    ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(21, 17, 25, 24), const Radius.circular(1)))  
    // right h-stabilizer
    ..addPolygon([ const Offset(22, 0), const Offset(22, 3), const Offset(16, 7), const Offset(16, 1) ], true);       
  static final ui.Path _defaultAircraft = ui.Path()  // default icon if no ICAO ID--just a triangle
    ..addPolygon([ const Offset(4, 4), const Offset(15, 31), const Offset(16, 31), const Offset(27, 4), 
      const Offset(16, 10), const Offset(15, 10) ], true);
  static final ui.Path _lightAircraft = ui.Path()
    ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(13, 18, 18, 31), const Radius.circular(2))) // body
    ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(5, 19, 26, 26), const Radius.circular(1))) // wings
    ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(11, 7, 20, 11), const Radius.circular(1)))  // h-stabilizer
    ..addPolygon([ const Offset(13, 20), const Offset(15, 7), const Offset(16, 7), const Offset(18, 20)], true); // rear body
  static final ui.Path _rotorcraft = ui.Path()
    ..addOval(const Rect.fromLTRB(9, 11, 22, 31))
    ..addPolygon([const Offset(29, 11), const Offset(31, 13), const Offset(2, 31), const Offset(0, 29)], true)
    ..addPolygon([const Offset(29, 11), const Offset(31, 13), const Offset(2, 31), const Offset(0, 29)], true) // duped, for forcing opacity
    ..addPolygon([const Offset(2, 11), const Offset(0, 13), const Offset(29, 31), const Offset(31, 29) ], true)
    ..addPolygon([const Offset(2, 11), const Offset(0, 13), const Offset(29, 31), const Offset(31, 29) ], true) // duped, for forcing opacity
    ..addRect(const Rect.fromLTRB(15, 0, 16, 12))
    ..addRRect(RRect.fromLTRBR(10, 3, 21, 7, const Radius.circular(1))); //(const Rect.fromLTRB(10, 3, 21, 7));       
  // vertical speed plus/minus overlays
  static final ui.Path _plusSign = ui.Path()
    ..addPolygon([ const Offset(14, 14), const Offset(14, 23), const Offset(17, 23), const Offset(17, 14) ], true)
    ..addPolygon([ const Offset(11, 17), const Offset(20, 17), const Offset(20, 20), const Offset(11, 20) ], true)
    ..addPolygon([ const Offset(11, 17), const Offset(20, 17), const Offset(20, 20), const Offset(11, 20) ], true);  // duped, for forcing opacity
  static final ui.Path _minusSign = ui.Path()
    ..addPolygon([ const Offset(11, 16), const Offset(20, 16), const Offset(20, 19), const Offset(11, 19) ], true);
  static final ui.Path _lowerPlusSign = ui.Path()
    ..addPolygon([ const Offset(14, 17), const Offset(14, 26), const Offset(17, 26), const Offset(17, 17) ], true)
    ..addPolygon([ const Offset(11, 20), const Offset(20, 20), const Offset(20, 23), const Offset(11, 23) ], true)
    ..addPolygon([ const Offset(11, 20), const Offset(20, 20), const Offset(20, 23), const Offset(11, 23) ], true);  // duped, for forcing opacity
  static final ui.Path _lowerMinusSign = ui.Path()
    ..addPolygon([ const Offset(11, 20), const Offset(20, 20), const Offset(20, 23), const Offset(11, 23) ], true);
 
  final _TrafficAircraftIconType _aircraftType;
  final bool _isAirborne;
  final int _flightLevelDiff;
  final int _vspeedDirection;
  final int _velocityLevel;

  _TrafficPainter(Traffic traffic) 
    : _aircraftType = _getAircraftIconType(traffic.message.emitter), 
      _isAirborne = traffic.message.airborne,
      _flightLevelDiff = _getGrossFlightLevelDiff(traffic.message.altitude), 
      _vspeedDirection = _getVerticalSpeedDirection(traffic.message.verticalSpeed),
      _velocityLevel = _getVelocityLevel(traffic.message.velocity);

  /// Paint arcraft, vertical speed direction overlay, and (horizontal) speed barb--using 
  /// cached picture if possible, and drawing and caching new one for next time if not
  @override paint(Canvas canvas, Size size) {
    // Use pre-painted picture from cache based on relevant icon UI-driving parameters, if possible
    final String pictureKey = "$_isAirborne^$_flightLevelDiff^$_vspeedDirection^$_velocityLevel";
    final ui.Picture? cachedPicture = _pictureCache[pictureKey];
    if (cachedPicture != null) {
      canvas.drawPicture(cachedPicture);
    } else {
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas drawingCanvas = Canvas(recorder);

      // Decide opacity, based on vertical distance from ownship and whether traffic is on the ground. 
      // Traffic far above or below ownship will be quite transparent, to avoid clutter, and 
      // ground traffic has a 50% max opacity / min transparency to avoid taxiing or stationary (ADSB-initilized)
      // traffic from flooding the map. Opacity decrease is 20% for every 1000 foot diff above or below, with a 
      // floor of 20% total opacity (i.e., max 80% transparency)
      final double opacity = min(max(.2, (_isAirborne ? 1.0 : 0.5) - _flightLevelDiff.abs() * 0.2), (_isAirborne ? 1.0 : 0.5));
      // Define aircraft colors using above opacity based on whether above, level, or below ownship (or on ground)
      final Color aircraftColor;
      if (!_isAirborne) {
        aircraftColor = Color.fromRGBO(_groundColor.red, _groundColor.green, _groundColor.blue, opacity);
      } else if (_flightLevelDiff > 0) {
        aircraftColor = Color.fromRGBO(_highColor.red, _highColor.green, _highColor.blue, opacity);
      } else if (_flightLevelDiff < 0) {
        aircraftColor = Color.fromRGBO(_lowColor.red, _lowColor.green, _lowColor.blue, opacity);
      } else {
        aircraftColor = Color.fromRGBO(_levelColor.red, _levelColor.green, _levelColor.blue, opacity);
      }
      final Color vspeedOverlayColor;
      if (_flightLevelDiff >= 0) {
        vspeedOverlayColor = Color.fromRGBO(_lightForegroundColor.red, _lightForegroundColor.green, _lightForegroundColor.blue, opacity);
      } else {
        vspeedOverlayColor = Color.fromRGBO(_darkForegroundColor.red, _darkForegroundColor.green, _darkForegroundColor.blue, opacity);
      }

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
          baseIconShape = ui.Path.from(_defaultAircraft);
      }
      
      // Set speed barb
      final ui.Path speedBarb = ui.Path()
        ..addRect(Rect.fromLTWH(15, 31, 1, _velocityLevel*2.0))
        ..addRect(Rect.fromLTWH(15, 31, 1, _velocityLevel*2.0)); // second time to prevent alias transparency interaction

      // Draw aircraft and speed barb in one shot (saves rendering time/resources)
      baseIconShape.addPath(speedBarb, const Offset(0,0));
      drawingCanvas.drawPath(baseIconShape, Paint()..color = aircraftColor);

      // draw vspeed overlay (if not level)
      if (_vspeedDirection != 0) {
        if (_aircraftType == _TrafficAircraftIconType.light || _aircraftType == _TrafficAircraftIconType.rotorcraft) {
          drawingCanvas.drawPath(
            _vspeedDirection > 0 ? _lowerPlusSign : _lowerMinusSign,
            Paint()..color = vspeedOverlayColor
          ); 
        } else {
          drawingCanvas.drawPath(
            _vspeedDirection > 0 ? _plusSign : _minusSign,
            Paint()..color = vspeedOverlayColor
          );    
        }
      }      

      // store this fresh image to the cache for next time
      final ui.Picture newPicture = recorder.endRecording();
      _pictureCache[pictureKey] = newPicture;

      // now draw the new picture to this widget's canvas
      canvas.drawPicture(newPicture);
    }
  }

  // Only repaint this traffic marker if one of the flight properties affecting the icon changes
  @override
  bool shouldRepaint(covariant _TrafficPainter oldDelegate) {
    return _flightLevelDiff != oldDelegate._flightLevelDiff || _velocityLevel != oldDelegate._velocityLevel 
      ||_vspeedDirection != oldDelegate._vspeedDirection || _isAirborne != oldDelegate._isAirborne;
  }

  @pragma("vm:prefer-inline")
  static _TrafficAircraftIconType _getAircraftIconType(int adsbEmitterCategoryId) {
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
  static int _getGrossFlightLevelDiff(double trafficAltitude) {
    return max(min(((trafficAltitude - Storage().position.altitude * _kMetersToFeetCont) * _kDivBy1000Mult).round(), 5), -5);
  }

  @pragma("vm:prefer-inline")
  static int _getVerticalSpeedDirection(double verticalSpeedMps) {
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
    return (veloMps * _kMetersPerSecondToKnots * _kDivBy60Mult).round();
  }  
}