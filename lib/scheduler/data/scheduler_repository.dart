import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../community/data/community_repository.dart';
import '../models/lesson_pack.dart';
import '../models/reservation.dart';
import '../models/schedulable_resource.dart';
import '../models/scheduler_group.dart';
import '../models/scheduler_member.dart';
import '../models/squawk.dart';

/// Outcome of a booking attempt so the UI can tell the member whether they
/// got the slot outright or were queued as a backup.
class BookingResult {
  final bool isBackup;
  final int backupOrder;
  const BookingResult({required this.isBackup, required this.backupOrder});
}

/// All Firestore interaction for the Aircraft Scheduler feature is funneled
/// through this repository so the UI never touches Firestore directly.
///
/// Collection layout (mirrors the Community feature):
///   schedulerGroups/{sgid}                          -> SchedulerGroup
///   schedulerGroups/{sgid}/members/{uid}            -> SchedulerMember
///   schedulerGroups/{sgid}/resources/{rid}          -> SchedulableResource
///   schedulerGroups/{sgid}/reservations/{resvId}    -> Reservation
///   schedulerGroups/{sgid}/squawks/{sid}            -> Squawk
///   schedulerGroups/{sgid}/lessonPacks/{pid}        -> LessonPack
///   userSchedulerGroups/{uid}/groups/{sgid}         -> denormalized index
class SchedulerRepository {
  SchedulerRepository._();
  static final SchedulerRepository instance = SchedulerRepository._();

  /// Upper bound on a single reservation's length. This also bounds the
  /// "look-back" window for day/overlap queries: any reservation overlapping
  /// a given day must have started within [maxBookingDays] before it, which
  /// lets us keep a single-field range query on `start` (no second range
  /// field) while still catching multi-day reservations that began earlier.
  static const int maxBookingDays = 14;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  String _requireUid() {
    final uid = _uid;
    if (uid == null) {
      throw StateError("Not signed in");
    }
    return uid;
  }

  // Reuse the Community profile so display names are consistent across the
  // app's Pro features.
  Future<String> _myDisplayName() async {
    final profile = await CommunityRepository.instance.ensureMyProfile();
    return profile.displayName;
  }

  // -------------------- Collection refs --------------------

  CollectionReference<Map<String, dynamic>> get _groupsCol =>
      _db.collection("schedulerGroups");

  DocumentReference<Map<String, dynamic>> _groupRef(String sgid) =>
      _groupsCol.doc(sgid);

  CollectionReference<Map<String, dynamic>> _membersCol(String sgid) =>
      _groupRef(sgid).collection("members");

  CollectionReference<Map<String, dynamic>> _resourcesCol(String sgid) =>
      _groupRef(sgid).collection("resources");

  CollectionReference<Map<String, dynamic>> _reservationsCol(String sgid) =>
      _groupRef(sgid).collection("reservations");

  CollectionReference<Map<String, dynamic>> _squawksCol(String sgid) =>
      _groupRef(sgid).collection("squawks");

  CollectionReference<Map<String, dynamic>> _lessonPacksCol(String sgid) =>
      _groupRef(sgid).collection("lessonPacks");

  DocumentReference<Map<String, dynamic>> _userGroupRef(
          String uid, String sgid) =>
      _db
          .collection("userSchedulerGroups")
          .doc(uid)
          .collection("groups")
          .doc(sgid);

  // -------------------- Groups --------------------

  Stream<SchedulerGroup?> watchGroup(String sgid) {
    return _groupRef(sgid)
        .snapshots()
        .map((s) => s.exists ? SchedulerGroup.fromDoc(s) : null);
  }

  /// Discover tab. All schedulers are private, so there is no public browse
  /// list — members find a scheduler by searching its name and then request
  /// to join. An empty query returns nothing.
  Stream<List<SchedulerGroup>> discoverGroups({String? query, int limit = 50}) {
    final trimmed = query?.trim() ?? "";
    if (trimmed.isEmpty) {
      return Stream.value(const []);
    }
    final lower = trimmed.toLowerCase();
    return _groupsCol
        .where("nameLower", isGreaterThanOrEqualTo: lower)
        .where("nameLower", isLessThan: "$lower\uf8ff")
        .orderBy("nameLower")
        .limit(limit)
        .snapshots()
        .map((s) =>
            s.docs.map(SchedulerGroup.fromDoc).toList(growable: false));
  }

