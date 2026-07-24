import 'package:cloud_firestore/cloud_firestore.dart';

enum LessonPackStatus { active, completed, cancelled }

LessonPackStatus lessonPackStatusFromString(String? v) {
  switch (v) {
    case "completed":
      return LessonPackStatus.completed;
    case "cancelled":
      return LessonPackStatus.cancelled;
    case "active":
    default:
      return LessonPackStatus.active;
  }
}

String lessonPackStatusToString(LessonPackStatus s) {
  switch (s) {
    case LessonPackStatus.completed:
      return "completed";
    case LessonPackStatus.cancelled:
      return "cancelled";
    case LessonPackStatus.active:
      return "active";
  }
}

/// Prepaid / block lesson hours assigned to a student in a club scheduler.
/// Stored under schedulerGroups/{sgid}/lessonPacks/{pid}.
class LessonPack {
  final String id;
  final String name;
  final String description;
  final double totalHours;
  final double hoursUsed;
  final String studentUid;
  final String studentName;
  final String? instructorUid;
  final String? instructorName;
  final LessonPackStatus status;
  final DateTime createdAt;
  final DateTime? expiresAt;

  const LessonPack({
    required this.id,
    required this.name,
    required this.description,
    required this.totalHours,
    required this.hoursUsed,
    required this.studentUid,
    required this.studentName,
    this.instructorUid,
    this.instructorName,
    required this.status,
    required this.createdAt,
    this.expiresAt,
  });

  double get hoursRemaining {
    final left = totalHours - hoursUsed;
    return left < 0 ? 0 : left;
  }

  bool get isActive => status == LessonPackStatus.active;

  Map<String, dynamic> toCreateMap() => {
        "name": name,
        "description": description,
        "totalHours": totalHours,
        "hoursUsed": hoursUsed,
        "studentUid": studentUid,
        "studentName": studentName,
        "instructorUid": instructorUid,
        "instructorName": instructorName,
        "status": lessonPackStatusToString(status),
        "createdAt": Timestamp.fromDate(createdAt),
        "expiresAt":
            expiresAt == null ? null : Timestamp.fromDate(expiresAt!),
      };

  factory LessonPack.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final c = data["createdAt"];
    final e = data["expiresAt"];
    double asDouble(dynamic v) => v is num ? v.toDouble() : 0;
    return LessonPack(
      id: doc.id,
      name: (data["name"] as String?) ?? "Lesson pack",
      description: (data["description"] as String?) ?? "",
      totalHours: asDouble(data["totalHours"]),
      hoursUsed: asDouble(data["hoursUsed"]),
      studentUid: (data["studentUid"] as String?) ?? "",
      studentName: (data["studentName"] as String?) ?? "Student",
      instructorUid: data["instructorUid"] as String?,
      instructorName: data["instructorName"] as String?,
      status: lessonPackStatusFromString(data["status"] as String?),
      createdAt: c is Timestamp ? c.toDate() : DateTime.now(),
      expiresAt: e is Timestamp ? e.toDate() : null,
    );
  }
}
