import 'package:cloud_firestore/cloud_firestore.dart';

/// A reservation of a resource for a time window made by a member.
///
/// Stored under schedulerGroups/{sgid}/reservations/{resvId}.
///
/// When more than one member books the same resource for overlapping times,
/// the first becomes the "main" reservation ([isBackup] == false) and the
/// rest are queued as backups ([isBackup] == true) ordered by [backupOrder].
/// If the main reservation is cancelled, the next backup in line is promoted
/// to main.
class Reservation {
  final String id;
  final String resourceId;
  final String resourceName;
  final String schedulerUid; // who made the reservation
  final String schedulerName;
  final DateTime start;
  final DateTime end;
  final bool isBackup;
  final int backupOrder; // 0 for main; 1..n for backups in queue order
  final String? note;
  final DateTime createdAt;

  const Reservation({
    required this.id,
    required this.resourceId,
    required this.resourceName,
    required this.schedulerUid,
    required this.schedulerName,
    required this.start,
    required this.end,
    this.isBackup = false,
    this.backupOrder = 0,
    this.note,
    required this.createdAt,
  });

  bool get isMain => !isBackup;

  /// True if this reservation's time window overlaps [otherStart, otherEnd).
  bool overlaps(DateTime otherStart, DateTime otherEnd) {
    return start.isBefore(otherEnd) && otherStart.isBefore(end);
  }

  Map<String, dynamic> toCreateMap() => {
        "resourceId": resourceId,
        "resourceName": resourceName,
        "schedulerUid": schedulerUid,
        "schedulerName": schedulerName,
        "start": Timestamp.fromDate(start),
        "end": Timestamp.fromDate(end),
        "isBackup": isBackup,
        "backupOrder": backupOrder,
        "note": note,
        "createdAt": Timestamp.fromDate(createdAt),
      };

  factory Reservation.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final s = data["start"];
    final e = data["end"];
    final c = data["createdAt"];
    return Reservation(
      id: doc.id,
      resourceId: (data["resourceId"] as String?) ?? "",
      resourceName: (data["resourceName"] as String?) ?? "",
      schedulerUid: (data["schedulerUid"] as String?) ?? "",
      schedulerName: (data["schedulerName"] as String?) ?? "Pilot",
      start: s is Timestamp ? s.toDate() : DateTime.now(),
      end: e is Timestamp ? e.toDate() : DateTime.now(),
      isBackup: (data["isBackup"] as bool?) ?? false,
      backupOrder: (data["backupOrder"] as int?) ?? 0,
      note: data["note"] as String?,
      createdAt: c is Timestamp ? c.toDate() : DateTime.now(),
    );
  }
}
