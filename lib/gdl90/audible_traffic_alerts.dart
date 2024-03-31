import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:geolocator/geolocator.dart';

import 'package:avaremp/gdl90/traffic_cache.dart';
import 'package:avaremp/constants.dart';

enum TrafficIdOption { phoneticAlphaId, fullCallsign, none }

enum DistanceCalloutOption { none, rounded, decimal }

enum NumberFormatOption { colloquial, individualDigit }

const double _deg180inv = 1.0 / 180.0;
@pragma("vm:prefer-inline")
double _radians(double deg) => deg * _deg180inv * pi;

const double _ln10inv = 1.0 / ln10;
@pragma("vm:prefer-inline")
double _log10(num x) => log(x) * _ln10inv;

/// Class to calculate and speak audio alerts for nearby and closing-in (TCPA) traffic
class AudibleTrafficAlerts {
  static const double _kSecondsPerHour = 3600.000;
  static const double _kHoursPerSecond = 1.0 / 3600.000;
  static const double _kSecPerAudioSegment = 0.7; // SWAG ==> TODO: Worth putting in code to compute duration of audio-to-date exactly?
  static const double _k30DegInv = 1.0 / 30.0;
  static const double _k60DegInv = 1.0 / 60.0;
  static const double _kSecPerMillseconds = 0.001;
  static const double _kHalf = 0.5;

  static AudibleTrafficAlerts? _instance;

  // Audio assets for each sound used to compose an alert
  final AssetSource _trafficAudio = AssetSource("tr_traffic.mp3");
  final AssetSource _bogeyAudio = AssetSource("tr_bogey.mp3");
  final AssetSource _closingInAudio = AssetSource("tr_cl_closingin.mp3");
  final AssetSource _overAudio = AssetSource("tr_cl_over.mp3");
  final AssetSource _lowAudio = AssetSource("tr_low.mp3"),
      _highAudio = AssetSource("tr_high.mp3"),
      _sameAltitudeAudio = AssetSource("tr_same_altitude.mp3");
  final AssetSource _oClockAudio = AssetSource("tr_oclock.mp3");
  final List<AssetSource> _twentiesToNinetiesAudios = [
    AssetSource("tr_20.mp3"),
    AssetSource("tr_30.mp3"),
    AssetSource("tr_40.mp3"),
    AssetSource("tr_50.mp3"),
    AssetSource("tr_60.mp3"),
    AssetSource("tr_70.mp3"),
    AssetSource("tr_80.mp3"),
    AssetSource("tr_90.mp3")
  ];
  final AssetSource _hundredAudio = AssetSource("tr_100.mp3"), _thousandAudio = AssetSource("tr_1000.mp3");
  final AssetSource _atAudio = AssetSource("tr_at.mp3");
  final List<AssetSource> _alphabetAudios = [
    AssetSource("tr_alpha.mp3"),
    AssetSource("tr_bravo.mp3"),
    AssetSource("tr_charlie.mp3"),
    AssetSource("tr_delta.mp3"),
    AssetSource("tr_echo.mp3"),
    AssetSource("tr_foxtrot.mp3"),
    AssetSource("tr_golf.mp3"),
    AssetSource("tr_hotel.mp3"),
    AssetSource("tr_india.mp3"),
    AssetSource("tr_juliet.mp3"),
    AssetSource("tr_kilo.mp3"),
    AssetSource("tr_lima.mp3"),
    AssetSource("tr_mike.mp3"),
    AssetSource("tr_november.mp3"),
    AssetSource("tr_oscar.mp3"),
    AssetSource("tr_papa.mp3"),
    AssetSource("tr_quebec.mp3"),
    AssetSource("tr_romeo.mp3"),
    AssetSource("tr_sierra.mp3"),
    AssetSource("tr_tango.mp3"),
    AssetSource("tr_uniform.mp3"),
    AssetSource("tr_victor.mp3"),
    AssetSource("tr_whiskey.mp3"),
    AssetSource("tr_xray.mp3"),
    AssetSource("tr_yankee.mp3"),
    AssetSource("tr_zulu.mp3")
  ];
  final List<AssetSource> _numberAudios = [
    AssetSource("tr_00.mp3"),
    AssetSource("tr_01.mp3"),
    AssetSource("tr_02.mp3"),
    AssetSource("tr_03.mp3"),
    AssetSource("tr_04.mp3"),
    AssetSource("tr_05.mp3"),
    AssetSource("tr_06.mp3"),
    AssetSource("tr_07.mp3"),
    AssetSource("tr_08.mp3"),
    AssetSource("tr_09.mp3"),
    AssetSource("tr_10.mp3"),
    AssetSource("tr_11.mp3"),
    AssetSource("tr_12.mp3"),
    AssetSource("tr_13.mp3"),
    AssetSource("tr_14.mp3"),
    AssetSource("tr_15.mp3"),
    AssetSource("tr_16.mp3"),
    AssetSource("tr_17.mp3"),
    AssetSource("tr_18.mp3"),
    AssetSource("tr_19.mp3")
  ];
  final AssetSource _secondsAudio = AssetSource("tr_seconds.mp3");
  final AssetSource _milesAudio = AssetSource("tr_miles.mp3");
  final AssetSource _climbingAudio = AssetSource("tr_climbing.mp3"),
      _descendingAudio = AssetSource("tr_descending.mp3"),
      _levelAudio = AssetSource("tr_level.mp3");
  final AssetSource _criticallyCloseChirpAudio = AssetSource("tr_cl_chirp.mp3");
  final AssetSource _withinAudio = AssetSource("tr_within.mp3");
  final AssetSource _pointAudio = AssetSource("tr_point.mp3");

