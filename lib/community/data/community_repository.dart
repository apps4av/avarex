import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/community_notification.dart';
import '../models/group_member.dart';
import '../models/group_post.dart';
import '../models/notification_prefs.dart';
import '../models/pilot_group.dart';
import '../models/pilot_profile.dart';

/// All Firestore interaction for the Community feature is funneled through
/// this repository so the rest of the UI never touches Firestore directly.
///
/// Collection layout:
///   users/{uid}                                  -> PilotProfile
///   usernames/{displayNameLower}                 -> { uid } (name uniqueness)
///   groups/{gid}                                 -> PilotGroup
///   groups/{gid}/members/{uid}                   -> GroupMember
///   groups/{gid}/posts/{pid}                     -> GroupPost
///   userGroups/{uid}/groups/{gid}                -> denormalized membership index
///   userNotifications/{uid}/items/{nid}          -> CommunityNotification
///   userNotificationPrefs/{uid}                  -> NotificationPrefs
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

  DocumentReference<Map<String, dynamic>> _usernameRef(String nameLower) =>
      _db.collection("usernames").doc(nameLower);

  Future<PilotProfile> ensureMyProfile() async {
    final uid = _requireUid();
    final ref = _profileRef(uid);
    final snap = await ref.get();
    if (snap.exists) {
      return PilotProfile.fromDoc(snap);
    }
    // Pick a globally-unique display name (the security rules require the
    // caller to own the matching usernames/{lower} claim before the profile
    // can be written). Start from the auth name/email, appending a short uid
    // suffix if it's taken.
    final base = FirebaseAuth.instance.currentUser?.displayName ??
        FirebaseAuth.instance.currentUser?.email?.split("@").first ??
        "Pilot";
    final displayName = await _pickFreeName(uid, base);
    final initial = PilotProfile.empty(uid, displayName);
    // Issue the profile create but don't block on the server ack, so first use
    // works offline too: the write is applied to the local cache immediately
    // and syncs later (rules are re-checked on sync). ensureMyProfile runs
    // before every contribution, so blocking here would hang those writes.
    unawaited(ref.set(initial.toMap()).catchError((_) => null));
    return initial;
  }

  /// Normalize a candidate display name to the 2-40 char window the rules
  /// require, and to something usable as the usernames claim document id
  /// (the lowercased name is the doc id, so '/', '.' and '..' are illegal).
  String _sanitizeDisplayName(String name) {
    var n = name.replaceAll("/", "-").trim();
    if (n.length > 40) n = n.substring(0, 40).trim();
    if (n.length < 2 || n == "." || n == "..") n = "Pilot";
    return n;
  }

  /// Pick a globally-unique display name for a brand-new profile and stake the
  /// matching usernames claim. Derives from [base], falling back to
  /// uid-suffixed variants when a candidate is taken. The claim write is
  /// issued but not awaited (so this works offline); the rules enforce real
  /// uniqueness when the write syncs.
  Future<String> _pickFreeName(String uid, String base) async {
    final root = _sanitizeDisplayName(base);
    final candidates = <String>[
      root,
      _sanitizeDisplayName("$root-${uid.substring(0, 4)}"),
      _sanitizeDisplayName("$root-${uid.substring(0, 6)}"),
      _sanitizeDisplayName("Pilot-${uid.substring(0, 6)}"),
      _sanitizeDisplayName("Pilot-$uid"), // uid is unique, so this always frees
    ];
    for (final candidate in candidates) {
      final lower = candidate.toLowerCase();
      final snap = await _usernameRef(lower).get();
      if (!snap.exists) {
        unawaited(
            _usernameRef(lower).set({"uid": uid}).catchError((_) => null));
        return candidate;
      }
      if (snap.data()?["uid"] == uid) return candidate; // already mine
    }
    return candidates.last;
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
    // Canonicalize the name so the claim id is a valid doc id and matches the
    // stored displayNameLower exactly (the rules bind the two).
    final toSave = profile.copyWith(
        displayName: _sanitizeDisplayName(profile.displayName));
    final newLower = toSave.displayName.toLowerCase();

    // Determine the previous name so we can release its claim on a rename.
    final currentSnap = await _profileRef(uid).get();
    final data = currentSnap.data();
    final oldLower = (data?["displayNameLower"] as String?) ??
        (data?["displayName"] as String?)?.toLowerCase();

    // Reject a name already held by another pilot (server truth when online;
    // offline this uses the cache and is re-checked by the rules on sync).
    final claimSnap = await _usernameRef(newLower).get();
    if (claimSnap.exists && claimSnap.data()?["uid"] != uid) {
      throw StateError("That display name is taken. Please choose another.");
    }

    // Issue the writes in order (claim before profile) so they apply to the
    // local cache at once and, when offline, queue in the order the rules
    // need: the profile's ownsUsername check must see the claim first on sync.
    // We don't await between them; the caller wraps the whole call in
    // commitWithOfflineFallback to decide synced vs queued.
    final claimWrite = claimSnap.exists
        ? Future<void>.value()
        : _usernameRef(newLower).set({"uid": uid});
    final profileWrite =
        _profileRef(uid).set(toSave.toMap(), SetOptions(merge: true));
    final rename = Future.wait([claimWrite, profileWrite]);

    // Release the previous name's claim ONLY once the rename actually commits.
    // Doing it unconditionally would be unsafe offline: if the new name is
    // taken by the time our queued writes sync, the profile write rolls back
    // (rules), and deleting the old claim anyway would strand us with a
    // profile name we no longer own -- reopening the impersonation gap.
    if (oldLower != null && oldLower != newLower) {
      unawaited(rename
          .then((_) => _usernameRef(oldLower).delete())
          .catchError((_) {}));
    }

    await rename;
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

  CollectionReference<Map<String, dynamic>> _notifsCol(String uid) =>
      _db.collection("userNotifications").doc(uid).collection("items");

  DocumentReference<Map<String, dynamic>> _notifPrefsRef(String uid) =>
      _db.collection("userNotificationPrefs").doc(uid);

  DocumentReference<Map<String, dynamic>> _groupReadRef(String uid, String gid) =>
      _db.collection("userGroupReads").doc(uid).collection("groups").doc(gid);

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

    // Best-effort media cleanup runs FIRST, while the group doc still
    // exists: the Storage rules authorize the owner to delete other
    // members' photos via isCommunityOwner(groupId), which needs the group
    // doc to be present. Failures here only leak Storage objects.
    for (final p in posts.docs) {
      final post = GroupPost.fromDoc(groupId, p);
      await _deletePostMedia(groupId, post.authorUid, p.id);
    }

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

  /// One-shot read of the current user's membership, used when opening a
  /// thread from a notification (where the streamed membership context
  /// isn't already on hand).
  Future<GroupMember?> fetchMyMembership(String groupId) async {
    final uid = _uid;
    if (uid == null) return null;
    final snap = await _membersCol(groupId).doc(uid).get();
    return snap.exists ? GroupMember.fromDoc(snap) : null;
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

  /// Top-level topics for a group's feed, newest first.
  ///
  /// Replies are filtered out client-side (rather than with a server
  /// `where("replyToId", isEqualTo: null)`) so that legacy posts written
  /// before threading existed -- which have no `replyToId` field at all --
  /// still show up as topics. A server null-equality filter would silently
  /// drop those documents.
  Stream<List<GroupPost>> watchPosts(String groupId, {int limit = 100}) {
    return _postsCol(groupId)
        .orderBy("createdAt", descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs
            .map((d) => GroupPost.fromDoc(groupId, d))
            .where((p) => !p.isReply)
            .toList(growable: false));
  }

  /// Replies to a single topic, oldest first so a thread reads top to
  /// bottom like a conversation.
  ///
  /// Deliberately an equality-only query (no server-side `orderBy`): an
  /// equality filter plus an `orderBy` on a different field would require a
  /// deployed composite index, and without it the stream errors and the
  /// thread appears empty even though the topic's replyCount is non-zero.
  /// Relying only on the automatic single-field index on `replyToId` keeps
  /// replies working with no index deployment; they're sorted client-side.
  Stream<List<GroupPost>> watchReplies(String groupId, String topicId,
      {int limit = 200}) {
    return _postsCol(groupId)
        .where("replyToId", isEqualTo: topicId)
        .limit(limit)
        .snapshots()
        .map((s) {
      final list =
          s.docs.map((d) => GroupPost.fromDoc(groupId, d)).toList();
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return list;
    });
  }

  /// Live view of a single post (used by the thread screen to keep the
  /// topic header -- including its reply count -- up to date).
  Stream<GroupPost?> watchPost(String groupId, String postId) {
    return _postsCol(groupId).doc(postId).snapshots().map(
        (s) => s.exists ? GroupPost.fromDoc(groupId, s) : null);
  }

  /// Create a post. When [replyToId] is supplied the post is a reply to
  /// that topic: it is tagged with the parent id and the parent's
  /// [GroupPost.replyCount] is bumped in the same batch. Replies do not
  /// affect the group's `postCount` (only topics do), which keeps the
  /// group counter changes to ±1 per call.
  Future<void> createPost(
    String groupId, {
    required String text,
    String? attachedAirport,
    String? attachedRouteText,
    String? attachedRouteName,
    List<Uint8List> images = const [],
    String? replyToId,
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
    if (images.length > GroupPost.maxImages) {
      throw StateError(
          "At most ${GroupPost.maxImages} images per post");
    }
    final routeText = attachedRouteText?.trim();
    if (routeText != null && routeText.length > GroupPost.maxRouteLength) {
      throw StateError("Attached plan is too long to share");
    }

    final parentId = (replyToId != null && replyToId.trim().isNotEmpty)
        ? replyToId.trim()
        : null;
    // Replies attach to a top-level topic only. If the supplied parent is
    // itself a reply, re-target its parent so the thread stays one level
    // deep and the reply counter lives on the topic.
    String? topicId = parentId;
    if (parentId != null) {
      final parentSnap = await _postsCol(groupId).doc(parentId).get();
      if (!parentSnap.exists) {
        throw StateError("The topic you're replying to no longer exists");
      }
      final parent = GroupPost.fromDoc(groupId, parentSnap);
      topicId = parent.isReply ? parent.replyToId : parent.id;
    }

    final postRef = _postsCol(groupId).doc();

    // Upload images first so the post doc is only created with finalized
    // download URLs. Path layout matches storage.rules:
    //   community/{groupId}/{uid}/{postId}/{index}.jpg
    // The uid segment binds each object to its uploader so Storage rules
    // can authorize writes/deletes without reading the post doc.
    final mediaUrls = <String>[];
    for (var i = 0; i < images.length; i++) {
      final imgRef = FirebaseStorage.instance
          .ref()
          .child('community')
          .child(groupId)
          .child(uid)
          .child(postRef.id)
          .child('$i.jpg');
      await imgRef.putData(
        images[i],
        SettableMetadata(contentType: 'image/jpeg'),
      );
      mediaUrls.add(await imgRef.getDownloadURL());
    }

    final post = GroupPost(
      id: postRef.id,
      groupId: groupId,
      authorUid: uid,
      authorName: profile.displayName,
      text: text.trim(),
      attachedAirport: attachedAirport?.trim().toUpperCase(),
      attachedRouteText:
          (routeText == null || routeText.isEmpty) ? null : routeText,
      attachedRouteName:
          attachedRouteName?.trim().isEmpty ?? true ? null : attachedRouteName!.trim(),
      mediaUrls: mediaUrls,
      replyToId: topicId,
      replyCount: 0,
      createdAt: DateTime.now(),
    );

    final batch = _db.batch();
    batch.set(postRef, post.toCreateMap());
    if (topicId == null) {
      // A new topic counts toward the group's post total.
      batch.update(_groupRef(groupId), {
        "postCount": FieldValue.increment(1),
      });
    } else {
      // A reply bumps its topic's reply counter instead.
      batch.update(_postsCol(groupId).doc(topicId), {
        "replyCount": FieldValue.increment(1),
      });
    }
    await batch.commit();

    // Fan out reply notifications after the reply is durably committed.
    // Done separately (and best-effort) so a notification rule rejection
    // can never roll back the reply itself.
    if (topicId != null) {
      final snippet = text.trim().isNotEmpty
          ? text.trim()
          : (mediaUrls.isNotEmpty ? "[Photo]" : "Replied");
      await _notifyReply(
        groupId: groupId,
        topicId: topicId,
        replyId: postRef.id,
        actorUid: uid,
        actorName: profile.displayName,
        snippet: snippet,
      );
    }
  }

  /// Write reply notifications to the topic's author and the group owner
  /// (excluding the replier, and de-duplicated when they're the same
  /// person). Best-effort: any failure here is swallowed so it never
  /// affects the reply that already committed.
  Future<void> _notifyReply({
    required String groupId,
    required String topicId,
    required String replyId,
    required String actorUid,
    required String actorName,
    required String snippet,
  }) async {
    try {
      final groupSnap = await _groupRef(groupId).get();
      if (!groupSnap.exists) return;
      final group = PilotGroup.fromDoc(groupSnap);
      final topicSnap = await _postsCol(groupId).doc(topicId).get();
      if (!topicSnap.exists) return;
      final topic = GroupPost.fromDoc(groupId, topicSnap);

      // uid -> reason. Topic author wins over group owner when both apply.
      final recipients = <String, String>{};
      if (topic.authorUid.isNotEmpty && topic.authorUid != actorUid) {
        recipients[topic.authorUid] = CommunityNotification.reasonTopicAuthor;
      }
      if (group.ownerUid.isNotEmpty &&
          group.ownerUid != actorUid &&
          !recipients.containsKey(group.ownerUid)) {
        recipients[group.ownerUid] = CommunityNotification.reasonGroupOwner;
      }
      if (recipients.isEmpty) return;

      final trimmed = snippet.length > CommunityNotification.maxSnippet
          ? snippet.substring(0, CommunityNotification.maxSnippet)
          : snippet;
      final now = DateTime.now();

      final batch = _db.batch();
      recipients.forEach((recipientUid, reason) {
        final ref = _notifsCol(recipientUid).doc();
        final notif = CommunityNotification(
          id: ref.id,
          type: CommunityNotification.typeReply,
          groupId: groupId,
          groupName: group.name,
          topicId: topicId,
          postId: replyId,
          actorUid: actorUid,
          actorName: actorName,
          reason: reason,
          snippet: trimmed,
          read: false,
          createdAt: now,
        );
        batch.set(ref, notif.toCreateMap());
      });
      await batch.commit();
    } catch (_) {
      // Notifications are best-effort; ignore rule/network failures.
    }
  }

  /// Delete a post. Authors can delete their own; owners can delete any.
  ///
  /// Deleting a topic cascades to its replies so a thread never outlives
  /// the conversation it belonged to; only the topic decrements the
  /// group's `postCount`. Deleting a reply decrements its topic's
  /// `replyCount` instead.
  ///
  /// Any attached images are removed from Firebase Storage on a
  /// best-effort basis; an orphaned image is harmless and gets cleaned
  /// up by lifecycle rules if configured.
  Future<void> deletePost(String groupId, String postId) async {
    final uid = _requireUid();
    final postSnap = await _postsCol(groupId).doc(postId).get();
    if (!postSnap.exists) return;
    final post = GroupPost.fromDoc(groupId, postSnap);
    if (post.authorUid != uid) {
      await _assertOwner(groupId, uid);
    }

    if (post.isReply) {
      // A reply: drop the doc and decrement its topic's reply counter.
      final batch = _db.batch();
      batch.delete(_postsCol(groupId).doc(postId));
      batch.update(_postsCol(groupId).doc(post.replyToId!), {
        "replyCount": FieldValue.increment(-1),
      });
      await batch.commit();
      await _deletePostMedia(groupId, post.authorUid, postId);
      return;
    }

    // A topic: cascade-delete every reply, then the topic itself. Only the
    // topic touches the group's postCount (replies never did).
    final replies =
        await _postsCol(groupId).where("replyToId", isEqualTo: postId).get();

    final batch = _db.batch();
    for (final r in replies.docs) {
      batch.delete(r.reference);
    }
    batch.delete(_postsCol(groupId).doc(postId));
    batch.update(_groupRef(groupId), {
      "postCount": FieldValue.increment(-1),
    });
    await batch.commit();

    // Best-effort Storage cleanup for the topic and all its replies.
    await _deletePostMedia(groupId, post.authorUid, postId);
    for (final r in replies.docs) {
      final reply = GroupPost.fromDoc(groupId, r);
      await _deletePostMedia(groupId, reply.authorUid, r.id);
    }
  }

  Future<void> _deletePostMedia(
      String groupId, String authorUid, String postId) async {
    try {
      final folderRef = FirebaseStorage.instance
          .ref()
          .child('community')
          .child(groupId)
          .child(authorUid)
          .child(postId);
      final list = await folderRef.listAll();
      await Future.wait(list.items.map((i) => i.delete()));
    } catch (_) {
      // Ignore — Storage cleanup is best effort.
    }
  }

  // -------------------- Read tracking --------------------

  /// The last time the current user marked a group's feed as read. Topics
  /// created after this are considered unread (shown bold in the feed).
  /// Returns null when the user has never opened the group.
  Future<DateTime?> fetchGroupLastRead(String groupId) async {
    final uid = _uid;
    if (uid == null) return null;
    final snap = await _groupReadRef(uid, groupId).get();
    if (!snap.exists) return null;
    final ts = snap.data()?["lastReadAt"];
    return ts is Timestamp ? ts.toDate() : null;
  }

  /// Mark a group's feed as read up to now.
  Future<void> markGroupRead(String groupId) async {
    final uid = _uid;
    if (uid == null) return;
    await _groupReadRef(uid, groupId)
        .set({"lastReadAt": Timestamp.fromDate(DateTime.now())});
  }

  // -------------------- Notifications --------------------

  /// The current user's notifications, newest first. Preferences are
  /// applied by the caller on read (see [NotificationPrefs]).
  Stream<List<CommunityNotification>> watchMyNotifications({int limit = 50}) {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _notifsCol(uid)
        .orderBy("createdAt", descending: true)
        .limit(limit)
        .snapshots()
        .map((s) => s.docs
            .map(CommunityNotification.fromDoc)
            .toList(growable: false));
  }

  Stream<NotificationPrefs> watchMyNotificationPrefs() {
    final uid = _uid;
    if (uid == null) return Stream.value(NotificationPrefs.defaults);
    return _notifPrefsRef(uid).snapshots().map(
        (s) => s.exists ? NotificationPrefs.fromDoc(s) : NotificationPrefs.defaults);
  }

  Future<void> saveMyNotificationPrefs(NotificationPrefs prefs) async {
    final uid = _requireUid();
    await _notifPrefsRef(uid).set(prefs.toMap());
  }

  Future<void> markNotificationRead(String notificationId) async {
    final uid = _requireUid();
    await _notifsCol(uid).doc(notificationId).update({"read": true});
  }

  /// Mark every currently-unread notification as read.
  Future<void> markAllNotificationsRead() async {
    final uid = _requireUid();
    final unread =
        await _notifsCol(uid).where("read", isEqualTo: false).get();
    if (unread.docs.isEmpty) return;
    final batch = _db.batch();
    for (final d in unread.docs) {
      batch.update(d.reference, {"read": true});
    }
    await batch.commit();
  }

  Future<void> deleteNotification(String notificationId) async {
    final uid = _requireUid();
    await _notifsCol(uid).doc(notificationId).delete();
  }

  /// Remove all of the current user's notifications.
  Future<void> clearAllNotifications() async {
    final uid = _requireUid();
    final all = await _notifsCol(uid).get();
    if (all.docs.isEmpty) return;
    final batch = _db.batch();
    for (final d in all.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }
}
