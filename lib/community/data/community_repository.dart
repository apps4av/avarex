import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/group_member.dart';
import '../models/group_post.dart';
import '../models/pilot_group.dart';
import '../models/pilot_profile.dart';

/// All Firestore interaction for the Community feature is funneled through
/// this repository so the rest of the UI never touches Firestore directly.
///
/// Collection layout:
///   users/{uid}                                  -> PilotProfile
///   groups/{gid}                                 -> PilotGroup
///   groups/{gid}/members/{uid}                   -> GroupMember
///   groups/{gid}/posts/{pid}                     -> GroupPost
///   userGroups/{uid}/groups/{gid}                -> denormalized membership index
class CommunityRepository {
  CommunityRepository._();
  static final CommunityRepository instance = CommunityRepository._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  String _requireUid() {
    final uid = _uid;
    if (uid == null) {
      throw StateError("Not signed in");
    }
    return uid;
  }

  // -------------------- Profile --------------------

  DocumentReference<Map<String, dynamic>> _profileRef(String uid) =>
      _db.collection("users").doc(uid);

  Future<PilotProfile> ensureMyProfile() async {
    final uid = _requireUid();
    final ref = _profileRef(uid);
    final snap = await ref.get();
    if (snap.exists) {
      return PilotProfile.fromDoc(snap);
    }
    final initial = PilotProfile.empty(
      uid,
      FirebaseAuth.instance.currentUser?.displayName ??
          FirebaseAuth.instance.currentUser?.email?.split("@").first,
    );
    await ref.set(initial.toMap());
    return initial;
  }

  Stream<PilotProfile?> watchMyProfile() {
    final uid = _uid;
    if (uid == null) {
      return Stream.value(null);
    }
    return _profileRef(uid).snapshots().map(
        (s) => s.exists ? PilotProfile.fromDoc(s) : null);
  }

  Future<void> saveMyProfile(PilotProfile profile) async {
    final uid = _requireUid();
    await _profileRef(uid).set(profile.toMap(), SetOptions(merge: true));
  }

  // -------------------- Groups --------------------

  CollectionReference<Map<String, dynamic>> get _groupsCol =>
      _db.collection("groups");

  DocumentReference<Map<String, dynamic>> _groupRef(String gid) =>
      _groupsCol.doc(gid);

  CollectionReference<Map<String, dynamic>> _membersCol(String gid) =>
      _groupRef(gid).collection("members");

  CollectionReference<Map<String, dynamic>> _postsCol(String gid) =>
      _groupRef(gid).collection("posts");

  DocumentReference<Map<String, dynamic>> _userGroupRef(String uid, String gid) =>
      _db.collection("userGroups").doc(uid).collection("groups").doc(gid);

  Stream<PilotGroup?> watchGroup(String groupId) {
    return _groupRef(groupId)
        .snapshots()
        .map((s) => s.exists ? PilotGroup.fromDoc(s) : null);
  }

  /// Discover tab query.
  ///
  /// * When the user is browsing (no query), only **public** groups are shown
  ///   so the default Discover view doesn't expose every private group's
  ///   metadata to strangers.
  /// * When the user types a search term, **both** public and private groups
  ///   match by name-prefix. Private groups are intentionally discoverable by
  ///   exact-ish name so members can find them and tap "Request to Join";
  ///   the feed itself remains locked down at the posts subcollection rule.
  Stream<List<PilotGroup>> discoverGroups({String? query, int limit = 50}) {
    final trimmed = query?.trim() ?? "";
    if (trimmed.isNotEmpty) {
      final lower = trimmed.toLowerCase();
      return _groupsCol
          .where("nameLower", isGreaterThanOrEqualTo: lower)
          .where("nameLower", isLessThan: "$lower\uf8ff")
          .orderBy("nameLower")
          .limit(limit)
          .snapshots()
          .map((s) =>
              s.docs.map(PilotGroup.fromDoc).toList(growable: false));
    }
    return _groupsCol
        .where("visibility", isEqualTo: "public")
        .orderBy("memberCount", descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs.map(PilotGroup.fromDoc).toList(growable: false));
  }

