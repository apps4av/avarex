import 'dart:math';

import 'package:avaremp/data/main_database_helper.dart';
import 'package:avaremp/destination/destination.dart';
import 'package:avaremp/utils/app_log.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:latlong2/latlong.dart';

// A minimal offline IFR route generator.
//
// It routes between two airports over the published airway network: it joins the
// network at a fix near the departure airport, follows airways, and leaves at a fix
// near the destination airport. The airways themselves are not named in the output -
// the route is emitted as the list of waypoints along the way
// (e.g. "KBOS BOS WHYBE ... JFK KJFK").
//
// When [lowAltitudeOnly] is true only Victor (V) and RNAV T (T) airways are used;
// otherwise the full airway network (V, T, J, Q) is used.
class RouteGenerator {

  // Restrict routing to low altitude airways (Victor and RNAV T) only.
  final bool lowAltitudeOnly;

  RouteGenerator({this.lowAltitudeOnly = false});

  // Longest allowed single airway segment. Real VOR/RNAV airway segments are well
  // under this; anything longer is a data artifact where one airway name spans two
  // geographically disjoint pieces (e.g. a mainland and a Hawaii airway of the same
  // name). Capping here keeps those pieces separate and, crucially, prevents the
  // route from ever "leaving" the airway with a long direct leg between fixes.
  static const double _maxSegmentLength = 120; // nm
  static const double _regionMarginDeg = 3.0; // corridor padding around the direct path
  static const double _maxTransitionDistance = 300; // nm, farthest an airport may be from an entry/exit fix
  static const int _maxTransitionCandidates = 20; // how many nearby fixes to try as entry/exit
  // Off-airway (direct) get-on/get-off legs cost more than airway miles, so the
  // route prefers to join/leave the airway system at the fix closest to the airport
  // rather than cutting the corner with a long direct leg.
  static const double _directLegPenalty = 2.0;

  final GeoCalculations _geo = GeoCalculations();

  // Node storage: coordinates are quantized to a string key so waypoints that are
  // shared between airways collapse onto the same graph node.
  final Map<String, int> _keyToId = {};
  final List<LatLng> _coords = [];
  final List<List<_Edge>> _adjacency = [];

  static String _key(LatLng ll) => "${ll.latitude.toStringAsFixed(5)},${ll.longitude.toStringAsFixed(5)}";

  int _nodeFor(LatLng ll) {
    String k = _key(ll);
    int? id = _keyToId[k];
    if (id != null) {
      return id;
    }
    id = _coords.length;
    _keyToId[k] = id;
    _coords.add(ll);
    _adjacency.add([]);
    return id;
  }

  void _addEdge(int a, int b, double distance) {
    _adjacency[a].add(_Edge(b, distance));
    _adjacency[b].add(_Edge(a, distance));
  }

  // Generate a route between two airport identifiers. Returns the ordered list of
  // destinations (departure airport, airway waypoints, destination airport) or null
  // if no airway path could be found.
  Future<List<Destination>?> generate(String originId, String destinationId) async {
    try {
      Destination? origin = await _findAirport(originId);
      Destination? destination = await _findAirport(destinationId);
      if (origin == null || destination == null) {
        return null;
      }

      LatLng originLl = origin.coordinate;
      LatLng destLl = destination.coordinate;

      await _buildGraph(originLl, destLl);
      if (_coords.isEmpty) {
        return null; // no airways in the corridor
      }

      // Everything added so far is an airway waypoint; the airports are added next.
      int airwayNodeCount = _coords.length;

      // Connect the airports to the network via nearby entry/exit fixes only (never
      // directly to each other, so a route always uses the airway system).
      int originNode = _nodeFor(originLl);
      int destNode = _nodeFor(destLl);
      _connectAirport(originNode, originLl, airwayNodeCount);
      _connectAirport(destNode, destLl, airwayNodeCount);

      List<int>? path = _dijkstra(originNode, destNode);
      if (path == null) {
        return null;
      }

      return await _buildDestinations(origin, destination, path);
    }
    catch (e) {
      AppLog.logMessage("Route generator error $e");
      return null;
    }
  }

