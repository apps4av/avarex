import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:avaremp/data/app_settings.dart';
import 'package:avaremp/link/link_protocol.dart';
import 'package:avaremp/plan/plan_route.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/app_log.dart';
import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';

/// Another AvareX device heard on the local network.
class LinkPeer {
  LinkPeer({
    required this.id,
    required this.name,
    required this.role,
    required this.address,
    required this.lastSeen,
  });

  final String id;
  String name;
  LinkRole role;
  String address;
  DateTime lastSeen;
}

/// One line in the Link debug window.
class LinkLogEntry {
  LinkLogEntry({
    required this.time,
    required this.outbound,
    required this.address,
    required this.summary,
    required this.body,
  });

  final DateTime time;
  final bool outbound;
  final String address;
  final String summary;
  final String body;
  bool expanded = false;
}

class _RxSeen {
  _RxSeen(this.body, this.at);
  final String body;
  final DateTime at;
}

/// Finds other AvareX devices and, when this device is master, pushes the
/// active plan and the waypoint being flown. Slaves apply that plan.
///
/// Started and stopped with the rest of the app's network IO. The manage
/// screen reads [change], [peers], and [log].
class LinkService {
  static final LinkService _instance = LinkService._();
  factory LinkService() => _instance;
  LinkService._();

  static const Duration _helloInterval = Duration(seconds: 10);
  // Drop a device after a minute with no hello from it.
  static const Duration _peerTimeout = Duration(minutes: 1);
  static const int _maxLog = 200;

  final ValueNotifier<int> change = ValueNotifier<int>(0);

  final Map<String, LinkPeer> _peers = {};
  final List<LinkLogEntry> _log = [];
  final Map<String, _RxSeen> _seen = {};

  RawDatagramSocket? _socket;
  Timer? _helloTimer;
  Timer? _expireTimer;
  Timer? _subnetTimer;
  Timer? _sendDebounce;
  List<InternetAddress> _subnetBroadcasts = [];

  bool _loaded = false;
  bool _running = false;
  bool _routeListening = false;
  bool _applying = false;
  int _generation = 0;
  String _id = "";
  String _name = "AvareX";
  LinkRole _role = LinkRole.off;
  String? _bindError;
  String? _lastSentStamp;
  LinkMessage? _pendingPlan;
  bool logPaused = false;

  bool get isRunning => _running;
  String? get bindError => _bindError;
  String get deviceId => _id;
  String get deviceName => _name;
  LinkRole get role => _role;
  List<LinkLogEntry> get log => List<LinkLogEntry>.unmodifiable(_log);