  /// Groups the current user belongs to.
  Stream<List<PilotGroup>> watchMyGroups() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _db
        .collection("userGroups")
        .doc(uid)
        .collection("groups")
        .where("status", isEqualTo: "active")
        .snapshots()
        .asyncMap((snap) async {
      if (snap.docs.isEmpty) return <PilotGroup>[];
      final ids = snap.docs.map((d) => d.id).toList();
      final List<PilotGroup> groups = [];
      // Firestore whereIn caps at 30; chunk if needed.
      for (var i = 0; i < ids.length; i += 30) {
        final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
        final qs = await _groupsCol
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        groups.addAll(qs.docs.map(PilotGroup.fromDoc));
      }
      groups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return groups;
    });
  }

  /// Create a new group; current user becomes the owner.
  Future<String> createGroup({
    required String name,
    required String description,
    required GroupVisibility visibility,
    String? homeAirport,
    List<String> tags = const [],
  }) async {
    final uid = _requireUid();
    final profile = await ensureMyProfile();

    final groupRef = _groupsCol.doc();
    final now = DateTime.now();
    final group = PilotGroup(
      id: groupRef.id,
      name: name.trim(),
      description: description.trim(),
      homeAirport: homeAirport?.trim().toUpperCase(),
      tags: tags,
      visibility: visibility,
      ownerUid: uid,
      ownerName: profile.displayName,
      memberCount: 1,
      postCount: 0,
      createdAt: now,
    );

    final ownerMember = GroupMember(
      uid: uid,
      displayName: profile.displayName,
      homeAirport: profile.homeAirport,
      role: MemberRole.owner,
      status: MemberStatus.active,
      joinedAt: now,
    );

    final batch = _db.batch();
    batch.set(groupRef, group.toCreateMap());
    batch.set(_membersCol(groupRef.id).doc(uid), ownerMember.toMap());
    batch.set(_userGroupRef(uid, groupRef.id), {
      "role": "owner",
      "status": "active",
      "joinedAt": Timestamp.fromDate(now),
      "groupName": group.name,
    });
    await batch.commit();
    return groupRef.id;
  }

  /// Delete a group (owner only). Removes members + posts in a best-effort
  /// cleanup; for very large groups a Cloud Function would be preferable.
  Future<void> deleteGroup(String groupId) async {
    final uid = _requireUid();
    final groupSnap = await _groupRef(groupId).get();
    if (!groupSnap.exists) return;
    final group = PilotGroup.fromDoc(groupSnap);
    if (group.ownerUid != uid) {
      throw StateError("Only the owner can delete this group");
    }

    final members = await _membersCol(groupId).get();
    final posts = await _postsCol(groupId).get();

    final batch = _db.batch();
    for (final m in members.docs) {
      batch.delete(m.reference);
      batch.delete(_userGroupRef(m.id, groupId));
    }
    for (final p in posts.docs) {
      batch.delete(p.reference);
    }
    batch.delete(_groupRef(groupId));
    await batch.commit();
  }

  // -------------------- Membership --------------------

  Stream<GroupMember?> watchMyMembership(String groupId) {
    final uid = _uid;
    if (uid == null) return Stream.value(null);
    return _membersCol(groupId)
        .doc(uid)
        .snapshots()
        .map((s) => s.exists ? GroupMember.fromDoc(s) : null);
  }

  Stream<List<GroupMember>> watchMembers(String groupId,
      {MemberStatus? status}) {
    Query<Map<String, dynamic>> q = _membersCol(groupId);
    if (status != null) {
      q = q.where("status",
          isEqualTo: status == MemberStatus.pending ? "pending" : "active");
    }
    return q.snapshots().map((s) {
      final list = s.docs.map(GroupMember.fromDoc).toList();
      list.sort((a, b) {
        if (a.isOwner && !b.isOwner) return -1;
        if (b.isOwner && !a.isOwner) return 1;
        return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      });
      return list;
    });
  }

  /// Join a group. Public groups go straight to active; private groups
  /// land in `pending` until the owner approves.
  Future<MemberStatus> joinGroup(String groupId) async {
    final uid = _requireUid();
    final profile = await ensureMyProfile();
    final groupSnap = await _groupRef(groupId).get();
    if (!groupSnap.exists) {
      throw StateError("Group not found");
    }
    final group = PilotGroup.fromDoc(groupSnap);
    final status =
        group.isPrivate ? MemberStatus.pending : MemberStatus.active;

    final now = DateTime.now();
    final member = GroupMember(
      uid: uid,
      displayName: profile.displayName,
      homeAirport: profile.homeAirport,
      role: MemberRole.member,
      status: status,
      joinedAt: now,
    );

    final batch = _db.batch();
    batch.set(_membersCol(groupId).doc(uid), member.toMap());
    batch.set(_userGroupRef(uid, groupId), {
      "role": "member",
      "status": status == MemberStatus.active ? "active" : "pending",
      "joinedAt": Timestamp.fromDate(now),
      "groupName": group.name,
    });
    if (status == MemberStatus.active) {
      batch.update(_groupRef(groupId), {
        "memberCount": FieldValue.increment(1),
      });
    }
    await batch.commit();
    return status;
  }

  /// Leave a group. Owners cannot leave; they must delete the group instead.
  Future<void> leaveGroup(String groupId) async {
    final uid = _requireUid();
    final memberSnap = await _membersCol(groupId).doc(uid).get();
    if (!memberSnap.exists) return;
    final member = GroupMember.fromDoc(memberSnap);
    if (member.isOwner) {
      throw StateError(
          "Owners cannot leave. Delete the group or transfer ownership.");
    }

    final batch = _db.batch();
    batch.delete(_membersCol(groupId).doc(uid));
    batch.delete(_userGroupRef(uid, groupId));
    if (member.isActive) {
      batch.update(_groupRef(groupId), {
        "memberCount": FieldValue.increment(-1),
      });
    }
    await batch.commit();
  }

  /// Owner approves a pending join request on a private group.
  Future<void> approveMember(String groupId, String memberUid) async {
    final uid = _requireUid();
    await _assertOwner(groupId, uid);
    final batch = _db.batch();
    batch.update(_membersCol(groupId).doc(memberUid), {"status": "active"});
    batch.update(_userGroupRef(memberUid, groupId), {"status": "active"});
    batch.update(_groupRef(groupId), {
      "memberCount": FieldValue.increment(1),
    });
    await batch.commit();
  }

  /// Owner removes a member (or rejects a pending request).
  Future<void> removeMember(String groupId, String memberUid) async {
    final uid = _requireUid();
    await _assertOwner(groupId, uid);
    final memberSnap = await _membersCol(groupId).doc(memberUid).get();
    if (!memberSnap.exists) return;
    final member = GroupMember.fromDoc(memberSnap);
    if (member.isOwner) {
      throw StateError("Cannot remove the owner");
    }
    final batch = _db.batch();
    batch.delete(_membersCol(groupId).doc(memberUid));
    batch.delete(_userGroupRef(memberUid, groupId));
    if (member.isActive) {
      batch.update(_groupRef(groupId), {
        "memberCount": FieldValue.increment(-1),
      });
    }
    await batch.commit();
  }

  Future<void> _assertOwner(String groupId, String uid) async {
    final snap = await _groupRef(groupId).get();
    if (!snap.exists) throw StateError("Group not found");
    final g = PilotGroup.fromDoc(snap);
    if (g.ownerUid != uid) {
      throw StateError("Only the owner can do that");
    }
  }

  // -------------------- Posts --------------------

  Stream<List<GroupPost>> watchPosts(String groupId, {int limit = 100}) {
    return _postsCol(groupId)
        .orderBy("createdAt", descending: true)
        .limit(limit)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => GroupPost.fromDoc(groupId, d)).toList(growable: false));
  }

  Future<void> createPost(
    String groupId, {
    required String text,
    String? attachedAirport,
  }) async {
    final uid = _requireUid();
    final profile = await ensureMyProfile();
    final memberSnap = await _membersCol(groupId).doc(uid).get();
    if (!memberSnap.exists) {
      throw StateError("Join the group before posting");
    }
    final member = GroupMember.fromDoc(memberSnap);
    if (!member.isActive) {
      throw StateError("Membership pending owner approval");
    }
    final postRef = _postsCol(groupId).doc();
    final post = GroupPost(
      id: postRef.id,
      groupId: groupId,
      authorUid: uid,
      authorName: profile.displayName,
      text: text.trim(),
      attachedAirport: attachedAirport?.trim().toUpperCase(),
      createdAt: DateTime.now(),
    );

    final batch = _db.batch();
    batch.set(postRef, post.toCreateMap());
    batch.update(_groupRef(groupId), {
      "postCount": FieldValue.increment(1),
    });
    await batch.commit();
  }

  /// Delete a post. Authors can delete their own; owners can delete any.
  Future<void> deletePost(String groupId, String postId) async {
    final uid = _requireUid();
    final postSnap = await _postsCol(groupId).doc(postId).get();
    if (!postSnap.exists) return;
    final post = GroupPost.fromDoc(groupId, postSnap);
    if (post.authorUid != uid) {
      await _assertOwner(groupId, uid);
    }
    final batch = _db.batch();
    batch.delete(_postsCol(groupId).doc(postId));
    batch.update(_groupRef(groupId), {
      "postCount": FieldValue.increment(-1),
    });
    await batch.commit();
  }
}