  final List<_AlertItem> _alertQueue = [];
  final Map<int, int> _lastTrafficPositionUpdateTimeMap = {};
  final Map<int, int> _lastTrafficAlertTimeMap = {};
  final List<int> _phoneticAlphaIcaoSequenceQueue = [];

  // General audible alert preferences
  bool prefIsAudibleGroundAlertsEnabled = false;
  bool prefVerticalAttitudeCallout = false;
  DistanceCalloutOption prefDistanceCalloutOption = DistanceCalloutOption.none;
  NumberFormatOption prefNumberFormatOption = NumberFormatOption.colloquial;
  TrafficIdOption prefTrafficIdOption = TrafficIdOption.none;
  bool prefTopGunDorkMode = false;
  int prefAudibleTrafficAlertsMinSpeed = 0;
  int prefAudibleTrafficAlertsDistanceMinimum = 5;
  double prefTrafficAlertsHeight = 1000;
  int prefMaxAlertFrequencySeconds = 15;
  int prefTimeBetweenAnyAlertMs = 750;
  // Closing (TCPA) alert preferences
  bool prefIsAudibleClosingInAlerts = true;
  double prefClosingAlertAltitude = 1000;
  double prefClosingTimeThresholdSeconds = 60;
  double prefClosestApproachThresholdNmi = 1;
  double prefCriticalClosingAlertRatio = 0.5;
  double _prefAudioPlayRate = 1;
  set prefAudioPlayRate(double playRate) {
    if (_player._audioPlayer.playbackRate != playRate) {
      _player._audioPlayer.setPlaybackRate(playRate);
    }
    _prefAudioPlayRate = playRate;
  }
  double get prefAudioPlayRate {
    return _prefAudioPlayRate;
  }

  bool _isRunning = false;
  bool _isPlaying = false;

  final _AudioSequencePlayer _player = _AudioSequencePlayer("assets/audio/traffic_alerts/");

  final Completer<AudibleTrafficAlerts> _startupCompleter = Completer();

  static Future<AudibleTrafficAlerts?> getAndStartAudibleTrafficAlerts() async {
    if (_instance == null) {
      _instance = AudibleTrafficAlerts._privateConstructor();
      _instance?._loadAudio().then((value) {
        _instance?._isRunning = true;
        _instance?._startupCompleter.complete(_instance);
      });
    }
    return _instance?._startupCompleter.future;
  }

  static Future<void> stopAudibleTrafficAlerts() async {
    if (_instance != null) {
      _instance?._isRunning = false;
      _instance?._alertQueue.clear();
      _instance?._isPlaying = false;
      _instance = null;
      final Completer<void> shutdownCompleter = Completer();
      // TODO: Try to reclaim memory of audio cache, if at all possible (e.g., no temp dir delete issues)
      return shutdownCompleter.future;
    }
  }

  AudibleTrafficAlerts._privateConstructor();

