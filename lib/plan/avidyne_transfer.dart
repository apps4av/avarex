import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/nmea/rte_packet.dart';
import 'package:avaremp/nmea/wpl_packet.dart';
import 'package:avaremp/plan/plan_route.dart';
import 'package:latlong2/latlong.dart';

class AvidyneTransferPayload {
  final String data;
  final int waypointCount;
  final int userWaypointCount;
  final int sentenceCount;
  final String routeId;

  const AvidyneTransferPayload({
    required this.data,
    required this.waypointCount,
    required this.userWaypointCount,
    required this.sentenceCount,
    required this.routeId,
  });
}

class AvidyneTransfer {
  static const int _maxWaypointIdLength = 6;
  static const int _maxNmeaSentenceLength = 82;
  static const String _defaultRouteId = 'AVX';

  static AvidyneTransferPayload? buildTransfer(PlanRoute route) {
    final destinations = route.getAllDestinations();
    if (destinations.isEmpty) {
      return null;
    }

    final _PreparedWaypoints prepared = _prepareWaypoints(destinations);
    final String routeId = _sanitizeRouteId(route.name);
    final List<String> wplSentences = prepared.waypoints
        .map((waypoint) => WPLPacket(
          waypoint.coordinate.latitude,
          waypoint.coordinate.longitude,
          waypoint.id,
        ).packet)
        .toList();
    final List<String> rteSentences = _buildRteSentences(prepared.routeIds, routeId);
    final String data = (wplSentences + rteSentences).join();

    return AvidyneTransferPayload(
      data: data,
      waypointCount: prepared.waypoints.length,
      userWaypointCount: prepared.userWaypointCount,
      sentenceCount: wplSentences.length + rteSentences.length,
      routeId: routeId,
    );
  }

  static _PreparedWaypoints _prepareWaypoints(List<Destination> destinations) {
    final List<_AvidyneWaypoint> waypoints = [];
    final List<String> routeIds = [];
    final Map<String, String> idToCoordinate = {};
    int userWaypointCount = 0;
    int userIndex = 1;

    for (final destination in destinations) {
      final String coordKey = _coordinateKey(destination.coordinate);
      String id = _baseWaypointId(destination);
      bool isUser = id.isEmpty;

      if (id.isNotEmpty && idToCoordinate.containsKey(id)) {
        if (idToCoordinate[id] != coordKey) {
          id = '';
          isUser = true;
        }
      }

      if (id.isEmpty) {
        id = _makeUserId(userIndex++);
        isUser = true;
      }

      idToCoordinate[id] = coordKey;
      routeIds.add(id);
      waypoints.add(_AvidyneWaypoint(id: id, coordinate: destination.coordinate));
      if (isUser) {
        userWaypointCount++;
      }
    }

    return _PreparedWaypoints(
      waypoints: waypoints,
      routeIds: routeIds,
      userWaypointCount: userWaypointCount,
    );
  }

  static List<String> _buildRteSentences(List<String> waypointIds, String routeId) {
    if (waypointIds.isEmpty) {
      return [];
    }

    final List<List<String>> chunks = [];
    final String base = '\$GPRTE,99,99,c,$routeId';
    final int baseLength = base.length;

    List<String> current = [];
    int currentLength = baseLength;

    for (final id in waypointIds) {
      final int addedLength = 1 + id.length; // comma + waypoint id
      if (current.isNotEmpty &&
          (currentLength + addedLength + 5) > _maxNmeaSentenceLength) {
        chunks.add(current);
        current = [];
        currentLength = baseLength;
      }
      current.add(id);
      currentLength += addedLength;
    }

    if (current.isNotEmpty) {
      chunks.add(current);
    }

    final int total = chunks.length;
    return List<String>.generate(total, (index) {
      return RTEPacket(total, index + 1, routeId, chunks[index]).packet;
    });
  }

  static String _sanitizeRouteId(String name) {
    final String cleaned = _sanitizeId(name);
    if (cleaned.isEmpty) {
      return _defaultRouteId;
    }
    return cleaned.substring(0, cleaned.length > _maxWaypointIdLength ? _maxWaypointIdLength : cleaned.length);
  }

  static String _baseWaypointId(Destination destination) {
    if (destination.type == Destination.typeGps) {
      return '';
    }
    final bool isComposite = Destination.isAirway(destination.type) || Destination.isProcedure(destination.type);
    final String? secondary = destination.secondaryName;
    if (isComposite && (secondary == null || secondary.trim().isEmpty)) {
      return '';
    }
    final String rawId = (secondary != null && secondary.trim().isNotEmpty)
        ? secondary
        : destination.locationID;
    final String cleaned = _sanitizeId(rawId);
    if (cleaned.isEmpty || cleaned.length > _maxWaypointIdLength) {
      return '';
    }
    return cleaned;
  }

  static String _sanitizeId(String value) {
    return value
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  static String _makeUserId(int index) {
    if (index > 9999) {
      return 'WP9999';
    }
    return 'WP${index.toString().padLeft(4, '0')}';
  }

  static String _coordinateKey(LatLng coordinate) {
    return '${coordinate.latitude.toStringAsFixed(6)},${coordinate.longitude.toStringAsFixed(6)}';
  }
}

class _AvidyneWaypoint {
  final String id;
  final LatLng coordinate;

  _AvidyneWaypoint({required this.id, required this.coordinate});
}

class _PreparedWaypoints {
  final List<_AvidyneWaypoint> waypoints;
  final List<String> routeIds;
  final int userWaypointCount;

  _PreparedWaypoints({
    required this.waypoints,
    required this.routeIds,
    required this.userWaypointCount,
  });
}
