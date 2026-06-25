import 'package:cloud_firestore/cloud_firestore.dart';

enum ResourceType { aircraft, instructor }

ResourceType resourceTypeFromString(String? v) =>
    v == "instructor" ? ResourceType.instructor : ResourceType.aircraft;

String resourceTypeToString(ResourceType t) =>
    t == ResourceType.instructor ? "instructor" : "aircraft";

/// A schedulable resource owned by a scheduler group: an aircraft or a
/// flight instructor. Stored under schedulerGroups/{sgid}/resources/{rid}.
class SchedulableResource {
  final String id;
  final String name;
  final ResourceType type;
  final String? identifier; // tail number for aircraft, etc.
  final bool available; // false == out of service / unavailable (red)
  final DateTime createdAt;

  const SchedulableResource({
    required this.id,
    required this.name,
    required this.type,
    this.identifier,
    this.available = true,
    required this.createdAt,
  });

  bool get isAircraft => type == ResourceType.aircraft;

  Map<String, dynamic> toMap() => {
        "name": name,
        "type": resourceTypeToString(type),
        "identifier": identifier,
        "available": available,
        "createdAt": Timestamp.fromDate(createdAt),
      };

  factory SchedulableResource.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final ts = data["createdAt"];
    return SchedulableResource(
      id: doc.id,
      name: (data["name"] as String?) ?? "Resource",
      type: resourceTypeFromString(data["type"] as String?),
      identifier: data["identifier"] as String?,
      available: (data["available"] as bool?) ?? true,
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}