  Future<List<Uri>> _loadAudio() async {
    final List<AssetSource> audioAssets = [
      _trafficAudio,
      _bogeyAudio,
      _closingInAudio,
      _overAudio,
      _lowAudio,
      _lowAudio,
      _sameAltitudeAudio,
      _oClockAudio,
      _hundredAudio,
      _hundredAudio,
      _atAudio,
      _secondsAudio,
      _milesAudio,
      _climbingAudio,
      _descendingAudio,
      _levelAudio,
      _criticallyCloseChirpAudio,
      _withinAudio,
      _pointAudio
    ];
    audioAssets.addAll(_numberAudios);
    audioAssets.addAll(_alphabetAudios);
    audioAssets.addAll(_twentiesToNinetiesAudios);
    return _player.preCacheAudioAssets(audioAssets);
  }

  void processTrafficForAudibleAlerts(
      List<Traffic?> trafficList, Position? ownshipLocation, int ownshipUpdateTimeMs, double ownVspeed, bool ownIsAirborne) {
    if (!_isRunning ||
        ownshipLocation == null ||
        (Constants.mpsToKt(ownshipLocation.speed) < prefAudibleTrafficAlertsMinSpeed) ||
        !(ownIsAirborne || prefIsAudibleGroundAlertsEnabled)) {
      return;
    }

    bool hasInserts = false;
    for (final traffic in trafficList) {
      if (traffic == null || !(traffic.message.airborne || prefIsAudibleGroundAlertsEnabled)) {
        continue;
      }
      final int trafficPositionTimeCalcUpdateValue = Constants.hashInts([ traffic.message.time.millisecondsSinceEpoch, ownshipUpdateTimeMs ]);
      final int trafficKey = _getTrafficKey(traffic);
      final int? lastTrafficPositionUpdateValue = _lastTrafficPositionUpdateTimeMap[trafficKey];
      final bool hasUpdate;
      // Ensure traffic has been recently updated, and if within the alerts threshold "cylinder", upsert it to the alert queue
      if ((hasUpdate = lastTrafficPositionUpdateValue == null || lastTrafficPositionUpdateValue != trafficPositionTimeCalcUpdateValue)
          && traffic.verticalOwnshipDistanceFt.abs() < prefTrafficAlertsHeight
          && traffic.horizontalOwnshipDistanceNmi < prefAudibleTrafficAlertsDistanceMinimum) 
      {
        hasInserts = hasInserts ||
            _upsertTrafficAlertQueue(_AlertItem(
                traffic,
                ownshipLocation,
                prefIsAudibleClosingInAlerts ? _determineClosingEvent(ownshipLocation, traffic, ownVspeed) : null));
          
      } else if (hasUpdate) {
        // Prune out any alert for this traffic that no longer qualifies (e.g., distance exceeded before able to process/speak)
        _alertQueue.removeWhere((element) => element._traffic.message.icao == traffic.message.icao);
      }
      if (hasUpdate) {
        // Only update position map if there is an update
        _lastTrafficPositionUpdateTimeMap[trafficKey] = trafficPositionTimeCalcUpdateValue;
      }
    }

    // Only schedule a new microtask if there is a brand new alert (updates will already have one)
    if (hasInserts) { 
      scheduleMicrotask(runAudibleAlertsQueueProcessing);
    }
  }

  bool _upsertTrafficAlertQueue(_AlertItem alert) {
    final int existingIndex = _alertQueue.indexOf(alert);
    if (existingIndex == -1) {
      // If this is a "critically close" alert, put it ahead of the first non-critically close alert
      if ((alert._closingEvent?._isCriticallyClose ?? false) && _alertQueue.isNotEmpty) {
        final int lowestNonCEIndex = _alertQueue.indexWhere((element) => !(element._closingEvent?._isCriticallyClose ?? false));
        _alertQueue.insert(lowestNonCEIndex, alert);
        return true;
      }
      // ..otherwise, if this is just a normal alert, or it is and all others are also critical, put it at the back of the queue
      _alertQueue.add(alert);
      return true;
    } else {
      // If this old alert that wasn't critically close before is now --> move it to the first non-critical spot
      if ((alert._closingEvent?._isCriticallyClose ?? false) && !(_alertQueue[existingIndex]._closingEvent?._isCriticallyClose ?? false)) {
        final int lowestNonCEIndex = _alertQueue.indexWhere((element) => !(element._closingEvent?._isCriticallyClose ?? false));
        if (lowestNonCEIndex < existingIndex) { // Ensures there is some benefit, and we aren't shifting/borking indexes
          _alertQueue.removeAt(existingIndex);
          _alertQueue.insert(lowestNonCEIndex, alert);
          return false;
        }
      }
      // If you got here, either this one isn't critical now, or all other alerts are critical too (that's a bad day)
      _alertQueue[existingIndex] = alert;
    }
    return false;
  }

