import 'package:cloud_firestore/cloud_firestore.dart';

enum GroupVisibility { public, private }

GroupVisibility _visibilityFromString(String? v) {
  switch (v) {
    case "private":
      return GroupVisibility.private;
    case "public":
    default:
      return GroupVisibility.public;
  }
}

String _visibilityToString(GroupVisibility v) =>
    v == GroupVisibility.private ? "private" : "public";

/// A pilot community / group.
class PilotGroup {
  final String id;
  final String name;
  final String description;
  final String? homeAirport; // ICAO, uppercase
  final List<String> tags;
  final GroupVisibility visibility;
  final String ownerUid;
  final String ownerName;
  final int memberCount;
  final int postCount;
  final DateTime createdAt;

  const PilotGroup({
    required this.id,
    required this.name,
    required this.description,
    this.homeAirport,
    this.tags = const [],
    required this.visibility,
    required this.ownerUid,
    required this.ownerName,
    this.memberCount = 0,
    this.postCount = 0,
    required this.createdAt,
  });

  bool get isPrivate => visibility == GroupVisibility.private;

  Map<String, dynamic> toCreateMap() => {
        "name": name,
        "nameLower": name.toLowerCase(),
        "description": description,
        "homeAirport": homeAirport?.toUpperCase(),
        "tags": tags,
        "visibility": _visibilityToString(visibility),
        "ownerUid": ownerUid,
        "ownerName": ownerName,
        "memberCount": memberCount,
        "postCount": postCount,
        "createdAt": Timestamp.fromDate(createdAt),
      };

  factory PilotGroup.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final ts = data["createdAt"];
    return PilotGroup(
      id: doc.id,
      name: (data["name"] as String?) ?? "Unnamed",
      description: (data["description"] as String?) ?? "",
      homeAirport: data["homeAirport"] as String?,
      tags: List<String>.from((data["tags"] as List?) ?? const []),
      visibility: _visibilityFromString(data["visibility"] as String?),
      ownerUid: (data["ownerUid"] as String?) ?? "",
      ownerName: (data["ownerName"] as String?) ?? "",
      memberCount: (data["memberCount"] as int?) ?? 0,
      postCount: (data["postCount"] as int?) ?? 0,
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}