  /// Scheduler groups the current user belongs to.
  Stream<List<SchedulerGroup>> watchMyGroups() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _db
        .collection("userSchedulerGroups")
        .doc(uid)
        .collection("groups")
        .where("status", isEqualTo: "active")
        .snapshots()
        .asyncMap((snap) async {
      if (snap.docs.isEmpty) return <SchedulerGroup>[];
      final ids = snap.docs.map((d) => d.id).toList();
      final List<SchedulerGroup> groups = [];
      for (var i = 0; i < ids.length; i += 30) {
        final chunk =
            ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
        final qs = await _groupsCol
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        groups.addAll(qs.docs.map(SchedulerGroup.fromDoc));
      }
      groups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return groups;
    });
  }

  /// Create a new scheduler group; current user becomes the owner.
  ///
  /// All schedulers are **private** — discoverable by name, but the owner
  /// approves every member.
  Future<String> createGroup({
    required String name,
    required String description,
    String? homeAirport,
  }) async {
    final uid = _requireUid();
    final displayName = await _myDisplayName();

    final groupRef = _groupsCol.doc();
    final now = DateTime.now();
    final group = SchedulerGroup(
      id: groupRef.id,
      name: name.trim(),
      description: description.trim(),
      homeAirport: homeAirport?.trim().toUpperCase(),
      visibility: SchedulerVisibility.private,
      ownerUid: uid,
      ownerName: displayName,
      memberCount: 1,
      resourceCount: 0,
      maxReservationsPerMember: 0,
      maxWeekendReservations: 0,
      createdAt: now,
    );

    final ownerMember = SchedulerMember(
      uid: uid,
      displayName: displayName,
      role: SchedulerRole.owner,
      status: SchedulerMemberStatus.active,
      clubRole: ClubRole.dispatcher,
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

  /// Delete a group (owner only) along with its members, resources and
  /// reservations.
  Future<void> deleteGroup(String sgid) async {
    final uid = _requireUid();
    final groupSnap = await _groupRef(sgid).get();
    if (!groupSnap.exists) return;
    final group = SchedulerGroup.fromDoc(groupSnap);
    if (group.ownerUid != uid) {
      throw StateError("Only the owner can delete this scheduler");
    }

    final members = await _membersCol(sgid).get();
    final resources = await _resourcesCol(sgid).get();
    final reservations = await _reservationsCol(sgid).get();
    final squawks = await _squawksCol(sgid).get();
    final packs = await _lessonPacksCol(sgid).get();

    final batch = _db.batch();
    for (final m in members.docs) {
      batch.delete(m.reference);
      batch.delete(_userGroupRef(m.id, sgid));
    }
    for (final r in resources.docs) {
      batch.delete(r.reference);
    }
    for (final r in reservations.docs) {
      batch.delete(r.reference);
    }
    for (final s in squawks.docs) {
      batch.delete(s.reference);
    }
    for (final p in packs.docs) {
      batch.delete(p.reference);
    }
    batch.delete(_groupRef(sgid));
    await batch.commit();
  }

  /// Owner sets the booking rules for the scheduler. A value of 0 means
  /// "unlimited".
  Future<void> updateBookingRules(
    String sgid, {
    required int maxReservationsPerMember,
    required int maxWeekendReservations,
  }) async {
    final uid = _requireUid();
    await _assertOwner(sgid, uid);
    await _groupRef(sgid).update({
      "maxReservationsPerMember":
          maxReservationsPerMember < 0 ? 0 : maxReservationsPerMember,
      "maxWeekendReservations":
          maxWeekendReservations < 0 ? 0 : maxWeekendReservations,
    });
  }

  // -------------------- Membership --------------------

  Stream<SchedulerMember?> watchMyMembership(String sgid) {
    final uid = _uid;
    if (uid == null) return Stream.value(null);
    return _membersCol(sgid)
        .doc(uid)
        .snapshots()
        .map((s) => s.exists ? SchedulerMember.fromDoc(s) : null);
  }

  Stream<List<SchedulerMember>> watchMembers(String sgid,
      {SchedulerMemberStatus? status}) {
    Query<Map<String, dynamic>> q = _membersCol(sgid);
    if (status != null) {
      q = q.where("status",
          isEqualTo:
              status == SchedulerMemberStatus.pending ? "pending" : "active");
    }
    return q.snapshots().map((s) {
      final list = s.docs.map(SchedulerMember.fromDoc).toList();
      list.sort((a, b) {
        if (a.isOwner && !b.isOwner) return -1;
        if (b.isOwner && !a.isOwner) return 1;
        return a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase());
      });
      return list;
    });
  }

  /// Join a group. Public groups go straight to active; private groups land
  /// in `pending` until the owner approves.
  Future<SchedulerMemberStatus> joinGroup(String sgid) async {
    final uid = _requireUid();
    final displayName = await _myDisplayName();
    final groupSnap = await _groupRef(sgid).get();
    if (!groupSnap.exists) {
      throw StateError("Scheduler not found");
    }
    final group = SchedulerGroup.fromDoc(groupSnap);
    final status = group.isPrivate
        ? SchedulerMemberStatus.pending
        : SchedulerMemberStatus.active;

    final now = DateTime.now();
    final member = SchedulerMember(
      uid: uid,
      displayName: displayName,
      role: SchedulerRole.member,
      status: status,
      joinedAt: now,
    );

    final batch = _db.batch();
    batch.set(_membersCol(sgid).doc(uid), member.toMap());
    batch.set(_userGroupRef(uid, sgid), {
      "role": "member",
      "status": status == SchedulerMemberStatus.active ? "active" : "pending",
      "joinedAt": Timestamp.fromDate(now),
      "groupName": group.name,
    });
    if (status == SchedulerMemberStatus.active) {
      batch.update(_groupRef(sgid), {
        "memberCount": FieldValue.increment(1),
      });
    }
    await batch.commit();
    return status;
  }

  /// Leave a group. Owners cannot leave; they must delete the group instead.
  Future<void> leaveGroup(String sgid) async {
    final uid = _requireUid();
    final memberSnap = await _membersCol(sgid).doc(uid).get();
    if (!memberSnap.exists) return;
    final member = SchedulerMember.fromDoc(memberSnap);
    if (member.isOwner) {
      throw StateError("Owners cannot leave. Delete the scheduler instead.");
    }

    final batch = _db.batch();
    batch.delete(_membersCol(sgid).doc(uid));
    batch.delete(_userGroupRef(uid, sgid));
    if (member.isActive) {
      batch.update(_groupRef(sgid), {
        "memberCount": FieldValue.increment(-1),
      });
    }
    await batch.commit();
  }

  /// Owner approves a pending join request on a private group.
  Future<void> approveMember(String sgid, String memberUid) async {
    final uid = _requireUid();
    await _assertOwner(sgid, uid);
    final batch = _db.batch();
    batch.update(_membersCol(sgid).doc(memberUid), {"status": "active"});
    batch.update(_userGroupRef(memberUid, sgid), {"status": "active"});
    batch.update(_groupRef(sgid), {
      "memberCount": FieldValue.increment(1),
    });
    await batch.commit();
  }

  /// Owner removes a member (or rejects a pending request).
  Future<void> removeMember(String sgid, String memberUid) async {
    final uid = _requireUid();
    await _assertOwner(sgid, uid);
    final memberSnap = await _membersCol(sgid).doc(memberUid).get();
    if (!memberSnap.exists) return;
    final member = SchedulerMember.fromDoc(memberSnap);
    if (member.isOwner) {
      throw StateError("Cannot remove the owner");
    }
    final batch = _db.batch();
    batch.delete(_membersCol(sgid).doc(memberUid));
    batch.delete(_userGroupRef(memberUid, sgid));
    if (member.isActive) {
      batch.update(_groupRef(sgid), {
        "memberCount": FieldValue.increment(-1),
      });
    }
    await batch.commit();
  }

  /// Owner sets a member's club role and optional student→instructor link.
  Future<void> updateMemberClubRole(
    String sgid,
    String memberUid, {
    required ClubRole clubRole,
    String? assignedInstructorUid,
    String? assignedInstructorName,
  }) async {
    final uid = _requireUid();
    await _assertOwner(sgid, uid);
    final memberSnap = await _membersCol(sgid).doc(memberUid).get();
    if (!memberSnap.exists) {
      throw StateError("Member not found");
    }

    String? instructorUid = assignedInstructorUid;
    String? instructorName = assignedInstructorName;
    if (clubRole != ClubRole.student) {
      instructorUid = null;
      instructorName = null;
    } else if (instructorUid != null && instructorUid.isNotEmpty) {
      final iSnap = await _membersCol(sgid).doc(instructorUid).get();
      if (!iSnap.exists) {
        throw StateError("Assigned instructor is not a member");
      }
      final instructor = SchedulerMember.fromDoc(iSnap);
      instructorName = instructor.displayName;
    } else {
      instructorUid = null;
      instructorName = null;
    }

    await _membersCol(sgid).doc(memberUid).update({
      "clubRole": clubRoleToString(clubRole),
      "assignedInstructorUid": instructorUid,
      "assignedInstructorName": instructorName,
    });
  }

  Future<SchedulerGroup> _assertOwner(String sgid, String uid) async {
    final snap = await _groupRef(sgid).get();
    if (!snap.exists) throw StateError("Scheduler not found");
    final g = SchedulerGroup.fromDoc(snap);
    if (g.ownerUid != uid) {
      throw StateError("Only the owner can do that");
    }
    return g;
  }

  Future<SchedulerMember> _assertCanDispatch(String sgid, String uid) async {
    final memberSnap = await _membersCol(sgid).doc(uid).get();
    if (!memberSnap.exists) {
      throw StateError("Join this scheduler first");
    }
    final member = SchedulerMember.fromDoc(memberSnap);
    if (!member.isActive) {
      throw StateError("Membership pending owner approval");
    }
    if (!member.canDispatch) {
      throw StateError("Only the owner or a dispatcher can do that");
    }
    return member;
  }

  // -------------------- Resources --------------------

  Stream<List<SchedulableResource>> watchResources(String sgid) {
    return _resourcesCol(sgid).snapshots().map((s) {
      final list = s.docs.map(SchedulableResource.fromDoc).toList();
      list.sort((a, b) {
        // Aircraft first, then instructors, then by name.
        if (a.type != b.type) return a.isAircraft ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return list;
    });
  }

  /// Owner adds a schedulable resource (aircraft or instructor).
  Future<void> addResource(
    String sgid, {
    required String name,
    required ResourceType type,
    String? identifier,
    bool available = true,
    double? hobbs,
    double? tach,
  }) async {
    final uid = _requireUid();
    await _assertOwner(sgid, uid);
    final ref = _resourcesCol(sgid).doc();
    final resource = SchedulableResource(
      id: ref.id,
      name: name.trim(),
      type: type,
      identifier: identifier?.trim().isEmpty ?? true ? null : identifier!.trim(),
      available: available,
      createdAt: DateTime.now(),
      hobbs: type == ResourceType.aircraft ? hobbs : null,
      tach: type == ResourceType.aircraft ? tach : null,
    );
    final batch = _db.batch();
    batch.set(ref, resource.toMap());
    batch.update(_groupRef(sgid), {
      "resourceCount": FieldValue.increment(1),
    });
    await batch.commit();
  }

  /// Owner toggles a resource between available and out-of-service.
  Future<void> setResourceAvailability(
      String sgid, String resourceId, bool available) async {
    final uid = _requireUid();
    await _assertCanDispatch(sgid, uid);
    await _resourcesCol(sgid).doc(resourceId).update({"available": available});
  }

  /// Owner/dispatcher updates aircraft meters and MX due fields.
  Future<void> updateResourceDispatchStatus(
    String sgid,
    String resourceId, {
    double? hobbs,
    double? tach,
    DateTime? annualDue,
    double? hundredHourDueHobbs,
    DateTime? transponderDue,
    DateTime? eltDue,
    String? mxNotes,
    bool clearAnnualDue = false,
    bool clearHundredHourDueHobbs = false,
    bool clearTransponderDue = false,
    bool clearEltDue = false,
  }) async {
    final uid = _requireUid();
    await _assertCanDispatch(sgid, uid);
    final Map<String, dynamic> patch = {};
    if (hobbs != null) patch["hobbs"] = hobbs;
    if (tach != null) patch["tach"] = tach;
    if (clearAnnualDue) {
      patch["annualDue"] = null;
    } else if (annualDue != null) {
      patch["annualDue"] = Timestamp.fromDate(annualDue);
    }
    if (clearHundredHourDueHobbs) {
      patch["hundredHourDueHobbs"] = null;
    } else if (hundredHourDueHobbs != null) {
      patch["hundredHourDueHobbs"] = hundredHourDueHobbs;
    }
    if (clearTransponderDue) {
      patch["transponderDue"] = null;
    } else if (transponderDue != null) {
      patch["transponderDue"] = Timestamp.fromDate(transponderDue);
    }
    if (clearEltDue) {
      patch["eltDue"] = null;
    } else if (eltDue != null) {
      patch["eltDue"] = Timestamp.fromDate(eltDue);
    }
    if (mxNotes != null) {
      patch["mxNotes"] = mxNotes.trim().isEmpty ? null : mxNotes.trim();
    }
    if (patch.isEmpty) return;
    await _resourcesCol(sgid).doc(resourceId).update(patch);
  }

  /// Owner removes a resource along with all its reservations.
  Future<void> deleteResource(String sgid, String resourceId) async {
    final uid = _requireUid();
    await _assertOwner(sgid, uid);
    final resvs = await _reservationsCol(sgid)
        .where("resourceId", isEqualTo: resourceId)
        .get();
    final batch = _db.batch();
    for (final r in resvs.docs) {
      batch.delete(r.reference);
    }
    batch.delete(_resourcesCol(sgid).doc(resourceId));
    batch.update(_groupRef(sgid), {
      "resourceCount": FieldValue.increment(-1),
    });
    await batch.commit();
  }

  // -------------------- Reservations --------------------

  /// Watch the current user's reservations in this scheduler, soonest first.
  Stream<List<Reservation>> watchMyReservations(String sgid) {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _reservationsCol(sgid)
        .where("schedulerUid", isEqualTo: uid)
        .orderBy("start")
        .snapshots()
        .map((s) =>
            s.docs.map(Reservation.fromDoc).toList(growable: false));
  }

  static bool _isWeekend(DateTime d) =>
      d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;

  /// Watch every reservation that overlaps the given calendar [day],
  /// including multi-day reservations that started on an earlier day.
  Stream<List<Reservation>> watchReservationsForDay(String sgid, DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final lower = dayStart.subtract(const Duration(days: maxBookingDays));
    return _reservationsCol(sgid)
        .where("start", isGreaterThanOrEqualTo: Timestamp.fromDate(lower))
        .where("start", isLessThan: Timestamp.fromDate(dayEnd))
        .orderBy("start")
        .snapshots()
        .map((s) => s.docs
            .map(Reservation.fromDoc)
            // Keep only the ones that actually overlap this day.
            .where((r) => r.end.isAfter(dayStart))
            .toList(growable: false));
  }

  /// Reserve [resource] from [start] to [end]. If the resource is already
  /// booked (a main reservation overlaps), the caller is queued as a backup.
  ///
  /// Returns a [BookingResult] describing whether the caller got the slot or
  /// landed on the backup queue.
  Future<BookingResult> createReservation(
    String sgid, {
    required SchedulableResource resource,
    required DateTime start,
    required DateTime end,
    String? note,
    String? instructorUid,
    String? instructorName,
    String? studentUid,
    String? studentName,
    String? lessonPackId,
  }) async {
    final uid = _requireUid();
    final displayName = await _myDisplayName();

    if (!end.isAfter(start)) {
      throw StateError("End time must be after start time");
    }
    if (end.difference(start) > const Duration(days: maxBookingDays)) {
      throw StateError(
          "A reservation can be at most $maxBookingDays days long");
    }
    if (!resource.available) {
      throw StateError("${resource.name} is currently unavailable");
    }
    if (resource.isAircraft && resource.hundredHourOverdue) {
      throw StateError(
          "${resource.name} is past its 100-hour inspection hobbs");
    }

    // Membership check.
    final memberSnap = await _membersCol(sgid).doc(uid).get();
    if (!memberSnap.exists) {
      throw StateError("Join this scheduler before booking");
    }
    final member = SchedulerMember.fromDoc(memberSnap);
    if (!member.isActive) {
      throw StateError("Membership pending owner approval");
    }

    // Open grounding squawk blocks aircraft dispatch.
    if (resource.isAircraft) {
      final openSquawks = await _squawksCol(sgid)
          .where("resourceId", isEqualTo: resource.id)
          .where("status", isEqualTo: "open")
          .get();
      final grounding = openSquawks.docs
          .map(Squawk.fromDoc)
          .where((s) => s.isGrounding)
          .toList();
      if (grounding.isNotEmpty) {
        throw StateError(
            "${resource.name} has an open grounding squawk: "
            "${grounding.first.title}");
      }
    }

    // Enforce the owner's booking rules. The owner themselves is exempt so
    // they can always manage the schedule.
    if (!member.isOwner) {
      final groupSnap = await _groupRef(sgid).get();
      final group =
          groupSnap.exists ? SchedulerGroup.fromDoc(groupSnap) : null;
      final maxTotal = group?.maxReservationsPerMember ?? 0;
      final maxWeekend = group?.maxWeekendReservations ?? 0;
      final bookingIsWeekend = _isWeekend(start);
      if (maxTotal > 0 || (maxWeekend > 0 && bookingIsWeekend)) {
        final mineSnap = await _reservationsCol(sgid)
            .where("schedulerUid", isEqualTo: uid)
            .get();
        final now = DateTime.now();
        // Only count current/upcoming reservations against the limits.
        final active = mineSnap.docs
            .map(Reservation.fromDoc)
            .where((r) => r.end.isAfter(now))
            .toList();
        if (maxTotal > 0 && active.length >= maxTotal) {
          throw StateError(
              "Booking limit reached: you can hold at most $maxTotal "
              "reservation${maxTotal == 1 ? '' : 's'} at a time");
        }
        if (maxWeekend > 0 && bookingIsWeekend) {
          final weekendCount =
              active.where((r) => _isWeekend(r.start)).length;
          if (weekendCount >= maxWeekend) {
            throw StateError(
                "Weekend limit reached: you can hold at most $maxWeekend "
                "weekend reservation${maxWeekend == 1 ? '' : 's'} at a time");
          }
        }
      }
    }

    // Default student→instructor from membership when booking as a student.
    String? resolvedInstructorUid = instructorUid;
    String? resolvedInstructorName = instructorName;
    String? resolvedStudentUid = studentUid;
    String? resolvedStudentName = studentName;
    if (member.isStudent) {
      resolvedStudentUid ??= uid;
      resolvedStudentName ??= displayName;
      if (resolvedInstructorUid == null &&
          member.assignedInstructorUid != null) {
        resolvedInstructorUid = member.assignedInstructorUid;
        resolvedInstructorName = member.assignedInstructorName;
      }
    }

    if (lessonPackId != null) {
      final packSnap = await _lessonPacksCol(sgid).doc(lessonPackId).get();
      if (!packSnap.exists) {
        throw StateError("Lesson pack not found");
      }
      final pack = LessonPack.fromDoc(packSnap);
      if (!pack.isActive) {
        throw StateError("Lesson pack is not active");
      }
      if (pack.hoursRemaining <= 0) {
        throw StateError("Lesson pack has no hours remaining");
      }
      resolvedStudentUid ??= pack.studentUid;
      resolvedStudentName ??= pack.studentName;
      resolvedInstructorUid ??= pack.instructorUid;
      resolvedInstructorName ??= pack.instructorName;
    }

    // Find existing reservations on this resource that overlap the requested
    // window (which may span multiple days). NOTE: there is a small race
    // window here (no Cloud Function/transactional query) — two simultaneous
    // bookings could both think they are the main reservation. This mirrors
    // the existing rules-only compromises in the Community feature and is
    // acceptable for v1; the owner can always cancel a duplicate.
    final lower = start.subtract(const Duration(days: maxBookingDays));
    final existingSnap = await _reservationsCol(sgid)
        .where("resourceId", isEqualTo: resource.id)
        .where("start", isGreaterThanOrEqualTo: Timestamp.fromDate(lower))
        .where("start", isLessThan: Timestamp.fromDate(end))
        .get();

    final overlapping = existingSnap.docs
        .map(Reservation.fromDoc)
        .where((r) => r.overlaps(start, end))
        .toList();

    if (overlapping.any((r) => r.schedulerUid == uid)) {
      throw StateError("You already have a reservation in this window");
    }

    final hasMain = overlapping.any((r) => r.isMain);
    final bool isBackup = hasMain;
    int backupOrder = 0;
    if (isBackup) {
      final maxBackup = overlapping
          .where((r) => r.isBackup)
          .fold<int>(0, (m, r) => r.backupOrder > m ? r.backupOrder : m);
      backupOrder = maxBackup + 1;
    }

    final ref = _reservationsCol(sgid).doc();
    final reservation = Reservation(
      id: ref.id,
      resourceId: resource.id,
      resourceName: resource.name,
      schedulerUid: uid,
      schedulerName: displayName,
      start: start,
      end: end,
      isBackup: isBackup,
      backupOrder: backupOrder,
      note: (note?.trim().isEmpty ?? true) ? null : note!.trim(),
      createdAt: DateTime.now(),
      instructorUid: resolvedInstructorUid,
      instructorName: resolvedInstructorName,
      studentUid: resolvedStudentUid,
      studentName: resolvedStudentName,
      lessonPackId: lessonPackId,
    );
    await ref.set(reservation.toCreateMap());
    return BookingResult(isBackup: isBackup, backupOrder: backupOrder);
  }

  /// Cancel a reservation. Only the member who made it or the group owner may
  /// cancel. If a **main** reservation is cancelled, the next backup in line
  /// (lowest [Reservation.backupOrder]) overlapping the same window is
  /// promoted to the main reservation.
  Future<void> cancelReservation(String sgid, Reservation reservation) async {
    final uid = _requireUid();
    final group = await _groupRef(sgid).get();
    final isOwner = group.exists &&
        (SchedulerGroup.fromDoc(group).ownerUid == uid);
    if (reservation.schedulerUid != uid && !isOwner) {
      throw StateError("Only the owner or the booking member can cancel this");
    }

    // Delete the reservation first.
    await _reservationsCol(sgid).doc(reservation.id).delete();

    // Only a main reservation triggers a promotion.
    if (reservation.isBackup) return;

    final lower =
        reservation.start.subtract(const Duration(days: maxBookingDays));
    final snap = await _reservationsCol(sgid)
        .where("resourceId", isEqualTo: reservation.resourceId)
        .where("start", isGreaterThanOrEqualTo: Timestamp.fromDate(lower))
        .where("start", isLessThan: Timestamp.fromDate(reservation.end))
        .get();

    final backups = snap.docs
        .map(Reservation.fromDoc)
        .where((r) =>
            r.isBackup && r.overlaps(reservation.start, reservation.end))
        .toList()
      ..sort((a, b) => a.backupOrder.compareTo(b.backupOrder));

    if (backups.isEmpty) return;

    final promoted = backups.first;
    await _reservationsCol(sgid).doc(promoted.id).update({
      "isBackup": false,
      "backupOrder": 0,
    });
  }

  // -------------------- Squawks --------------------

  Stream<List<Squawk>> watchSquawks(String sgid, {SquawkStatus? status}) {
    Query<Map<String, dynamic>> q = _squawksCol(sgid);
    if (status != null) {
      q = q.where("status", isEqualTo: squawkStatusToString(status));
    }
    return q.snapshots().map((s) {
      final list = s.docs.map(Squawk.fromDoc).toList();
      list.sort((a, b) {
        if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
        if (a.severity != b.severity) {
          return a.severity.index.compareTo(b.severity.index);
        }
        return b.createdAt.compareTo(a.createdAt);
      });
      return list;
    });
  }

  Stream<List<Squawk>> watchOpenSquawksForResource(
      String sgid, String resourceId) {
    return _squawksCol(sgid)
        .where("resourceId", isEqualTo: resourceId)
        .where("status", isEqualTo: "open")
        .snapshots()
        .map((s) {
      final list = s.docs.map(Squawk.fromDoc).toList();
      list.sort((a, b) => a.severity.index.compareTo(b.severity.index));
      return list;
    });
  }

  /// Any active member can file a squawk on a fleet aircraft.
  Future<void> createSquawk(
    String sgid, {
    required SchedulableResource resource,
    required String title,
    required String description,
    required SquawkSeverity severity,
  }) async {
    final uid = _requireUid();
    final displayName = await _myDisplayName();
    final memberSnap = await _membersCol(sgid).doc(uid).get();
    if (!memberSnap.exists || !SchedulerMember.fromDoc(memberSnap).isActive) {
      throw StateError("Join this scheduler before filing a squawk");
    }
    if (!resource.isAircraft) {
      throw StateError("Squawks apply to aircraft only");
    }
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw StateError("Enter a squawk title");
    }
    final ref = _squawksCol(sgid).doc();
    final squawk = Squawk(
      id: ref.id,
      resourceId: resource.id,
      resourceName: resource.name,
      title: trimmed,
      description: description.trim(),
      severity: severity,
      status: SquawkStatus.open,
      reportedByUid: uid,
      reportedByName: displayName,
      createdAt: DateTime.now(),
    );
    // Grounding squawks block booking via open-squawk checks and show as
    // GROUNDED on the fleet board; availability toggle remains owner/dispatcher.
    await ref.set(squawk.toCreateMap());
  }

  /// Reporter, owner, or dispatcher can resolve an open squawk.
  Future<void> resolveSquawk(String sgid, Squawk squawk) async {
    final uid = _requireUid();
    final displayName = await _myDisplayName();
    final memberSnap = await _membersCol(sgid).doc(uid).get();
    if (!memberSnap.exists) {
      throw StateError("Not a member of this scheduler");
    }
    final member = SchedulerMember.fromDoc(memberSnap);
    if (!member.isActive) {
      throw StateError("Membership pending owner approval");
    }
    if (!member.canDispatch && squawk.reportedByUid != uid) {
      throw StateError("Only the reporter, owner, or dispatcher can resolve");
    }
    await _squawksCol(sgid).doc(squawk.id).update({
      "status": "resolved",
      "resolvedAt": Timestamp.fromDate(DateTime.now()),
      "resolvedByUid": uid,
      "resolvedByName": displayName,
    });
  }

  Future<void> deleteSquawk(String sgid, String squawkId) async {
    final uid = _requireUid();
    await _assertCanDispatch(sgid, uid);
    await _squawksCol(sgid).doc(squawkId).delete();
  }

  // -------------------- Lesson packs --------------------

  Stream<List<LessonPack>> watchLessonPacks(String sgid) {
    return _lessonPacksCol(sgid).snapshots().map((s) {
      final list = s.docs.map(LessonPack.fromDoc).toList();
      list.sort((a, b) {
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        return a.studentName
            .toLowerCase()
            .compareTo(b.studentName.toLowerCase());
      });
      return list;
    });
  }

  /// Owner creates a prepaid lesson block for a student.
  Future<void> createLessonPack(
    String sgid, {
    required String name,
    String description = "",
    required double totalHours,
    required String studentUid,
    required String studentName,
    String? instructorUid,
    String? instructorName,
    DateTime? expiresAt,
  }) async {
    final uid = _requireUid();
    await _assertOwner(sgid, uid);
    if (totalHours <= 0) {
      throw StateError("Lesson pack hours must be greater than zero");
    }
    final ref = _lessonPacksCol(sgid).doc();
    final pack = LessonPack(
      id: ref.id,
      name: name.trim().isEmpty ? "Lesson pack" : name.trim(),
      description: description.trim(),
      totalHours: totalHours,
      hoursUsed: 0,
      studentUid: studentUid,
      studentName: studentName,
      instructorUid: instructorUid,
      instructorName: instructorName,
      status: LessonPackStatus.active,
      createdAt: DateTime.now(),
      expiresAt: expiresAt,
    );
    await ref.set(pack.toCreateMap());
  }

  /// Owner / assigned instructor logs hours against a pack (e.g. after a lesson).
  Future<void> logLessonPackHours(
    String sgid,
    String packId, {
    required double hours,
  }) async {
    final uid = _requireUid();
    if (hours <= 0) {
      throw StateError("Hours must be greater than zero");
    }
    final packSnap = await _lessonPacksCol(sgid).doc(packId).get();
    if (!packSnap.exists) throw StateError("Lesson pack not found");
    final pack = LessonPack.fromDoc(packSnap);
    if (!pack.isActive) throw StateError("Lesson pack is not active");

    final memberSnap = await _membersCol(sgid).doc(uid).get();
    if (!memberSnap.exists) throw StateError("Not a member");
    final member = SchedulerMember.fromDoc(memberSnap);
    final allowed = member.isOwner ||
        member.isDispatcher ||
        (pack.instructorUid != null && pack.instructorUid == uid) ||
        pack.studentUid == uid;
    if (!allowed) {
      throw StateError("Not allowed to log hours on this pack");
    }

    final used = pack.hoursUsed + hours;
    final Map<String, dynamic> patch = {"hoursUsed": used};
    if (used >= pack.totalHours) {
      patch["status"] = lessonPackStatusToString(LessonPackStatus.completed);
    }
    await _lessonPacksCol(sgid).doc(packId).update(patch);
  }

  Future<void> setLessonPackStatus(
    String sgid,
    String packId,
    LessonPackStatus status,
  ) async {
    final uid = _requireUid();
    await _assertOwner(sgid, uid);
    await _lessonPacksCol(sgid).doc(packId).update({
      "status": lessonPackStatusToString(status),
    });
  }

  Future<void> deleteLessonPack(String sgid, String packId) async {
    final uid = _requireUid();
    await _assertOwner(sgid, uid);
    await _lessonPacksCol(sgid).doc(packId).delete();
  }
}