  _ClosingEvent? _determineClosingEvent(Position ownshipLocation, Traffic traffic, double ownVspeed) {
    final int ownSpeedInKts = Constants.mpsToKt(ownshipLocation.speed).round();
    final double ownAltInFeet = Constants.mToFt(ownshipLocation.altitude);
    final double closingEventTimeSec = (_closestApproachTime(
                traffic.message.coordinates.latitude,
                traffic.message.coordinates.longitude,
                ownshipLocation.latitude,
                ownshipLocation.longitude,
                traffic.message.heading,
                ownshipLocation.heading,
                traffic.message.velocity.round(),
                ownSpeedInKts)).abs() * _kSecondsPerHour;
    if (closingEventTimeSec < prefClosingTimeThresholdSeconds) {
      // Gate #1: Time threshold met
      final Position myCaLoc = _locationAfterTime(ownshipLocation.latitude, ownshipLocation.longitude, ownshipLocation.heading,
          ownSpeedInKts * 1.0, closingEventTimeSec * _kHoursPerSecond, ownAltInFeet, ownVspeed);
      final Position theirCaLoc = _locationAfterTime(
          traffic.message.coordinates.latitude,
          traffic.message.coordinates.longitude,
          traffic.message.heading,
          traffic.message.velocity,
          closingEventTimeSec * _kHoursPerSecond,
          traffic.message.altitude,
          traffic.message.verticalSpeed);
      double? caDistance;
      final double altDiff = myCaLoc.altitude - theirCaLoc.altitude;
      // Gate #2: If traffic will be within configured "cylinder" of closing/TCPA alerts, create a closing event
      if (altDiff.abs() < prefClosingAlertAltitude &&
          (caDistance = _greatCircleDistanceNmi(myCaLoc.latitude, myCaLoc.longitude, theirCaLoc.latitude, theirCaLoc.longitude)) <
              prefClosestApproachThresholdNmi &&
          traffic.horizontalOwnshipDistanceNmi > caDistance) // catches cases when moving away
      {
        final bool criticallyClose = prefCriticalClosingAlertRatio > 0 &&
            (closingEventTimeSec / prefClosingTimeThresholdSeconds) <= prefCriticalClosingAlertRatio &&
            (caDistance / prefClosestApproachThresholdNmi) <= prefCriticalClosingAlertRatio;
        return _ClosingEvent(closingEventTimeSec, caDistance, criticallyClose);
      }
    }
    return null;
  }

  void runAudibleAlertsQueueProcessing() {
    if (!_isRunning || _isPlaying || _alertQueue.isEmpty) {
      return;
    }
    int timeToWaitForTraffic = Constants.kMaxIntValue;
    // Loop to allow a traffic item to cede place in line to next available one to be considered if current one can't go now
    for (int i = 0; i < _alertQueue.length; i++) {
      final _AlertItem nextAlert = _alertQueue[i];
      final int trafficKey = _getTrafficKey(nextAlert._traffic);
      final int? lastTrafficAlertTimeValue = _lastTrafficAlertTimeMap[trafficKey];
      if (lastTrafficAlertTimeValue == null ||
          (timeToWaitForTraffic = min(timeToWaitForTraffic,
                  (prefMaxAlertFrequencySeconds * 1000) - (DateTime.now().millisecondsSinceEpoch - lastTrafficAlertTimeValue))) <=
              0) {
        _lastTrafficAlertTimeMap[trafficKey] = DateTime.now().millisecondsSinceEpoch;
        _isPlaying = true;
        _alertQueue.removeAt(i);
        _player.playAudioSequence(_buildAlertSoundSequence(nextAlert))?.then((value) {
          _isPlaying = false;
          // Schedule next alert, if any, to fire after an appropriate delay (depending on criticality)
          if (_alertQueue.isNotEmpty) {
            Future.delayed(
                Duration(milliseconds: (_alertQueue[0]._closingEvent?._isCriticallyClose ?? false) ? 0 : prefTimeBetweenAnyAlertMs),
                runAudibleAlertsQueueProcessing);
          }
        });
        return; // if alert has been processed, we leave, as async firing of next one will have been scheduled on event queue
      }
    }
    // No-one can alert now, but if we have a defined time we need to wait then we schedule the next one
    if (timeToWaitForTraffic != Constants.kMaxIntValue && timeToWaitForTraffic > 0) {
      Future.delayed(Duration(milliseconds: timeToWaitForTraffic), runAudibleAlertsQueueProcessing);
    }
  }

