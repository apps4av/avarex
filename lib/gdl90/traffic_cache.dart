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
      child: CustomPaint(painter: TrafficPainter(this)));
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

/// Icon painter for different traffic aircraft types (ADSB emitter category) and flight status
class TrafficPainter extends CustomPainter {

  // Preference control variables
  static bool prefShowSpeedBarb = false;                    // Shows line/barb at tip of icon based on speed/velocity
  static bool prefAltDiffOpacityGraduation = true;          // Gradually vary opacity of icon based on altitude diff from ownship
  static bool prefUseDifferentDefaultIconThanLight = false; // Use a different default icon for unmapped or "0" emitter category ID traffic
  static bool prefShowBoundingBox = true;                   // Display outlined bounding box around icon for higher visibility
  static bool prefShowShadow = false;                       // Display shadow effect "under" aircraft for higher visibility
  static bool prefShowShapeOutline = true;                  // Display solid outline around aircraft for higher visibility

  /// Static caches, for faster rendering of the same icons for each marker, based on icon/flight state, given
  /// there are a discrete number of possible renderings for all traffic
  static final Map<int,ui.Picture> _pictureCache = {};  // Graphical operations cache (for realtime rasterization config, e.g., shadow on)
  static final Map<int,ui.Image> _imageCache = {};      // Rasterized pixel image cache (for non-realtime config, e.g., no shadow off)

  // Const's for magic #'s and division speedup
  static const double _kMetersToFeetCont = 3.28084;
  static const double _kMetersPerSecondToKnots = 1.94384;
  static const double _kDivBy60Mult = 1.0 / 60.0;
  static const double _kDivBy1000Mult = 1.0 / 1000.0;
  // UI Default constants
  static const double _kTrafficOpacityMin = 0.2;
  static const double _kFlyingTrafficOpacityMax = 1.0;
  static const double _kGroundTrafficOpacityMax = 0.5;
  static const double _kFlightLevelOpacityReduction = 0.1;
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

