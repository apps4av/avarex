import 'package:cloud_firestore/cloud_firestore.dart';

enum MemberRole { owner, member }

enum MemberStatus { active, pending }

MemberRole _roleFromString(String? v) =>
    v == "owner" ? MemberRole.owner : MemberRole.member;

String _roleToString(MemberRole r) => r == MemberRole.owner ? "owner" : "member";

MemberStatus _statusFromString(String? v) =>
    v == "pending" ? MemberStatus.pending : MemberStatus.active;

String _statusToString(MemberStatus s) =>
    s == MemberStatus.pending ? "pending" : "active";

/// Membership record stored under groups/{gid}/members/{uid}.
class GroupMember {
  final String uid;
  final String displayName;
  final String? homeAirport;
  final MemberRole role;
  final MemberStatus status;
  final DateTime joinedAt;

  const GroupMember({
    required this.uid,
    required this.displayName,
    this.homeAirport,
    required this.role,
    required this.status,
    required this.joinedAt,
  });

  bool get isOwner => role == MemberRole.owner;
  bool get isPending => status == MemberStatus.pending;
  bool get isActive => status == MemberStatus.active;

  Map<String, dynamic> toMap() => {
        "displayName": displayName,
        "homeAirport": homeAirport,
        "role": _roleToString(role),
        "status": _statusToString(status),
        "joinedAt": Timestamp.fromDate(joinedAt),
      };

  factory GroupMember.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final ts = data["joinedAt"];
    return GroupMember(
      uid: doc.id,
      displayName: (data["displayName"] as String?) ?? "Pilot",
      homeAirport: data["homeAirport"] as String?,
      role: _roleFromString(data["role"] as String?),
      status: _statusFromString(data["status"] as String?),
      joinedAt: ts is Timestamp ? ts.toDate() : DateTime.now(),
    );
  }
}
