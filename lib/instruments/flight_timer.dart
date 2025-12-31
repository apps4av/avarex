import 'package:flutter/material.dart';


class FlightTimer {

  int _count = 0;
  final int _startCount;
  final bool _up;
  bool _started = false;
  bool _expired = false;

  FlightTimer(this._up, this._startCount, ValueNotifier timeChange) {
    if(_up) {
      _count = 0;
    }
    else {
      _count = _startCount;
    }
    timeChange.addListener(_timeListener);
  }

  void _timeListener() {
    if(_started) {
      if(_up) {
        _count++;
      }
      else {
        if(_count > 0) {
          _expired = false;
          _count--;
        }
        else {
          _started = false;
          _expired = true;
        }
      }
    }
  }

  void start() {
    _started = true;
  }

  void stop() {
    _started = false;
  }

  void reset() {
    _count = _startCount;
  }

  Duration getTime() {
    return Duration(seconds: _count);
  }

  bool isExpired() {
    return _expired;
  }

  bool isStarted() {
    return _started;
  }

}