  // Look up an airport, trying the identifier as typed and, for 3-letter US ids,
  // with a 'K' prefix (e.g. BOS -> KBOS).
  Future<Destination?> _findAirport(String id) async {
    String up = id.toUpperCase().trim();
    Destination? d = await MainDatabaseHelper.db.findAirport(up);
    if (d == null && up.length == 3) {
      d = await MainDatabaseHelper.db.findAirport("K$up");
    }
    return d;
  }

  Future<void> _buildGraph(LatLng origin, LatLng dest) async {
    double minLat = min(origin.latitude, dest.latitude) - _regionMarginDeg;
    double maxLat = max(origin.latitude, dest.latitude) + _regionMarginDeg;
    double minLon = min(origin.longitude, dest.longitude) - _regionMarginDeg;
    double maxLon = max(origin.longitude, dest.longitude) + _regionMarginDeg;

    List<Map<String, Object?>> rows = await MainDatabaseHelper.db.getAirwayPointsInRegion(minLat, maxLat, minLon, maxLon);

    // Group points by airway name. Rows are ordered by name then sequence.
    // Note: a single airway name can contain several geographically separate
    // segments that reuse the same sequence numbers (e.g. a mainland V1 and a
    // Hawaii V1). We therefore connect points across adjacent sequence groups by
    // nearest neighbour, and the segment-length limit keeps the regions separate.
    String? currentName;
    List<MapEntry<int, LatLng>> group = [];

    void flush() {
      if (currentName == null || group.isEmpty) {
        return;
      }
      _connectAirwayGroup(currentName, group);
    }

    for (Map<String, Object?> row in rows) {
      String name = row['name'] as String;
      int? seq = int.tryParse((row['sequence'] as String).trim());
      if (seq == null) {
        continue;
      }
      LatLng point = LatLng(row['Latitude'] as double, row['Longitude'] as double);

      if (name != currentName) {
        flush();
        currentName = name;
        group = [];
      }
      group.add(MapEntry(seq, point));
    }
    flush();
  }

  // Build airway edges for a single airway. Points are grouped by sequence value
  // (in ascending order); consecutive sequence groups are joined by connecting each
  // point to the nearest point in the next group, within the segment-length limit.
  void _connectAirwayGroup(String name, List<MapEntry<int, LatLng>> points) {
    // Only route over Victor (V) and RNAV T (T) airways.
    if (!_isAllowedAirway(name)) {
      return;
    }
    List<int> sequences = points.map((e) => e.key).toSet().toList()..sort();
    Map<int, List<LatLng>> bySeq = {};
    for (MapEntry<int, LatLng> e in points) {
      (bySeq[e.key] ??= []).add(e.value);
    }

    for (int gi = 0; gi < sequences.length - 1; gi++) {
      List<LatLng> a = bySeq[sequences[gi]]!;
      List<LatLng> b = bySeq[sequences[gi + 1]]!;
      for (LatLng from in a) {
        LatLng? nearest;
        double best = double.infinity;
        for (LatLng to in b) {
          double d = _geo.calculateDistance(from, to);
          if (d < best) {
            best = d;
            nearest = to;
          }
        }
        if (nearest != null && best > 0 && best <= _maxSegmentLength) {
          _addEdge(_nodeFor(from), _nodeFor(nearest), best);
        }
      }
    }
  }

  // Which airways may be used for routing. In low altitude mode only Victor (V) and
  // RNAV T (T) airways are allowed; otherwise all airways are allowed.
  bool _isAllowedAirway(String name) {
    if (name.isEmpty) {
      return false;
    }
    if (!lowAltitudeOnly) {
      return true;
    }
    String c = name[0].toUpperCase();
    return c == 'V' || c == 'T';
  }

  // Link an airport node to the closest airway waypoints so a route can get on/off.
  // Only the first [airwayNodeCount] nodes are airway waypoints; this prevents
  // linking the two airports directly to one another.
  void _connectAirport(int airportNode, LatLng airportLl, int airwayNodeCount) {
    List<_Candidate> candidates = [];
    for (int id = 0; id < airwayNodeCount; id++) {
      if (id == airportNode) {
        continue;
      }
      double d = _geo.calculateDistance(airportLl, _coords[id]);
      if (d <= _maxTransitionDistance) {
        candidates.add(_Candidate(id, d));
      }
    }
    candidates.sort((a, b) => a.distance.compareTo(b.distance));
    int count = min(_maxTransitionCandidates, candidates.length);
    for (int i = 0; i < count; i++) {
      _Candidate c = candidates[i];
      _addEdge(airportNode, c.id, c.distance * _directLegPenalty);
    }
  }