  List<LinkPeer> get peers {
    final List<LinkPeer> list = _peers.values.toList();
    list.sort((LinkPeer a, LinkPeer b) {
      if (a.role == LinkRole.master && b.role != LinkRole.master) {
        return -1;
      }
      if (b.role == LinkRole.master && a.role != LinkRole.master) {
        return 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  int get otherMasterCount {
    int count = 0;
    for (final LinkPeer peer in _peers.values) {
      if (peer.role == LinkRole.master) {
        count++;
      }
    }
    return count;
  }

  /// Name of a master currently heard, when this device is not that master.
  String? get followedMasterName {
    for (final LinkPeer peer in peers) {
      if (peer.role == LinkRole.master) {
        return peer.name;
      }
    }
    return null;
  }

  /// Reads the saved id, name, and role. Safe to call more than once.
  void load() {
    if (_loaded || kIsWeb) {
      return;
    }
    final AppSettings settings = Storage().settings;
    _loaded = true;
    String id = settings.getLinkDeviceId();
    if (id.isEmpty) {
      id = _randomId();
      settings.setLinkDeviceId(id);
    }
    _id = id;
    final String savedName = settings.getLinkDeviceName().trim();
    if (savedName.isEmpty) {
      _name = _fallbackName();
      settings.setLinkDeviceName(_name);
    } else {
      _name = savedName;
    }
    _role = LinkRole.fromWire(settings.getLinkRole());
  }

  /// Opens the UDP socket and starts announcing. Idempotent.
  Future<void> start() async {
    if (kIsWeb || _running) {
      return;
    }
    load();
    final int generation = ++_generation;
    try {
      final RawDatagramSocket socket = await _bind();
      if (generation != _generation) {
        socket.close();
        return;
      }
      socket.broadcastEnabled = true;
      socket.listen(_onSocketEvent, onError: (Object error) {
        AppLog.logMessage("Link socket error: $error");
      });
      _socket = socket;
      _bindError = null;
      _running = true;
      _listenToRoute();
      await _refreshSubnets();
      if (generation != _generation) {
        return;
      }
      _helloTimer = Timer.periodic(_helloInterval, (_) => _sendHello());
      _expireTimer = Timer.periodic(const Duration(seconds: 2), (_) => _expire());
      _subnetTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _refreshSubnets();
      });
      _sendHello();
      change.value++;
    } catch (e) {
      if (generation != _generation) {
        return;
      }
      _bindError = e.toString();
      _running = false;
      AppLog.logMessage("Link start error: $e");
      change.value++;
    }
  }

  Future<void> stop() async {
    _generation++;
    _running = false;
    _sendDebounce?.cancel();
    _sendDebounce = null;
    _helloTimer?.cancel();
    _expireTimer?.cancel();
    _subnetTimer?.cancel();
    _helloTimer = null;
    _expireTimer = null;
    _subnetTimer = null;
    _unlistenRoute();
    _socket?.close();
    _socket = null;
    _peers.clear();
    _pendingPlan = null;
    change.value++;
  }

  void setRole(LinkRole role) {
    load();
    if (_role == role) {
      return;
    }
    _role = role;
    Storage().settings.setLinkRole(role.name);
    _sendDebounce?.cancel();
    if (_running && role != LinkRole.off) {
      _sendHello();
    }
    change.value++;
  }

  void setName(String value) {
    load();
    final String trimmed = value.trim();
    String next = trimmed.isEmpty ? _fallbackName() : trimmed;
    if (next.length > 48) {
      next = next.substring(0, 48);
    }
    if (next == _name) {
      return;
    }
    _name = next;
    Storage().settings.setLinkDeviceName(_name);
    if (_running && _role != LinkRole.off) {
      _sendHello();
    }
    change.value++;
  }

  /// Sends a hello immediately. The plan is sent only when it changes.
  void announce() {
    if (!_running) {
      return;
    }
    _sendHello();
  }

  void clearLog() {
    _log.clear();
    change.value++;
  }

  Future<RawDatagramSocket> _bind() async {
    try {
      return await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        LinkMessage.port,
        reuseAddress: true,
        reusePort: true,
      );
    } catch (_) {
      return await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        LinkMessage.port,
        reuseAddress: true,
      );
    }
  }

  void _listenToRoute() {
    if (_routeListening) {
      return;
    }
    Storage().route.change.addListener(_onRouteChanged);
    _routeListening = true;
  }

  void _unlistenRoute() {
    if (!_routeListening) {
      return;
    }
    Storage().route.change.removeListener(_onRouteChanged);
    _routeListening = false;
  }

  // The plan notifier also ticks once a second while the aircraft moves.
  // Compare the plan itself so that tick does not transmit.
  void _onRouteChanged() {
    if (!_running || _applying || _role != LinkRole.master) {
      return;
    }
    final String stamp = _routeStamp(Storage().route);
    if (stamp == _lastSentStamp) {
      return;
    }
    _sendDebounce?.cancel();
    _sendDebounce = Timer(const Duration(milliseconds: 250), _broadcastPlan);
  }

  String _routeStamp(PlanRoute route) {
    final int destinationIndex =
        route.getCurrentWaypoint()?.currentDestinationIndex ?? 0;
    return _stamp(route.name, route.currentWaypointIndex, destinationIndex,
        route.linkPointKey);
  }

  String _stamp(String name, int waypointIndex, int destinationIndex, String points) {
    return "$name\n$waypointIndex\n$destinationIndex\n$points";
  }

  void _sendHello() {
    // Off stays silent. Master and slave announce so the others can find them.
    if (!_running || _role == LinkRole.off) {
      return;
    }
    _transmit(LinkMessage.hello(id: _id, name: _name, role: _role), unicast: true);
  }

