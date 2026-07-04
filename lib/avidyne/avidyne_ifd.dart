import 'dart:async';

import 'package:avaremp/avidyne/avidyne_discovery.dart';
import 'package:avaremp/avidyne/avidyne_stored_route.dart';
import 'package:avaremp/avidyne/avidyne_wifi_channel.dart';
import 'package:avaremp/plan/plan_route.dart';
import 'package:flutter/foundation.dart';

/// High level manager for talking to Avidyne IFD units over Wi-Fi.
///
/// Responsibilities:
///   - run IFD discovery while a UI needs it,
///   - keep the list of currently visible IFDs (expiring stale ones), and
///   - send the active flight plan to a chosen IFD.
///
/// A single shared instance is used so the discovery socket is not opened more
/// than once.
class AvidyneIfd {
  static final AvidyneIfd _instance = AvidyneIfd._();
  factory AvidyneIfd() => _instance;
  AvidyneIfd._();

  static const Duration _deviceTimeout = Duration(seconds: 30);

  final ValueNotifier<int> change = ValueNotifier<int>(0);

  final Map<String, AvidyneDevice> _devices = {};
  AvidyneDiscovery? _discovery;
  int _listeners = 0;
  Timer? _expiryTimer;
  bool _transferInProgress = false;

  bool get transferInProgress => _transferInProgress;

  List<AvidyneDevice> get devices {
    final List<AvidyneDevice> list = _devices.values.toList();
    list.sort((a, b) => a.ipAddress.compareTo(b.ipAddress));
    return list;
  }

  /// Called by a screen/widget when it starts needing discovery. Reference
  /// counted so discovery keeps running while any UI is interested.
  Future<void> acquire() async {
    _listeners++;
    if (_discovery == null) {
      _discovery = AvidyneDiscovery(onDevice: _onDevice);
      await _discovery!.start();
      _expiryTimer =
          Timer.periodic(const Duration(seconds: 5), (_) => _expireDevices());
    }
  }

  /// Called when a screen/widget no longer needs discovery.
  Future<void> release() async {
    _listeners--;
    if (_listeners <= 0) {
      _listeners = 0;
      await _discovery?.stop();
      _discovery = null;
      _expiryTimer?.cancel();
      _expiryTimer = null;
    }
  }

  void _onDevice(AvidyneDevice device) {
    final AvidyneDevice? existing = _devices[device.ipAddress];
    if (existing == null) {
      _devices[device.ipAddress] = device;
    } else {
      existing.lastSeen = device.lastSeen;
    }
    change.value++;
  }

  void _expireDevices() {
    final DateTime now = DateTime.now();
    final int before = _devices.length;
    _devices.removeWhere(
        (_, d) => now.difference(d.lastSeen) > _deviceTimeout);
    if (_devices.length != before) {
      change.value++;
    }
  }

  /// Sends the given [route] to the given [device] as a stored route.
  ///
  /// Returns null on success or a human readable error otherwise.
  Future<String?> sendFlightPlan(AvidyneDevice device, PlanRoute route) async {
    if (_transferInProgress) {
      return "A transfer is already in progress.";
    }
    if (!device.acceptsFlightPlans) {
      return "This IFD is not configured to accept flight plans.";
    }

    final Uint8List? file = AvidyneStoredRoute.buildRouteFile(route);
    if (file == null) {
      return "Flight plan needs at least two waypoints.";
    }

    _transferInProgress = true;
    change.value++;
    try {
      final AvidyneWifiChannel channel = AvidyneWifiChannel();
      return await channel.upload(
          device.ipAddress, AvidyneWifiChannel.datasetRoute, file);
    } finally {
      _transferInProgress = false;
      change.value++;
    }
  }
}