  List<int>? _dijkstra(int start, int goal) {
    int n = _coords.length;
    List<double> dist = List.filled(n, double.infinity);
    List<int> prev = List.filled(n, -1);
    List<bool> done = List.filled(n, false);

    dist[start] = 0;
    _MinHeap heap = _MinHeap();
    heap.push(start, 0);

    while (!heap.isEmpty) {
      int u = heap.pop();
      if (done[u]) {
        continue;
      }
      done[u] = true;
      if (u == goal) {
        break;
      }
      for (_Edge e in _adjacency[u]) {
        double nd = dist[u] + e.dist;
        if (nd < dist[e.to]) {
          dist[e.to] = nd;
          prev[e.to] = u;
          heap.push(e.to, nd);
        }
      }
    }

    if (dist[goal] == double.infinity) {
      return null;
    }

    // walk back from goal to start
    List<int> nodes = [];
    int cur = goal;
    while (cur != -1) {
      nodes.add(cur);
      if (cur == start) {
        break;
      }
      cur = prev[cur];
    }
    return nodes.reversed.toList();
  }

  // Build the ordered destination list for the path.
  //
  // Intermediate waypoints are resolved by *coordinate* (the exact nav/fix at the
  // airway point). This is deliberate: resolving by identifier instead would be
  // ambiguous, because some fix identifiers collide with airport city names and the
  // generic lookup would then jump to a far-away airport, tearing the route apart.
  Future<List<Destination>> _buildDestinations(Destination origin, Destination destination, List<int> nodes) async {
    List<Destination> result = [origin];
    for (int i = 1; i < nodes.length - 1; i++) {
      Destination d = await MainDatabaseHelper.db.findNearNavOrFixElseGps(_coords[nodes[i]]);
      result.add(d);
    }
    result.add(destination);

    // Collapse accidental repeats (e.g. a fix coinciding with an airport).
    List<Destination> cleaned = [];
    for (Destination d in result) {
      if (cleaned.isEmpty || cleaned.last.locationID != d.locationID) {
        cleaned.add(d);
      }
    }
    return cleaned;
  }
}

class _Edge {
  final int to;
  final double dist;
  _Edge(this.to, this.dist);
}

class _Candidate {
  final int id;
  final double distance;
  _Candidate(this.id, this.distance);
}

// Simple binary min-heap keyed by priority, storing node ids.
class _MinHeap {
  final List<int> _ids = [];
  final List<double> _priorities = [];

  bool get isEmpty => _ids.isEmpty;

  void push(int id, double priority) {
    _ids.add(id);
    _priorities.add(priority);
    int i = _ids.length - 1;
    while (i > 0) {
      int parent = (i - 1) >> 1;
      if (_priorities[parent] <= _priorities[i]) {
        break;
      }
      _swap(i, parent);
      i = parent;
    }
  }

  int pop() {
    int top = _ids[0];
    int last = _ids.length - 1;
    _swap(0, last);
    _ids.removeLast();
    _priorities.removeLast();
    int i = 0;
    int size = _ids.length;
    while (true) {
      int left = 2 * i + 1;
      int right = 2 * i + 2;
      int smallest = i;
      if (left < size && _priorities[left] < _priorities[smallest]) {
        smallest = left;
      }
      if (right < size && _priorities[right] < _priorities[smallest]) {
        smallest = right;
      }
      if (smallest == i) {
        break;
      }
      _swap(i, smallest);
      i = smallest;
    }
    return top;
  }

  void _swap(int a, int b) {
    int ti = _ids[a];
    _ids[a] = _ids[b];
    _ids[b] = ti;
    double tp = _priorities[a];
    _priorities[a] = _priorities[b];
    _priorities[b] = tp;
  }
}
