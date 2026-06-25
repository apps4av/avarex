import 'package:cloud_firestore/cloud_firestore.dart';

enum SchedulerRole { owner, member }

enum SchedulerMemberStatus { active, pending }

SchedulerRole _roleFromString(String? v) =>
    v == "owner" ? SchedulerRole.owner : SchedulerRole.member;

String _roleToString(SchedulerRole r) =>
    r == SchedulerRole.owner ? "owner" : "member";

SchedulerMemberStatus _statusFromString(String? v) =>
    v == "pending" ? SchedulerMemberStatus.pending : SchedulerMemberStatus.active;

String _statusToString(SchedulerMemberStatus s) =>
    s == SchedulerMemberStatus.pending ? "pending" : "active";

/// Membership record stored under schedulerGroups/{sgid}/members/{uid}.
class SchedulerMember {
  final String uid;
  final String displayName;
  final SchedulerRole role;
  final SchedulerMemberStatus status;
  final DateTime joinedAt;

  const SchedulerMember({
    required this.uid,
    required this.displayName,
    required this.role,
    required this.status,
    required this.joinedAt,
  });

  bool get isOwner => role == SchedulerRole.owner;
  bool get isPending => status == SchedulerMemberStatus.pending;
  bool get isActive => status == SchedulerMemberStatus.active;

  Map<String, dynamic> toMap() => {
        "displayName": displayName,
        "role": _roleToString(role),
        "status": _statusToString(status),
        "joinedAt": Timestamp.fromDate(joinedAt),
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
    );
  }
}