  // Aircraft type outlines
  static final ui.Path _largeAircraft = ui.Path.combine(PathOperation.union,
    // body
    ui.Path()..addOval(const Rect.fromLTRB(12, 5, 19, 31)),
    ui.Path.combine(PathOperation.union,
      ui.Path()..addRect(const Rect.fromLTRB(12, 11, 19, 20)),
      ui.Path.combine(PathOperation.union,
        ui.Path()..addOval(const Rect.fromLTRB(12, 0, 19, 25)),
        // left wing
        ui.Path.combine(PathOperation.union,
          ui.Path()..addPolygon([ const Offset(0, 13), const Offset(0, 16), const Offset(15, 22), const Offset(15, 14) ], true), 
           ui.Path.combine(PathOperation.union,
            // left engine
            ui.Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(6, 17, 10, 24), const Radius.circular(1))),
            ui.Path.combine(PathOperation.union,
              // left h-stabilizer
              ui.Path()..addPolygon([ const Offset(9, 0), const Offset(9, 3), const Offset(15, 7), const Offset(15, 1) ], true),
              ui.Path.combine(PathOperation.union,
                // right wing
                ui.Path()..addPolygon([ const Offset(31, 13), const Offset(31, 16), const Offset(17, 22), const Offset(17, 14) ], true),
                ui.Path.combine(PathOperation.union,
                  // right engine
                  ui.Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(21, 17, 25, 24), const Radius.circular(1))),
                  // right h-stabilizer
                  ui.Path()..addPolygon([ const Offset(22, 0), const Offset(22, 3), const Offset(16, 7), const Offset(16, 1) ], true)))))))));       
  static final ui.Path _defaultAircraft = ui.Path()  // old default icon if no ICAO ID--just a triangle
    ..addPolygon([ const Offset(0, 0), const Offset(15, 31), const Offset(16, 31), const Offset(31, 0), 
      const Offset(16, 5), const Offset(15, 5) ], true);
  static final ui.Path _lightAircraft = ui.Path.combine(PathOperation.union,
    ui.Path.combine(PathOperation.union, 
      ui.Path.combine(PathOperation.union, 
        ui.Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(12, 18, 19, 31), const Radius.circular(2))), // body
        ui.Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(0, 18, 31, 25), const Radius.circular(1))) // wings
      ),
      ui.Path()..addRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(10, 0, 21, 5), const Radius.circular(1)))  // h-stabilizer
    ),
    ui.Path()..addPolygon([ const Offset(12, 20), const Offset(14, 4), const Offset(17, 4), const Offset(19, 20)], true)); // rear body
  static final ui.Path _rotorcraft = ui.Path.combine(PathOperation.union,
    // body
    ui.Path()..addOval(const Rect.fromLTRB(9, 11, 22, 31)),
    ui.Path.combine(PathOperation.union,
      ui.Path.combine(PathOperation.union,
        ui.Path.combine(PathOperation.union, 
          // rotor blades
          ui.Path()..addPolygon([const Offset(27, 11), const Offset(29, 13), const Offset(4, 31), const Offset(2, 29)], true),
          ui.Path()..addPolygon([const Offset(4, 11), const Offset(2, 13), const Offset(27, 31), const Offset(29, 29) ], true)),
      // tail
      ui.Path()..addRect(const Rect.fromLTRB(14, 0, 17, 12))),
    // horizontal stabilizer
    ui.Path()..addRRect(RRect.fromLTRBR(10, 3, 21, 7, const Radius.circular(1))))); 
  // vertical speed plus/minus overlays
  static final ui.Path _plusSign = ui.Path.combine(PathOperation.union,
    ui.Path()..addPolygon([ const Offset(14, 13), const Offset(14, 22), const Offset(17, 22), const Offset(17, 13) ], true),
    ui.Path()..addPolygon([ const Offset(11, 16), const Offset(20, 16), const Offset(20, 19), const Offset(11, 19) ], true));
  static final ui.Path _minusSign = ui.Path()
    ..addPolygon([ const Offset(11, 16), const Offset(20, 16), const Offset(20, 19), const Offset(11, 19) ], true);
  static final ui.Path _lowerPlusSign = ui.Path.combine(PathOperation.union,
    ui.Path()..addPolygon([ const Offset(14, 17), const Offset(14, 26), const Offset(17, 26), const Offset(17, 17) ], true),
    ui.Path()..addPolygon([ const Offset(11, 20), const Offset(20, 20), const Offset(20, 23), const Offset(11, 23) ], true));
  static final ui.Path _lowerMinusSign = ui.Path()
    ..addPolygon([ const Offset(11, 20), const Offset(20, 20), const Offset(20, 23), const Offset(11, 23) ], true);
  // Translucent bounding box shape
  static final ui.Path _boundingBox = ui.Path()
    ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(0, 0, 31, 31), const Radius.circular(3)));    
  
  // Discrete icon state variables used to determine UI
  final _TrafficAircraftIconType _aircraftType;
  final bool _isAirborne;
  final int _flightLevelDiff;
  final int _vspeedDirection;
  final int _velocityLevel;
  /// Unique key of icon state based on flight properties above that define the icon appearance, per the current
  /// configuration of enabled features.  This is used to determine UI-relevant state changes for repainting,
  /// as well as the key to the picture cache  
  int _iconStateKey = 0;

  TrafficPainter(Traffic traffic) 
    : _aircraftType = _getAircraftIconType(traffic.message.emitter), 
      _isAirborne = traffic.message.airborne,
      _flightLevelDiff = prefAltDiffOpacityGraduation ? _getGrossFlightLevelDiff(traffic.message.altitude) : -999999, 
      _vspeedDirection = _getVerticalSpeedDirection(traffic.message.verticalSpeed),
      _velocityLevel = prefShowSpeedBarb ? _getVelocityLevel(traffic.message.velocity) : -999999 
  {
    _iconStateKey = Constants.hashInts([ _vspeedDirection, _flightLevelDiff, _velocityLevel, _aircraftType.index, _isAirborne ? 1 : 0 ]);
  }

  /// Paint arcraft, vertical speed direction overlay, and (horizontal) speed barb--using 
  /// cached picture/image, based on icon state, if possible (if not, draw and cache a new one)
  @override paint(Canvas canvas, Size size) {
    
    final bool isRealtimeRasterizationRequired = prefShowShadow;

    if (!isRealtimeRasterizationRequired) {
      // Used cached rasterized (pixel) image if possible
      final ui.Image? cachedImage = _imageCache[_iconStateKey];  
      if (cachedImage != null) {
        paintImage(canvas: canvas, rect: Rect.fromLTWH(0, 0, cachedImage.width*1.0, cachedImage.height*1.0), image: cachedImage);
        return;
      }
    }

    // Use cached picture (pre-rasterization graphical operations) if possible
    final ui.Picture? cachedPicture = _pictureCache[_iconStateKey];
    if (cachedPicture != null) {
      canvas.drawPicture(cachedPicture);
    } else {
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final ui.Canvas drawingCanvas = Canvas(recorder);

      final double opacity;
      if (prefAltDiffOpacityGraduation) {
        // Decide opacity, based on vertical distance from ownship and whether traffic is on the ground. 
        // Traffic far above or below ownship will be quite transparent, to avoid clutter, and 
        // ground traffic has a 50% max opacity / min transparency to avoid taxiing or stationary (ADSB-initilized)
        // traffic from flooding the map. Opacity decrease is 10% for every 1000 foot diff above or below, with a 
        // floor of 20% total opacity (i.e., max 80% transparency)        
        opacity = min(max(_kTrafficOpacityMin, 
            (_isAirborne ? _kFlyingTrafficOpacityMax : _kGroundTrafficOpacityMax) - _flightLevelDiff.abs() * _kFlightLevelOpacityReduction
          ), 
          _isAirborne ? _kFlyingTrafficOpacityMax : _kGroundTrafficOpacityMax);
      } else {
        opacity = 1.0;
      }

      // Define aircraft, barb, accent/overlay colors and paint using above opacity
      final Paint aircraftPaint;
      if (!_isAirborne) {
        aircraftPaint = Paint()..color = Color.fromRGBO(_kGroundColor.red, _kGroundColor.green, _kGroundColor.blue, opacity);
      } else if (_flightLevelDiff > 0) {
        aircraftPaint = Paint()..color = Color.fromRGBO(_kHighColor.red, _kHighColor.green, _kHighColor.blue, opacity);
      } else if (_flightLevelDiff < 0) {
        aircraftPaint = Paint()..color = Color.fromRGBO(_kLowColor.red, _kLowColor.green, _kLowColor.blue, opacity);
      } else {
        aircraftPaint = Paint()..color = Color.fromRGBO(_kLevelColor.red, _kLevelColor.green, _kLevelColor.blue, opacity);
      }
      final Color darkAccentColor = Color.fromRGBO(_kDarkForegroundColor.red, _kDarkForegroundColor.green, _kDarkForegroundColor.blue, opacity);

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
          baseIconShape = (prefUseDifferentDefaultIconThanLight ? ui.Path.from(_defaultAircraft) : ui.Path.from(_lightAircraft));
      }            

      if (prefShowSpeedBarb) {
        // Create speed barb based on current velocity and add to plane shape, for one-shot rendering (saves time/resources)
        baseIconShape.addPath(ui.Path()..addRect(Rect.fromLTWH(14, 31, 3, _velocityLevel*2.0)), const Offset(0, 0));
      }

      if (prefShowBoundingBox) {
        // Draw transluscent bounding box for greater visibility (especially sectionals)
        drawingCanvas.drawPath(_boundingBox, 
          Paint()..color = Color.fromRGBO(_kDarkForegroundColor.red, _kDarkForegroundColor.green, _kDarkForegroundColor.blue,
            // Have box fill opacity be a certain % less, but track main icon, with a floor of the traffic opacity min
            max(opacity - _kBoundingBoxOpacityReduction, _kBoundingBoxOpacityMin)));                 
      }

      if (prefShowShadow) {
        // Draw shadow for contrast on detailed backgrounds (especially sectionals)
        for (int i = 0; i < _kShadowDrawPasses; i++) {
          drawingCanvas.drawShadow(baseIconShape, darkAccentColor, _kShadowElevation, true);  
        }
      }

      // Draw aircraft (and speed barb, if feature enabled)
      drawingCanvas.drawPath(baseIconShape, aircraftPaint);

      if (prefShowShapeOutline) {
        // Draw solid outline on edge of aircraft for higher visibility
        drawingCanvas.drawPath(baseIconShape, Paint()
          ..color = darkAccentColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
        );
      }

      // Draw vspeed ("+/-") overlay if not level
      if (_vspeedDirection != 0) {
        if (_aircraftType == _TrafficAircraftIconType.light || _aircraftType == _TrafficAircraftIconType.rotorcraft 
          || (!prefUseDifferentDefaultIconThanLight && _aircraftType == _TrafficAircraftIconType.unmapped)
        ) {
          drawingCanvas.drawPath(_vspeedDirection > 0 ? _lowerPlusSign : _lowerMinusSign, Paint()..color = darkAccentColor);
        } else {
          drawingCanvas.drawPath(_vspeedDirection > 0 ? _plusSign : _minusSign, Paint()..color = darkAccentColor);    
        }
      }  

      // store this fresh image to the cache(s) for quick and efficient rendering next time
      final ui.Picture newPicture = recorder.endRecording();
      _pictureCache[_iconStateKey] = newPicture;
      if (!isRealtimeRasterizationRequired) {
        // Cache pixels of image to image cache, to save rasterization next time, if possible
        newPicture.toImage(32, 32 + (prefShowSpeedBarb ? _velocityLevel*2 : 0)).then((image) => _imageCache[_iconStateKey] = image);
      }

      // now draw the new picture to this widget's canvas
      canvas.drawPicture(newPicture);
    }
  }

  /// Only repaint this traffic marker if one of the flight properties (coalesced in icon state key) affecting the icon changes
  @override
  bool shouldRepaint(covariant TrafficPainter oldDelegate) {
    return _iconStateKey != oldDelegate._iconStateKey;
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
    return max(min(((trafficAltitude - Storage().position.altitude * _kMetersToFeetCont) * _kDivBy1000Mult).round(), 8), -8);
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