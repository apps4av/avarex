import 'dart:convert';
import 'dart:typed_data';

import 'package:avaremp/visual_traffic/detection_models.dart';

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
///
/// Visual Traffic (a camera device spotting aircraft, and a viewer showing
/// them) adds three types. Older builds ignore all three. Roles do not matter
/// for these, so a device with Link off still sends and receives them.
///
/// `detections`, about 10 times a second, broadcast by the camera device.
/// Boxes are normalized to the upright picture (see `DetectionFrame`):
///
/// ```json
/// {"avarex":1,"type":"detections","id":"<id>","name":"Pilot phone","role":"off",
///  "seq":812,"ts":1790000000000,"fovH":65,"fovV":37,"hl":0.52,"hr":0.58,
///  "boxes":[{"id":3,"x":0.41,"y":0.2,"w":0.02,"h":0.02,"c":0.62,"t":"airplane"}]}
/// ```
///
/// `watch`, every 2 seconds, unicast by a viewer to the camera device it is
/// showing. While a watch is fresh the camera device also sends `preview`.
///
/// ```json
/// {"avarex":1,"type":"watch","id":"<viewer id>","name":"iPad","role":"off","target":"<camera id>"}
/// ```
///
/// `preview`, a few times a second, unicast to each fresh viewer. A small
/// grayscale JPEG (base64) of the upright picture. It is kept under about
/// 8 KB so it fits one UDP datagram on every platform.
///
/// ```json
/// {"avarex":1,"type":"preview","id":"<id>","name":"Pilot phone","role":"off",
///  "seq":812,"pw":240,"ph":135,"jpg":"<base64>"}
/// ```
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

  /// `detections` only.
  final DetectionFrame? detections;

  /// `preview` only: JPEG bytes, their picture size, and the frame they match.
  final Uint8List? preview;
  final int previewWidth;
  final int previewHeight;
  final int previewSeq;

  /// `watch` only: id of the camera device being watched.
  final String target;

  LinkMessage._({
    required this.type,
    required this.id,
    required this.name,
    required this.role,
    required this.planName,
    required this.waypointIndex,
    required this.destinationIndex,
    required this.plan,
    this.detections,
    this.preview,
    this.previewWidth = 0,
    this.previewHeight = 0,
    this.previewSeq = 0,
    this.target = "",
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

  factory LinkMessage.detections({
    required String id,
    required String name,
    required LinkRole role,
    required DetectionFrame detections,
  }) {
    return LinkMessage._(
      type: "detections",
      id: id,
      name: name,
      role: role,
      planName: "",
      waypointIndex: -1,
      destinationIndex: 0,
      plan: const [],
      detections: detections,
    );
  }

  factory LinkMessage.preview({
    required String id,
    required String name,
    required LinkRole role,
    required int seq,
    required int width,
    required int height,
    required Uint8List jpeg,
  }) {
    return LinkMessage._(
      type: "preview",
      id: id,
      name: name,
      role: role,
      planName: "",
      waypointIndex: -1,
      destinationIndex: 0,
      plan: const [],
      preview: jpeg,
      previewWidth: width,
      previewHeight: height,
      previewSeq: seq,
    );
  }

  factory LinkMessage.watch({
    required String id,
    required String name,
    required LinkRole role,
    required String target,
  }) {
    return LinkMessage._(
      type: "watch",
      id: id,
      name: name,
      role: role,
      planName: "",
      waypointIndex: -1,
      destinationIndex: 0,
      plan: const [],
      target: target,
    );
  }

  bool get isHello => type == "hello";
  bool get isPlan => type == "plan";
  bool get isDetections => type == "detections";
  bool get isPreview => type == "preview";
  bool get isWatch => type == "watch";

  /// Frequent Visual Traffic traffic. Kept out of the debug log and the
  /// duplicate filter so it cannot push plan messages out of view.
  bool get isVisual => isDetections || isPreview || isWatch;

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
    if (isDetections) {
      return "detections  $name  ${detections?.boxes.length ?? 0} boxes";
    }
    if (isPreview) {
      return "preview  $name  ${preview?.length ?? 0} bytes";
    }
    if (isWatch) {
      return "watch  $name";
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
    if (isDetections && detections != null) {
      map.addAll(detections!.toJson());
    }
    if (isPreview && preview != null) {
      map["seq"] = previewSeq;
      map["pw"] = previewWidth;
      map["ph"] = previewHeight;
      map["jpg"] = base64Encode(preview!);
    }
    if (isWatch) {
      map["target"] = target;
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
      if (type != "hello" &&
          type != "plan" &&
          type != "detections" &&
          type != "preview" &&
          type != "watch") {
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
      if (type == "detections") {
        final DetectionFrame? frame = DetectionFrame.fromJson(map);
        if (frame == null) {
          return null;
        }
        return LinkMessage.detections(
            id: id, name: name, role: role, detections: frame);
      }
      if (type == "preview") {
        final Object? jpg = map["jpg"];
        if (jpg is! String || jpg.isEmpty) {
          return null;
        }
        return LinkMessage.preview(
          id: id,
          name: name,
          role: role,
          seq: _asInt(map["seq"], fallback: 0),
          width: _asInt(map["pw"], fallback: 0),
          height: _asInt(map["ph"], fallback: 0),
          jpeg: base64Decode(jpg),
        );
      }
      if (type == "watch") {
        final Object? target = map["target"];
        if (target is! String || target.isEmpty) {
          return null;
        }
        return LinkMessage.watch(
            id: id, name: name, role: role, target: target);
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
