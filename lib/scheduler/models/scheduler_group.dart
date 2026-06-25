import 'package:cloud_firestore/cloud_firestore.dart';

enum SchedulerVisibility { public, private }

SchedulerVisibility _visibilityFromString(String? v) {
  switch (v) {
    case "private":
      return SchedulerVisibility.private;
    case "public":
    default:
      return SchedulerVisibility.public;
  }
}

String _visibilityToString(SchedulerVisibility v) =>
    v == SchedulerVisibility.private ? "private" : "public";

/// An aircraft scheduler group (e.g. a flying club). Members reserve the
/// resources the owner adds; the owner manages resources and reservations.
class SchedulerGroup {
  final String id;
  final String name;
  final String description;
  final String? homeAirport; // ICAO, uppercase
  final SchedulerVisibility visibility;
  final String ownerUid;
  final String ownerName;
  final int memberCount;
  final int resourceCount;

  /// Booking rules set by the owner. 0 means "unlimited".
  final int maxReservationsPerMember;
  final int maxWeekendReservations;

  final DateTime createdAt;

  const SchedulerGroup({
    required this.id,
    required this.name,
    required this.description,
    this.homeAirport,
    required this.visibility,
    required this.ownerUid,
    required this.ownerName,
    this.memberCount = 0,
    this.resourceCount = 0,
    this.maxReservationsPerMember = 0,
    this.maxWeekendReservations = 0,
    required this.createdAt,
  });

  bool get isPrivate => visibility == SchedulerVisibility.private;

  Map<String, dynamic> toCreateMap() => {
        "name": name,
        "nameLower": name.toLowerCase(),
        "description": description,
        "homeAirport": homeAirport?.toUpperCase(),
        "visibility": _visibilityToString(visibility),
        "ownerUid": ownerUid,
        "ownerName": ownerName,
        "memberCount": memberCount,
        "resourceCount": resourceCount,
        "maxReservationsPerMember": maxReservationsPerMember,
        "maxWeekendReservations": maxWeekendReservations,
        "createdAt": Timestamp.fromDate(createdAt),
      };

  factory SchedulerGroup.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final ts = data["createdAt"];
    return SchedulerGroup(
      id: doc.id,
      name: (data["name"] as String?) ?? "Unnamed",
      description: (data["description"] as String?) ?? "",
      homeAirport: data["homeAirport"] as String?,
      visibility: _visibilityFromString(data["visibility"] as String?),
      ownerUid: (data["ownerUid"] as String?) ?? "",
      ownerName: (data["ownerName"] as String?) ?? "",
      memberCount: (data["memberCount"] as int?) ?? 0,
      resourceCount: (data["resourceCount"] as int?) ?? 0,
      maxReservationsPerMember:
          (data["maxReservationsPerMember"] as int?) ?? 0,
      maxWeekendReservations: (data["maxWeekendReservations"] as int?) ?? 0,
      createdAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}