  void _broadcastPlan() {
    if (!_running || _role != LinkRole.master) {
      return;
    }
    final PlanRoute route = Storage().route;
    final String stamp = _routeStamp(route);
    if (stamp == _lastSentStamp) {
      return;
    }
    List<dynamic> decoded;
    try {
      final Object? value = jsonDecode(route.toLinkJson());
      if (value is! List) {
        return;
      }
      decoded = value;
    } catch (e) {
      AppLog.logMessage("Link plan encode error: $e");
      return;
    }
    final List<Map<String, dynamic>> plan = [];
    for (final dynamic entry in decoded) {
      if (entry is! Map) {
        return;
      }
      plan.add(Map<String, dynamic>.from(entry));
    }
    final int destinationIndex =
        route.getCurrentWaypoint()?.currentDestinationIndex ?? 0;
    _transmit(
      LinkMessage.plan(
        id: _id,
        name: _name,
        role: _role,
        planName: route.name,
        waypointIndex: route.currentWaypointIndex,
        destinationIndex: destinationIndex,
        plan: plan,
      ),
      unicast: true,
    );
    _lastSentStamp = stamp;
  }

  void _transmit(LinkMessage message, {required bool unicast}) {
    final RawDatagramSocket? socket = _socket;
    if (socket == null) {
      return;
    }
    final String body = message.encode();
    final List<int> data = utf8.encode(body);
    if (data.length > 60000) {
      _addLog(LinkLogEntry(
        time: DateTime.now(),
        outbound: true,
        address: "local",
        summary: "too large",
        body: "Plan is too large to send (${data.length} bytes).",
      ));
      change.value++;
      return;
    }
    final Set<String> sent = {};
    void sendTo(InternetAddress address) {
      if (!sent.add(address.address)) {
        return;
      }
      try {
        socket.send(data, address, LinkMessage.port);
      } catch (e) {
        AppLog.logMessage("Link send error: $e");
      }
    }

    sendTo(InternetAddress("255.255.255.255"));
    for (final InternetAddress address in _subnetBroadcasts) {
      sendTo(address);
    }
    if (unicast) {
      for (final LinkPeer peer in _peers.values) {
        try {
          sendTo(InternetAddress(peer.address));
        } catch (_) {
          // skip a peer address the stack will not send to
        }
      }
    }
    _addLog(LinkLogEntry(
      time: DateTime.now(),
      outbound: true,
      address: "broadcast",
      summary: message.summary,
      body: body,
    ));
    change.value++;
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) {
      return;
    }
    final RawDatagramSocket? socket = _socket;
    if (socket == null) {
      return;
    }
    while (true) {
      final Datagram? dg = socket.receive();
      if (dg == null) {
        break;
      }
      _onDatagram(dg);
    }
  }

  void _onDatagram(Datagram dg) {
    final String raw;
    try {
      raw = utf8.decode(dg.data);
    } catch (_) {
      return;
    }
    final String address = dg.address.address;
    final LinkMessage? message = LinkMessage.tryParse(raw);
    if (message == null) {
      _addLog(LinkLogEntry(
        time: DateTime.now(),
        outbound: false,
        address: address,
        summary: "ignored",
        body: raw,
      ));
      change.value++;
      return;
    }
    // A broadcast often comes back to the sender. Drop it before it is logged
    // or applied, so the master never loads its own plan and transmits again.
    if (message.id == _id) {
      return;
    }
    if (_isDuplicate(message, raw)) {
      return;
    }
    _addLog(LinkLogEntry(
      time: DateTime.now(),
      outbound: false,
      address: address,
      summary: message.summary,
      body: raw,
    ));
    _notePeer(message, address);
    if (message.isPlan) {
      _queuePlan(message);
    }
    change.value++;
  }

  bool _isDuplicate(LinkMessage message, String raw) {
    final String key = "${message.id}|${message.type}";
    final DateTime now = DateTime.now();
    final _RxSeen? prev = _seen[key];
    if (prev != null &&
        prev.body == raw &&
        now.difference(prev.at) < const Duration(seconds: 1)) {
      return true;
    }
    _seen[key] = _RxSeen(raw, now);
    return false;
  }

  void _notePeer(LinkMessage message, String address) {
    final LinkPeer peer = _peers.putIfAbsent(
      message.id,
      () => LinkPeer(
        id: message.id,
        name: message.name,
        role: message.role,
        address: address,
        lastSeen: DateTime.now(),
      ),
    );
    peer.name = message.name;
    peer.role = message.role;
    peer.address = address;
    peer.lastSeen = DateTime.now();
  }

  void _queuePlan(LinkMessage message) {
    if (_role != LinkRole.slave || message.role != LinkRole.master) {
      return;
    }
    _pendingPlan = message;
    _drainPlans();
  }

  Future<void> _drainPlans() async {
    if (_applying) {
      return;
    }
    final LinkMessage? message = _pendingPlan;
    if (message == null) {
      return;
    }
    _pendingPlan = null;
    if (_role != LinkRole.slave || message.role != LinkRole.master) {
      if (_pendingPlan != null) {
        _drainPlans();
      }
      return;
    }
    _applying = true;
    try {
      await _applyOne(message);
    } catch (e, st) {
      AppLog.logMessage("Link plan apply error: $e\n$st");
      _addLog(LinkLogEntry(
        time: DateTime.now(),
        outbound: false,
        address: "local",
        summary: "apply failed",
        body: "$e",
      ));
      change.value++;
    } finally {
      _applying = false;
    }
    if (_pendingPlan != null) {
      await _drainPlans();
    }
  }

  Future<void> _applyOne(LinkMessage message) async {
    final PlanRoute route = Storage().route;
    if (route.linkPointKey == message.pointKey) {
      if (route.name != message.planName) {
        route.name = message.planName;
        route.change.value++;
      }
      _applyActive(route, message);
      return;
    }
    PlanRoute incoming = await PlanRoute.fromLink(
      jsonEncode(message.plan),
      message.planName,
      message.waypointIndex,
      message.destinationIndex,
    );
    route.copyFrom(incoming);
    if (message.waypointIndex >= 0 && message.waypointIndex < route.length) {
      route.setCurrentWaypoint(message.waypointIndex);
      route.setCurrentWaypointDestinationIndex(message.destinationIndex);
    }
  }

  void _applyActive(PlanRoute route, LinkMessage message) {
    if (message.waypointIndex >= 0 &&
        message.waypointIndex < route.length &&
        route.currentWaypointIndex != message.waypointIndex) {
      route.setCurrentWaypoint(message.waypointIndex);
    }
    final int destinationIndex =
        route.getCurrentWaypoint()?.currentDestinationIndex ?? 0;
    if (destinationIndex != message.destinationIndex) {
      route.setCurrentWaypointDestinationIndex(message.destinationIndex);
    }
  }

  void _expire() {
    final DateTime cutoff = DateTime.now().subtract(_peerTimeout);
    final int before = _peers.length;
    _peers.removeWhere((_, LinkPeer peer) => peer.lastSeen.isBefore(cutoff));
    if (_peers.length != before) {
      change.value++;
    }
  }

  Future<void> _refreshSubnets() async {
    final List<InternetAddress> found = [];
    try {
      final List<NetworkInterface> interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final NetworkInterface iface in interfaces) {
        for (final InternetAddress addr in iface.addresses) {
          if (addr.isLoopback) {
            continue;
          }
          final List<String> parts = addr.address.split(".");
          if (parts.length != 4) {
            continue;
          }
          found.add(InternetAddress("${parts[0]}.${parts[1]}.${parts[2]}.255"));
        }
      }
    } catch (e) {
      AppLog.logMessage("Link interface error: $e");
    }
    _subnetBroadcasts = found;
  }

  void _addLog(LinkLogEntry entry) {
    if (logPaused) {
      return;
    }
    _log.insert(0, entry);
    if (_log.length > _maxLog) {
      _log.removeRange(_maxLog, _log.length);
    }
  }

  String _randomId() {
    final Random random = Random.secure();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < 16; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, "0"));
    }
    return buffer.toString();
  }

  String _fallbackName() {
    String host = "";
    try {
      host = Platform.localHostname.trim();
    } catch (_) {
      host = "";
    }
    if (host.isEmpty || host.toLowerCase() == "localhost") {
      final String tail = _id.length >= 4 ? _id.substring(_id.length - 4) : _id;
      return "AvareX $tail";
    }
    return host;
  }
}
