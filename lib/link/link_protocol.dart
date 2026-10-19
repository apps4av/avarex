import 'dart:convert';

/// Role of this device on the local AvareX link.
///
/// One device is [master]. Every [slave] copies that device's plan and the
/// waypoint it is flying. [off] does not announce or apply a plan. The choice
/// is stored and restored when the app starts.
enum LinkRole {
  off,
  master,
  slave;

  static LinkRole fromWire(String raw) {
    switch (raw) {
      case "master":
        return LinkRole.master;
      case "slave":
        return LinkRole.slave;
      default:
        return LinkRole.off;
    }
  }
}

/// JSON messages exchanged by AvareX devices on the same Wi-Fi network.
///
/// Datagrams are UTF-8 JSON, sent to UDP port [port] (broadcast, and unicast
/// to devices already heard). Every message carries `"avarex": 1`. Unknown
/// versions and types are ignored.
///
/// Discovery (`hello`), every 10 seconds, from a master or a slave. Off does
/// not transmit:
///
/// ```json
/// {"avarex":1,"type":"hello","id":"<id>","name":"Panel iPad","role":"master"}
/// ```
///
/// Plan sync (`plan`), from the master only when the plan changes: a waypoint
/// added, removed, or reordered, or the active waypoint (and the fix inside an
/// airway or procedure). `plan` is the same destination array the plan editor stores. Airways
/// and procedures are the airway or procedure itself, not the fix currently
/// being flown. `waypointIndex` is the active plan row. `destinationIndex` is
/// the fix inside that row when it is an airway or procedure (otherwise 0).
///
/// ```json
/// {"avarex":1,"type":"plan","id":"<id>","name":"Panel iPad","role":"master",
///  "planName":"New Plan","waypointIndex":1,"destinationIndex":0,
///  "plan":[{"LocationID":"KBOS","FacilityName":"BOSTON","Type":"AIRPORT",
///           "ARPLatitude":42.36,"ARPLongitude":-71.01}]}
/// ```
///
/// A slave applies a `plan` message only when the sender's role is `master`
/// and the id is not its own.
class LinkMessage {
  static const int version = 1;
  static const int port = 49090;

  final String type;
  final String id;
  final String name;
  final LinkRole role;
  final String planName;
  final int waypointIndex;
  final int destinationIndex;
  final List<Map<String, dynamic>> plan;

  LinkMessage._({
    required this.type,
    required this.id,
    required this.name,
    required this.role,
    required this.planName,
    required this.waypointIndex,
    required this.destinationIndex,
    required this.plan,
  });

  factory LinkMessage.hello({
    required String id,
    required String name,
    required LinkRole role,
  }) {
    return LinkMessage._(
      type: "hello",
      id: id,
      name: name,
      role: role,
      planName: "",
      waypointIndex: -1,
      destinationIndex: 0,
      plan: const [],
    );
  }

  factory LinkMessage.plan({
    required String id,
    required String name,
    required LinkRole role,
    required String planName,
    required int waypointIndex,
    required int destinationIndex,
    required List<Map<String, dynamic>> plan,
  }) {
    return LinkMessage._(
      type: "plan",
      id: id,
      name: name,
      role: role,
      planName: planName,
      waypointIndex: waypointIndex,
      destinationIndex: destinationIndex,
      plan: plan,
    );
  }

  bool get isHello => type == "hello";
  bool get isPlan => type == "plan";

  /// `id|type` for each plan row, in order. Coordinates are left out so two
  /// devices can treat the same airway as the same plan after each looks it
  /// up in its own database.
  String get pointKey {
    return plan.map((Map<String, dynamic> entry) =>
        "${entry["LocationID"]}|${entry["Type"]}").join("\n");
  }

  String get summary {
    if (isPlan) {
      final String leg = destinationIndex > 0
          ? "$waypointIndex.$destinationIndex"
          : "$waypointIndex";
      return "plan  $name  $planName  wp $leg  (${plan.length})";
    }
    return "hello  $name  ${role.name}";
  }

  String encode() {
    final Map<String, Object?> map = {
      "avarex": version,
      "type": type,
      "id": id,
      "name": name,
      "role": role.name,
    };
    if (isPlan) {
      map["planName"] = planName;
      map["waypointIndex"] = waypointIndex;
      map["destinationIndex"] = destinationIndex;
      map["plan"] = plan;
    }
    return jsonEncode(map);
  }

  /// Returns null when [raw] is not a version-1 AvareX message.
  static LinkMessage? tryParse(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final Map<String, dynamic> map = Map<String, dynamic>.from(decoded);
      final Object? versionValue = map["avarex"];
      if (versionValue is! num || versionValue.toInt() != version) {
        return null;
      }
      final Object? type = map["type"];
      if (type != "hello" && type != "plan") {
        return null;
      }
      final Object? id = map["id"];
      if (id is! String || id.isEmpty) {
        return null;
      }
      final Object? nameRaw = map["name"];
      final String name = nameRaw is String && nameRaw.trim().isNotEmpty
          ? nameRaw.trim()
          : "AvareX";
      final Object? roleRaw = map["role"];
      final LinkRole role =
          LinkRole.fromWire(roleRaw is String ? roleRaw : "");
      if (type == "hello") {
        return LinkMessage.hello(id: id, name: name, role: role);
      }
      final Object? planNameRaw = map["planName"];
      final String planName = planNameRaw is String && planNameRaw.isNotEmpty
          ? planNameRaw
          : "New Plan";
      final Object? planRaw = map["plan"];
      if (planRaw is! List) {
        return null;
      }
      final List<Map<String, dynamic>> plan = [];
      for (final Object? entry in planRaw) {
        if (entry is! Map) {
          return null;
        }
        plan.add(_waypoint(entry));
      }
      return LinkMessage.plan(
        id: id,
        name: name,
        role: role,
        planName: planName,
        waypointIndex: _asInt(map["waypointIndex"], fallback: -1),
        destinationIndex: _asInt(map["destinationIndex"], fallback: 0),
        plan: plan,
      );
    } catch (_) {
      return null;
    }
  }

  static int _asInt(Object? value, {required int fallback}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return fallback;
  }

  static Map<String, dynamic> _waypoint(Map<dynamic, dynamic> raw) {
    final Map<String, dynamic> map = {};
    for (final MapEntry<dynamic, dynamic> entry in raw.entries) {
      map[entry.key.toString()] = entry.value;
    }
    if (map["LocationID"] is! String || map["Type"] is! String) {
      throw const FormatException("waypoint missing id");
    }
    if (map["FacilityName"] is! String) {
      map["FacilityName"] = map["LocationID"];
    }
    for (final String key in ["ARPLatitude", "ARPLongitude"]) {
      final Object? value = map[key];
      if (value is! num) {
        throw const FormatException("waypoint missing coordinate");
      }
      map[key] = value.toDouble();
    }
    return map;
  }
}
