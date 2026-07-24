import 'package:cloud_firestore/cloud_firestore.dart';

enum SchedulerRole { owner, member }

enum SchedulerMemberStatus { active, pending }

/// Club ops role within a scheduler (independent of ownership).
enum ClubRole { pilot, student, instructor, dispatcher }

SchedulerRole _roleFromString(String? v) =>
    v == "owner" ? SchedulerRole.owner : SchedulerRole.member;

String _roleToString(SchedulerRole r) =>
    r == SchedulerRole.owner ? "owner" : "member";

SchedulerMemberStatus _statusFromString(String? v) =>
    v == "pending" ? SchedulerMemberStatus.pending : SchedulerMemberStatus.active;

String _statusToString(SchedulerMemberStatus s) =>
    s == SchedulerMemberStatus.pending ? "pending" : "active";

ClubRole clubRoleFromString(String? v) {
  switch (v) {
    case "student":
      return ClubRole.student;
    case "instructor":
      return ClubRole.instructor;
    case "dispatcher":
      return ClubRole.dispatcher;
    case "pilot":
    default:
      return ClubRole.pilot;
  }
}

String clubRoleToString(ClubRole r) {
  switch (r) {
    case ClubRole.student:
      return "student";
    case ClubRole.instructor:
      return "instructor";
    case ClubRole.dispatcher:
      return "dispatcher";
    case ClubRole.pilot:
      return "pilot";
  }
}

String clubRoleLabel(ClubRole r) {
  switch (r) {
    case ClubRole.student:
      return "Student";
    case ClubRole.instructor:
      return "Instructor";
    case ClubRole.dispatcher:
      return "Dispatcher";
    case ClubRole.pilot:
      return "Pilot";
  }
}

/// Membership record stored under schedulerGroups/{sgid}/members/{uid}.
class SchedulerMember {
  final String uid;
  final String displayName;
  final SchedulerRole role;
  final SchedulerMemberStatus status;
  final DateTime joinedAt;

  /// Club ops role (student / instructor / dispatcher / pilot).
  final ClubRole clubRole;

  /// For students: the assigned primary instructor (member uid).
  final String? assignedInstructorUid;
  final String? assignedInstructorName;

  const SchedulerMember({
    required this.uid,
    required this.displayName,
    required this.role,
    required this.status,
    required this.joinedAt,
    this.clubRole = ClubRole.pilot,
    this.assignedInstructorUid,
    this.assignedInstructorName,
  });

  bool get isOwner => role == SchedulerRole.owner;
  bool get isPending => status == SchedulerMemberStatus.pending;
  bool get isActive => status == SchedulerMemberStatus.active;
  bool get isStudent => clubRole == ClubRole.student;
  bool get isInstructor => clubRole == ClubRole.instructor;
  bool get isDispatcher => clubRole == ClubRole.dispatcher;

  /// Owner or dispatcher may manage fleet / MX / squawk resolution.
  bool get canDispatch => isOwner || isDispatcher;

  Map<String, dynamic> toMap() => {
        "displayName": displayName,
        "role": _roleToString(role),
        "status": _statusToString(status),
        "joinedAt": Timestamp.fromDate(joinedAt),
        "clubRole": clubRoleToString(clubRole),
        "assignedInstructorUid": assignedInstructorUid,
        "assignedInstructorName": assignedInstructorName,
      };

  factory SchedulerMember.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final ts = data["joinedAt"];
    return SchedulerMember(
      uid: doc.id,
      displayName: (data["displayName"] as String?) ?? "Pilot",
      role: _roleFromString(data["role"] as String?),
      status: _statusFromString(data["status"] as String?),
      joinedAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
      clubRole: clubRoleFromString(data["clubRole"] as String?),
      assignedInstructorUid: data["assignedInstructorUid"] as String?,
      assignedInstructorName: data["assignedInstructorName"] as String?,
    );
  }
}