  /// Construct sound sequence based on alert properties and preference configuration
  /// @param alert Alert item to build sound sequence for
  /// @return Sequence of sounds that represents the assembled alert
  List<AssetSource> _buildAlertSoundSequence(final _AlertItem alert) {
    final List<AssetSource> alertAudio = [];
    if (alert._closingEvent != null && alert._closingEvent._isCriticallyClose) {
      alertAudio.add(_criticallyCloseChirpAudio);
    }
    alertAudio.add(prefTopGunDorkMode ? _bogeyAudio : _trafficAudio);
    switch (prefTrafficIdOption) {
      case TrafficIdOption.phoneticAlphaId:
        _addPhoneticAlphaTrafficIdAudio(alertAudio, alert);
        break;
      case TrafficIdOption.fullCallsign:
        _addFullCallsignTrafficIdAudio(alertAudio, alert._traffic.message.callSign);
      default:
    }
    if (alert._closingEvent != null) {
      _addTimeToClosestPointOfApproachAudio(alertAudio, alert._closingEvent);
    }

    _addPositionAudio(alertAudio, alert._clockHour, alert._traffic.verticalOwnshipDistanceFt);

    if (prefDistanceCalloutOption != DistanceCalloutOption.none) {
      _addDistanceAudio(alertAudio, alert._traffic.horizontalOwnshipDistanceNmi);
    }

    if (prefVerticalAttitudeCallout /* && (alert._traffic?.message.verticalSpeed??0.0 != 0.0  Indeterminate value */) {
      _addVerticalAttitudeAudio(alertAudio, alert._traffic.message.verticalSpeed);
    }
    return alertAudio;
  }

  void _addPositionAudio(List<AssetSource> alertAudio, int clockHour, double altitudeDiff) {
    alertAudio.add(_atAudio);
    alertAudio.add(_numberAudios[clockHour]);
    alertAudio.add(_oClockAudio);
    alertAudio.add(altitudeDiff.abs() < 100 ? _sameAltitudeAudio : (altitudeDiff > 0 ? _lowAudio : _highAudio));
  }

  void _addVerticalAttitudeAudio(List<AssetSource> alertAudio, double vspeed) {
    if (vspeed.abs() < 100) {
      alertAudio.add(_levelAudio);
    } else if (vspeed >= 100) {
      alertAudio.add(_climbingAudio);
    } else if (vspeed <= -100) {
      alertAudio.add(_descendingAudio);
    }
  }

  void _addPhoneticAlphaTrafficIdAudio(List<AssetSource> alertAudio, _AlertItem alert) {
    final int trafficKey = _getTrafficKey(alert._traffic);
    int icaoIndex = _phoneticAlphaIcaoSequenceQueue.indexOf(trafficKey);
    if (icaoIndex == -1) {
      _phoneticAlphaIcaoSequenceQueue.add(trafficKey);
      icaoIndex = _phoneticAlphaIcaoSequenceQueue.length - 1;
    }
    alertAudio.add(_alphabetAudios[icaoIndex % _alphabetAudios.length]);
  }

  static final int _nineCodeUnit = "9".codeUnitAt(0),
      _zeroCodeUnit = "0".codeUnitAt(0),
      _aCodeUnit = "A".codeUnitAt(0),
      _zCodeUnit = "Z".codeUnitAt(0);
  void _addFullCallsignTrafficIdAudio(List<AssetSource> alertAudio, String? callsign) {
    if (callsign == null || callsign.trim().isEmpty) {
      return;
    }
    final String normalizedCallsign = callsign.toUpperCase().trim();
    for (int i = 0; i < normalizedCallsign.length; i++) {
      final int c = normalizedCallsign[i].codeUnitAt(0);
      if (c <= _nineCodeUnit && c >= _zeroCodeUnit) {
        alertAudio.add(_numberAudios[c - _zeroCodeUnit]);
      } else if (c >= _aCodeUnit && c <= _zCodeUnit) {
        alertAudio.add(_alphabetAudios[c - _aCodeUnit]);
      }
    }
  }

  void _addDistanceAudio(List<AssetSource> alertAudio, double distance) {
    _addNumericalAlertAudio(alertAudio, distance, prefDistanceCalloutOption == DistanceCalloutOption.decimal);
    alertAudio.add(_milesAudio);
  }

