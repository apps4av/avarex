import 'dart:async';
import 'dart:convert';

import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/io/io_screen.dart';
import 'package:avaremp/nmea/rte_packet.dart';
import 'package:avaremp/nmea/wpl_packet.dart';
import 'package:avaremp/plan/plan_route.dart';
import 'package:avaremp/utils/app_log.dart';

class GarminConnextTransfer {
  static const Duration defaultSentenceDelay = Duration(milliseconds: 60);
  static const int minWaypoints = 2;

  static bool get isConnected =>
      IoScreenState.connection?.isConnected ?? false;

  static String? get connectedDeviceLabel {
    final device = IoScreenState.connectedDevice;
    if (device == null) {
      return null;
    }
    final name = device.name ?? '';
    if (name.isNotEmpty) {
      return name;
    }
    return device.address;
  }

  static Future<String?> sendFlightPlan(PlanRoute route,
      {Duration sentenceDelay = defaultSentenceDelay}) async {
    if (!isConnected) {
      return "No Bluetooth connection. Pair a Garmin device in IO.";
    }

    final destinations = route.getAllDestinations();
    if (destinations.length < minWaypoints) {
      return "Flight plan needs at least two waypoints.";
    }

    final connection = IoScreenState.connection;
    if (connection == null || !connection.isConnected) {
      return "Bluetooth connection lost.";
    }

    final messages = GarminConnextEncoder.buildFlightPlanMessages(route);
    if (messages.isEmpty) {
      return "Flight plan is empty.";
    }

    IoScreenState.transferInProgress = true;
    try {
      for (final message in messages) {
        if (!connection.isConnected) {
          return "Bluetooth connection lost.";
        }
        connection.output.add(utf8.encode(message));
        await connection.output.allSent;
        if (sentenceDelay > Duration.zero) {
          await Future.delayed(sentenceDelay);
        }
      }
    } catch (e) {
      AppLog.logMessage("Garmin Connext transfer failed: $e");
      return "Failed to send flight plan.";
    } finally {
      IoScreenState.transferInProgress = false;
    }

    return null;
  }
}

/// Builds Garmin Connext flight plan transfer messages using NMEA RTE/WPL.
class GarminConnextEncoder {
  static const int maxWaypointNameLength = 6;
  static const int maxRouteNameLength = 8;
  static const int maxWaypointsPerSentence = 7;

  static List<String> buildFlightPlanMessages(PlanRoute route) {
    final destinations = route.getAllDestinations();
    if (destinations.isEmpty) {
      return [];
    }

    final routeName = _sanitizeRouteName(route.name);
    final waypointNames = _buildWaypointNames(destinations);

    final messages = <String>[];
    final sentWaypoints = <String>{};
    for (int index = 0; index < destinations.length; index++) {
      final name = waypointNames[index];
      if (sentWaypoints.add(name)) {
        final destination = destinations[index];
        final packet = WPLPacket(
          destination.coordinate.latitude,
          destination.coordinate.longitude,
          name,
        );
        messages.add(packet.getPacket());
      }
    }

    final segments = _chunkWaypoints(waypointNames);
    final total = segments.length;
    for (int index = 0; index < segments.length; index++) {
      final packet = RTEPacket(
        totalSentences: total,
        sentenceNumber: index + 1,
        isComplete: true,
        routeName: routeName,
        waypoints: segments[index],
      );
      messages.add(packet.getPacket());
    }

    return messages;
  }

  static List<String> _buildWaypointNames(List<Destination> destinations) {
    final usedNames = <String>{};
    final names = <String>[];
    for (int index = 0; index < destinations.length; index++) {
      final destination = destinations[index];
      final base = _sanitizeBaseName(destination.locationID);
      final name = _makeUniqueName(base, usedNames);
      names.add(name);
    }
    return names;
  }

  static String _sanitizeRouteName(String name) {
    final cleaned = _sanitizeBaseName(name);
    if (cleaned.isEmpty) {
      return "AVARE";
    }
    return _truncate(cleaned, maxRouteNameLength);
  }

  static String _sanitizeBaseName(String raw) {
    return raw
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  static String _makeUniqueName(String base, Set<String> used) {
    String cleaned = base.isEmpty ? 'WP' : base;
    String candidate = _truncate(cleaned, maxWaypointNameLength);
    int suffix = 1;
    while (used.contains(candidate)) {
      final suffixText = suffix.toString();
      final available = maxWaypointNameLength - suffixText.length;
      final prefix = _truncate(cleaned, available < 1 ? 1 : available);
      candidate = '$prefix$suffixText';
      suffix++;
    }
    used.add(candidate);
    return candidate;
  }

  static String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) {
      return value;
    }
    return value.substring(0, maxLength);
  }

  static List<List<String>> _chunkWaypoints(List<String> waypoints) {
    final segments = <List<String>>[];
    int index = 0;
    while (index < waypoints.length) {
      final end = (index + maxWaypointsPerSentence) > waypoints.length
          ? waypoints.length
          : index + maxWaypointsPerSentence;
      segments.add(waypoints.sublist(index, end));
      index = end;
    }
    return segments;
  }
}
