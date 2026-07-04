import 'dart:async';

import 'package:avaremp/avidyne/avidyne_discovery.dart';
import 'package:avaremp/avidyne/avidyne_stored_route.dart';
import 'package:avaremp/avidyne/avidyne_wifi_channel.dart';
import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/plan/plan_route.dart';
import 'package:avaremp/plan/waypoint.dart';
import 'package:avaremp/utils/app_log.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// High level manager for talking to Avidyne IFD units over Wi-Fi.
///
/// Responsibilities:
///   - run IFD discovery (broadcasting the "AVISDK" trigger),
///   - keep the list of currently visible IFDs (expiring stale ones), and
///   - send the active flight plan to a chosen IFD.
///
/// The discovery broadcast doubles as the Capstone ADS-B trigger: the IFD only
/// starts streaming its Capstone (GDL90) data once it has heard the "AVISDK"
/// trigger. Those datagrams arrive on UDP 4000 and are decoded by the existing
/// GDL90 pipeline ([UdpReceiver] -> [Storage.gdl90Buffer]), so no extra decode
/// is needed here. For that reason discovery is kept running for as long as
/// network IO is active rather than only while the transfer UI is open.
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
  Timer? _expiryTimer;
  bool _transferInProgress = false;

  bool get transferInProgress => _transferInProgress;

  bool get isRunning => _discovery != null;

  List<AvidyneDevice> get devices {
    final List<AvidyneDevice> list = _devices.values.toList();
    list.sort((a, b) => a.ipAddress.compareTo(b.ipAddress));
    return list;
  }

  /// Starts IFD discovery / Capstone ADS-B triggering. Idempotent: calling it
  /// again while already running is a no-op. Tied to the app's network IO
  /// lifecycle so ADS-B keeps flowing whenever the app is active on the IFD's
  /// Wi-Fi network.
  Future<void> start() async {
    if (_discovery != null) {
      return;
    }
    _discovery = AvidyneDiscovery(onDevice: _onDevice);
    await _discovery!.start();
    _expiryTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _expireDevices());
  }

  /// Stops discovery / the Capstone trigger. Not called while a transfer is in
  /// progress.
  Future<void> stop() async {
    if (_transferInProgress) {
      return;
    }
    await _discovery?.stop();
    _discovery = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _devices.clear();
    change.value++;
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

  /// Downloads the active route from [device] and turns it into an AvareX
  /// [PlanRoute].
  ///
  /// Returns a record of (route, error); exactly one is non-null. Each IFD
  /// waypoint is resolved against the AvareX database by identifier (picking
  /// the closest match to the IFD coordinate) so it keeps its real type; if it
  /// cannot be resolved, a plain GPS coordinate waypoint is used instead.
  Future<(PlanRoute?, String?)> importFlightPlan(AvidyneDevice device) async {
    if (_transferInProgress) {
      return (null, "A transfer is already in progress.");
    }

    _transferInProgress = true;
    change.value++;
    try {
      final AvidyneWifiChannel channel = AvidyneWifiChannel();
      final (Uint8List? bytes, String? error) =
          await channel.download(device.ipAddress, AvidyneWifiChannel.datasetRoute);
      if (error != null) {
        return (null, error);
      }
      if (bytes == null) {
        return (null, "No flight plan received from the IFD.");
      }

      AppLog.logMessage(
          "Avidyne IFD route file: ${bytes.length} bytes, preview: ${_preview(bytes)}");

      final AvidyneParsedRoute? parsed = AvidyneStoredRoute.parseRouteFile(bytes);
      if (parsed == null || parsed.points.isEmpty) {
        return (null, "The IFD did not return a usable flight plan.");
      }

      final PlanRoute route = await _buildRoute(parsed);
      if (route.length < 1) {
        return (null, "The IFD flight plan had no usable waypoints.");
      }
      return (route, null);
    } finally {
      _transferInProgress = false;
      change.value++;
    }
  }

  // A short, log-friendly preview of a downloaded file: printable characters
  // are shown as-is, everything else as a dot, so we can tell binary from CSV.
  static String _preview(Uint8List bytes) {
    final int n = bytes.length < 96 ? bytes.length : 96;
    final StringBuffer sb = StringBuffer();
    for (int i = 0; i < n; i++) {
      final int b = bytes[i];
      sb.writeCharCode((b >= 0x20 && b < 0x7f) ? b : 0x2e);
    }
    return sb.toString();
  }

  Future<PlanRoute> _buildRoute(AvidyneParsedRoute parsed) async {
    final PlanRoute route =
        PlanRoute(parsed.name.isEmpty ? "IFD Route" : parsed.name);
    for (final AvidyneRoutePoint p in parsed.points) {
      final Destination d = await _resolvePoint(p);
      route.addWaypoint(Waypoint(d));
    }
    return route;
  }

  Future<Destination> _resolvePoint(AvidyneRoutePoint p) async {
    final LatLng target = LatLng(p.latitude, p.longitude);
    final String ident = p.id.trim();

    if (ident.isNotEmpty) {
      try {
        final List<Destination> matches =
            await MainDatabaseHelper.db.findDestinations(ident, exact: true);
        Destination? best;
        double bestDistance = double.infinity;
        for (final Destination m in matches) {
          // Airways/procedures are not single coordinate waypoints.
          if (Destination.isAirway(m.type) || Destination.isProcedure(m.type)) {
            continue;
          }
          final double dist =
              GeoCalculations().calculateDistance(target, m.coordinate);
          if (dist < bestDistance) {
            bestDistance = dist;
            best = m;
          }
        }
        // Only accept the database hit if it is near the IFD coordinate (a few
        // miles) so we do not grab an identically named fix in another region.
        if (best != null && bestDistance <= 5.0) {
          return await DestinationFactory.make(best);
        }
      } catch (e) {
        AppLog.logMessage("Avidyne import lookup failed for $ident: $e");
      }
    }

    // Fall back to a GPS coordinate waypoint.
    return Destination.fromLatLng(target);
  }
}