  /// Inject an individual digit audio alert sound sequence (1,032 ==> "one-zero-three-two")
  /// @param alertAudio Existing audio list to add numeric value to
  /// @param numeric Numeric value to speak into alert audio
  /// @param doDecimal Whether to speak 1st decimal into alert (false ==> rounded to whole #)
  void _addNumericalAlertAudio(List<AssetSource> alertAudio, double numeric, bool doDecimal) {
    if (prefNumberFormatOption == NumberFormatOption.colloquial) {
      _addColloquialNumericBaseAlertAudio(alertAudio, doDecimal ? numeric : numeric.round() * 1.0);
    } else {
      _addNumberSequenceNumericBaseAlertAudio(alertAudio, doDecimal ? numeric : numeric.round() * 1.0);
    }

    if (doDecimal) {
      _addFirstDecimalAlertAudioSequence(alertAudio, numeric);
    }
  }

  /// Speak a number in digit-by-digit format (1962 ==> "one nine six two")
  /// @param alertAudio List of sounds to append to
  /// @param numeric Numeric value to speak into alertAudio
  void _addNumberSequenceNumericBaseAlertAudio(List<AssetSource> alertAudio, double numeric) {
    double curNumeric = numeric; // iteration variable for digit processing
    for (int i = max(_log10(numeric).floor(), 0); i >= 0; i--) {
      if (i == 0) {
        alertAudio.add(_numberAudios[min((curNumeric % 10).floor(), 9)]);
      } else {
        final double pow10 = pow(10, i) as double;
        alertAudio.add(_numberAudios[min(curNumeric / pow10, 9).floor()]);
        curNumeric = curNumeric % pow10;
      }
    }
  }

  /// Speak a number in colloquial format (1962 ==> "one thousand nine hundred sixty-two")
  /// @param alertAudio List of sounds to append to
  /// @param numeric Numeric value to speak into alertAudio
  void _addColloquialNumericBaseAlertAudio(List<AssetSource> alertAudio, final double numeric) {
    final double log10Val = _log10(numeric);
    double curNumeric = numeric;
    for (int i = max(log10Val.isInfinite || log10Val.isNaN ? -1 : log10Val.floor(), 0); i >= 0; i--) {
      if (i == 0
          // Only speak "zero" if it is only zero (not part of tens/hundreds/thousands)
          && ((min(curNumeric % 10, 9).floor()) != 0 || (max(_log10(numeric), 0)) == 0)) {
        alertAudio.add(_numberAudios[min(curNumeric % 10, 9).floor()]);
      } else {
        if (i > 3) {
          alertAudio.add(_overAudio);
          alertAudio.addAll(
              [_numberAudios[9], _thousandAudio, _numberAudios[9], _hundredAudio, _twentiesToNinetiesAudios[9 - 2], _numberAudios[9]]);
          return;
        } else {
          final double pow10 = pow(10, i) * 1.0;
          final int digit = min(curNumeric / pow10, 9).floor();
          if (i == 1 && digit == 1) {
            // tens/teens
            alertAudio.add(_numberAudios[10 + (curNumeric.floor()) % 10]);
            return;
          } else {
            if (i == 1 && digit != 0) { // twenties/thirties/etc.
              alertAudio.add(_twentiesToNinetiesAudios[digit - 2]);
            } else if (i == 2 && digit != 0) { // hundreds
              alertAudio.add(_numberAudios[digit]);
              alertAudio.add(_hundredAudio);
            } else if (i == 3 && digit != 0) { // thousands
              alertAudio.add(_numberAudios[digit]);
              alertAudio.add(_thousandAudio);
            }
            curNumeric = curNumeric % pow10;
          }
        }
      }
    }
  }

  void _addFirstDecimalAlertAudioSequence(List<AssetSource> alertAudio, double numeric) {
    final int firstDecimal = min(((numeric - numeric.floor()) * 10).round(), 9);
    if (firstDecimal != 0) {
      alertAudio.add(_pointAudio);
      alertAudio.add(_numberAudios[firstDecimal]);
    }
  }

  void _addTimeToClosestPointOfApproachAudio(List<AssetSource> alertAudio, _ClosingEvent closingEvent) {
    if (_addClosingSecondsAudio(alertAudio, closingEvent.closingSeconds())) {
      if (prefDistanceCalloutOption != DistanceCalloutOption.none) {
        alertAudio.add(_withinAudio);
        _addDistanceAudio(alertAudio, closingEvent._closestApproachDistanceNmi);
      }
    }
  }

  
  bool _addClosingSecondsAudio(List<AssetSource> alertAudio, double closingSeconds) {
    // Subtract speaking time of audio clips, and computation thereof, prior to # of seconds in this alert
    final double adjustedClosingSeconds = closingSeconds -
        (alertAudio.length * _kSecPerAudioSegment); // SWAG ==> TODO: Worth putting in code to compute duration of audio-to-date exactly?
    if (adjustedClosingSeconds > 0) {
      alertAudio.add(_closingInAudio);
      _addNumericalAlertAudio(alertAudio, adjustedClosingSeconds, false);
      alertAudio.add(_secondsAudio);
      return true;
    }
    return false;
  }

  static double _relativeBearingFromHeadingAndLocations(
      final double lat1, final double long1, final double lat2, final double long2, final double myBearing) {
    return (Geolocator.bearingBetween(lat1, long1, lat2, long2) - myBearing + 360) % 360;
  }

  static int _nearestClockHourFromHeadingAndLocations(
      final double lat1, final double long1, final double lat2, final double long2, final double myBearing) {
    final int nearestClockHour = (_relativeBearingFromHeadingAndLocations(lat1, long1, lat2, long2, myBearing) * _k30DegInv).round();
    return nearestClockHour != 0 ? nearestClockHour : 12;
  }

  /// Great circle distance between two lat/lon's via Haversine formula, Java impl courtesy of https://introcs.cs.princeton.edu/java/12types/GreatCircle.java.html
  /// @param lat1 Latitude 1
  /// @param lon1 Longitude 1
  /// @param lat2 Latitude 2
  /// @param lon2 Longitude 2
  /// @return Great circle distance between two points in nautical miles
  static double _greatCircleDistanceNmi(final double lat1, final double lon1, final double lat2, final double lon2) {
    return Constants.mToNm(Geolocator.distanceBetween(lat1, lon1, lat2, lon2));
  }

  @pragma("vm:prefer-inline")
  static int _getTrafficKey(Traffic? traffic) {
    return traffic?.message.icao ?? -1;
  }

  /// Time to closest approach between two 2-d kinematic vectors; credit to: https://math.stackexchange.com/questions/1775476/shortest-distance-between-two-objects-moving-along-two-lines
  /// @param lat1 Latitude 1
  /// @param lon1 Longitude 2
  /// @param lat2 Latitude 2
  /// @param lon2 Longitude 2
  /// @param heading1 Heading 1
  /// @param heading2 Heading 2
  /// @param velocity1 Velocity 1
  /// @param velocity2 Velocity 2
  /// @return Time (in units of velocity) of closest point of approach
  static double _closestApproachTime(final double lat1, final double lon1, final double lat2, final double lon2, final double heading1,
      final double heading2, final int velocity1, final int velocity2) {
    // Use cosine of average of two latitudes, to give some weighting for lesser intra-lon distance at higher latitudes
    final double a = (lon2 - lon1) * (60.0000 * cos(_radians((lat1 + lat2) * _kHalf)));
    final double b = velocity2 * sin(_radians(heading2)) - velocity1 * sin(_radians(heading1));
    final double c = (lat2 - lat1) * 60.0000;
    final double d = velocity2 * cos(_radians(heading2)) - velocity1 * cos(_radians(heading1));

    return -((a * b + c * d) / (b * b + d * d));
  }

  static Position _locationAfterTime(final double lat, final double lon, final double heading, final double velocityInKt,
      final double timeInHrs, final double altInFeet, final double vspeedInFpm) {
    final double newLat = lat + cos(_radians(heading)) * (velocityInKt * _k60DegInv) * timeInHrs;
    return Position(
        latitude: newLat,
        longitude: lon + sin(_radians(heading))
                // Again, use cos of average lat to give some weighting based on shorter intra-lon distance changes at higher latitudes
                * (velocityInKt / (60.00000 * cos(_radians((newLat + lat) * _kHalf)))) * timeInHrs,
        altitude: altInFeet + (vspeedInFpm * (60.0 * timeInHrs)),
        altitudeAccuracy: 0,
        heading: heading,
        headingAccuracy: 0,
        speed: velocityInKt,
        speedAccuracy: 0,
        accuracy: 0,
        timestamp: DateTime.now());
  }
}

class _ClosingEvent {
  final double _closingTimeSec;
  final double _closestApproachDistanceNmi;
  final int _eventTimeMillis;
  final bool _isCriticallyClose;

  _ClosingEvent(double closingTimeSec, double closestApproachDistanceNmi, bool isCriticallyClose)
      : _closingTimeSec = closingTimeSec,
        _closestApproachDistanceNmi = closestApproachDistanceNmi,
        _isCriticallyClose = isCriticallyClose,
        _eventTimeMillis = DateTime.now().millisecondsSinceEpoch;

  double closingSeconds() {
    return _closingTimeSec - (DateTime.now().millisecondsSinceEpoch - _eventTimeMillis) * AudibleTrafficAlerts._kSecPerMillseconds;
  }

  @override
  String toString() {
    return "${_closingTimeSec}s within ${_closestApproachDistanceNmi}mi${_isCriticallyClose ? " CRITICAL " : ""}";
  }
}

class _AlertItem {
  final Traffic _traffic;
  final _ClosingEvent? _closingEvent;
  final int _clockHour;

  _AlertItem(Traffic traffic, Position ownLocation, _ClosingEvent? closingEvent)
      : _traffic = traffic,
        _closingEvent = closingEvent,
        _clockHour = AudibleTrafficAlerts._nearestClockHourFromHeadingAndLocations(
          ownLocation.latitude,
          ownLocation.longitude,
          traffic.message.coordinates.latitude,
          traffic.message.coordinates.longitude,
          ownLocation.heading);

  @override
  int get hashCode => _traffic.message.icao;

  @override
  bool operator ==(Object other) {
    return other is _AlertItem && other.runtimeType == runtimeType && _traffic.message.icao == other._traffic.message.icao;
  }

  @override
  String toString() {
    return "[${AudibleTrafficAlerts._getTrafficKey(_traffic)}]: dist=${_traffic.horizontalOwnshipDistanceNmi}nmi, altdiff=${_traffic.verticalOwnshipDistanceFt}, ce=[$_closingEvent]";
  }
}

/// Plays a sequence of audio clips one after another (e.g., an alert)
class _AudioSequencePlayer {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioPlayer _audioPlayerAlt = AudioPlayer(); // my own DIY dual AudioPool--with more control
  bool _useAlt = false;
  Completer<void>? _completer;
  static AudioCache? _cache; // static singleton: brutal hack to get around Windows file locking issue with cache
  List<AssetSource> _audios = [];
  int _seqNum = 0;

  _AudioSequencePlayer(String cacheAudioDirectory) {
    _cache ??= AudioCache(prefix: cacheAudioDirectory); // static singleton: brutal hack to get around Windows file locking issue with cache
    _audioPlayer.audioCache = _cache!;
    _audioPlayerAlt.audioCache = _cache!;
    _audioPlayer.onPlayerComplete.listen(_handleNextSeqAudio);
    _audioPlayerAlt.onPlayerComplete.listen(_handleNextSeqAudio);
    _audioPlayer.setReleaseMode(ReleaseMode.stop);
    _audioPlayerAlt.setReleaseMode(ReleaseMode.stop);
  }

  void _handleNextSeqAudio(event) async {
    if (_seqNum < _audios.length) {
      _playFlip();
    } else {
      _completer?.complete();
      _completer = null;
    }
  }

  Future<List<Uri>> preCacheAudioAssets(List<AssetSource> assets) {
    if (_cache?.loadedFiles.isEmpty ?? false) { // static singleton: brutal hack to get around Windows file locking issue with cache
      final List<String> fileNames = assets.map((e) => e.path).toList();
      return _cache!.loadAll(fileNames);
    } else {
      final Completer<List<Uri>> completer = Completer();
      completer.complete([]);
      return completer.future;
    }
  }

  Future<void>? playAudioSequence(List<AssetSource> audioSources) async {
    if (_completer != null) {
      throw "Illegal state: audio sequence play currently in progress";
    }
    if (audioSources.isEmpty) {
      throw "Invalid argument: audio sources list is empty";
    }
    _audios = audioSources;
    _seqNum = 0;
    _completer = Completer();
    _playFlip();
    return _completer?.future;
  }

  void _playFlip() {
    if (_useAlt) {
      _audioPlayerAlt.play(_audios[_seqNum++]);
    } else {
      _audioPlayer.play(_audios[_seqNum++]);
    }
    _useAlt = !_useAlt;
  }
}