import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants.dart';
import '../utils/toast.dart';
import 'data/scheduler_repository.dart';
import 'models/lesson_pack.dart';
import 'models/reservation.dart';
import 'models/schedulable_resource.dart';
import 'models/scheduler_group.dart';
import 'models/scheduler_member.dart';
import 'scheduler_admin_screen.dart';
import 'scheduler_dispatch_screen.dart';
import 'scheduler_members_screen.dart';
import 'widgets/schedule_grid.dart';
import 'widgets/scheduler_join_leave_button.dart';

class SchedulerDetailScreen extends StatelessWidget {
  final String groupId;
  const SchedulerDetailScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SchedulerGroup?>(
      stream: SchedulerRepository.instance.watchGroup(groupId),
      builder: (context, gSnap) {
        final group = gSnap.data;
        return StreamBuilder<SchedulerMember?>(
          stream: SchedulerRepository.instance.watchMyMembership(groupId),
          builder: (context, mSnap) {
            final membership = mSnap.data;
            if (gSnap.connectionState == ConnectionState.waiting ||
                mSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }
            if (group == null) {
              return Scaffold(
                appBar: AppBar(
                  backgroundColor: Constants.appBarBackgroundColor,
                  title: const Text("Scheduler"),
                ),
                body: const Center(
                    child: Text("This scheduler has been deleted.")),
              );
            }
            return _SchedulerDetailBody(group: group, membership: membership);
          },
        );
      },
    );
  }
}

class _SchedulerDetailBody extends StatelessWidget {
  final SchedulerGroup group;
  final SchedulerMember? membership;
  const _SchedulerDetailBody({required this.group, this.membership});

  bool get _isOwner => membership?.isOwner ?? false;
  bool get _isActive => membership?.isActive ?? false;

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete scheduler?"),
        content: Text(
            "Delete '${group.name}'? This removes all resources, reservations and memberships and cannot be undone."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await SchedulerRepository.instance.deleteGroup(group.id);
      if (!context.mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (context.mounted) {
        Toast.showToast(context, "Delete failed: $e",
            const Icon(Icons.error, color: Colors.red), 4);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pendingBadge = _isOwner
        ? StreamBuilder<List<SchedulerMember>>(
            stream: SchedulerRepository.instance
                .watchMembers(group.id, status: SchedulerMemberStatus.pending),
            builder: (context, snap) {
              final count = snap.data?.length ?? 0;
              if (count == 0) return const SizedBox.shrink();
              return Positioned(
                top: 8,
                right: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: scheme.error,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "$count",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              );
            },
          )
        : const SizedBox.shrink();

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Constants.appBarBackgroundColor,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  group.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (group.isPrivate)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.lock_outline,
                      size: 16, color: scheme.outline),
                ),
            ],
          ),
          actions: [
            if (_isOwner)
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: "Booking rules",
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SchedulerAdminScreen(group: group),
                    ),
                  );
                },
              ),
            if (_isOwner)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: "Delete scheduler",
                onPressed: () => _confirmDelete(context),
              ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              const Tab(icon: Icon(Icons.calendar_month), text: "Schedule"),
              const Tab(icon: Icon(Icons.local_airport), text: "Dispatch"),
              const Tab(icon: Icon(Icons.event_note), text: "Mine"),
              Tab(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.people),
                    pendingBadge,
                  ],
                ),
                text: "Members",
              ),
              const Tab(icon: Icon(Icons.info_outline), text: "About"),
            ],
          ),
        ),
        body: Column(
          children: [
            _MembershipBanner(group: group, membership: membership),
            Expanded(
              child: TabBarView(
                children: [
                  _ScheduleTab(
                    group: group,
                    isOwner: _isOwner,
                    canBook: _isActive,
                  ),
                  SchedulerDispatchScreen(
                    groupId: group.id,
                    canDispatch: membership?.canDispatch ?? false,
                    isOwner: _isOwner,
                    canUse: _isActive,
                    embedded: true,
                  ),
                  _MyReservationsTab(group: group),
                  SchedulerMembersScreen(
                    groupId: group.id,
                    isOwner: _isOwner,
                    embedded: true,
                  ),
                  _AboutTab(group: group),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MembershipBanner extends StatelessWidget {
  final SchedulerGroup group;
  final SchedulerMember? membership;
  const _MembershipBanner({required this.group, this.membership});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      color: scheme.surfaceContainerHighest.withAlpha(120),
      child: Row(
        children: [
          Expanded(
            child: Text(
              membership == null
                  ? (group.isPrivate
                      ? "This is a private scheduler. Request to join to book resources."
                      : "Join this scheduler to book aircraft and instructors.")
                  : (membership!.isPending
                      ? "Your request is waiting for owner approval."
                      : membership!.isOwner
                          ? "You own this scheduler."
                          : "You're a member — tap a green slot to book."),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          SchedulerJoinLeaveButton(
            group: group,
            membership: membership,
            onMessage: (m) {
              if (context.mounted) {
                Toast.showToast(context, m, const Icon(Icons.info), 3);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _ScheduleTab extends StatefulWidget {
  final SchedulerGroup group;
  final bool isOwner;
  final bool canBook;
  const _ScheduleTab({
    required this.group,
    required this.isOwner,
    required this.canBook,
  });

  @override
  State<_ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends State<_ScheduleTab> {
  late DateTime _day;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _day = DateTime(now.year, now.month, now.day);
  }

  String _dayLabel(DateTime d) => _fmtDay(d);

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _day = DateTime(picked.year, picked.month, picked.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = SchedulerRepository.instance;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Column(
      children: [
        _DayBar(
          label: _dayLabel(_day),
          isToday: _isToday(_day),
          onPrev: () => setState(
              () => _day = _day.subtract(const Duration(days: 1))),
          onNext: () =>
              setState(() => _day = _day.add(const Duration(days: 1))),
          onPick: _pickDay,
          onToday: () {
            final now = DateTime.now();
            setState(() => _day = DateTime(now.year, now.month, now.day));
          },
        ),
        const _Legend(),
        if (widget.isOwner)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton.icon(
                onPressed: () => _showAddResourceDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text("Add resource"),
              ),
            ),
          ),
        Expanded(
          child: StreamBuilder<List<SchedulableResource>>(
            stream: repo.watchResources(widget.group.id),
            builder: (context, resSnap) {
              if (resSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final resources = resSnap.data ?? const [];
              return StreamBuilder<List<Reservation>>(
                stream: repo.watchReservationsForDay(widget.group.id, _day),
                builder: (context, resvSnap) {
                  final reservations = resvSnap.data ?? const [];
                  return ScheduleGrid(
                    day: _day,
                    resources: resources,
                    reservations: reservations,
                    currentUid: uid,
                    onTapEmpty: (resource, startHour) {
                      if (!widget.canBook) {
                        Toast.showToast(
                            context,
                            "Join this scheduler to book resources",
                            const Icon(Icons.info, color: Colors.orange),
                            3);
                        return;
                      }
                      _showBookingDialog(context, resource, startHour);
                    },
                    onTapReservation: (r) =>
                        _showReservationSheet(context, r, uid),
                    onTapResource: widget.isOwner
                        ? (resource) =>
                            _showManageResourceDialog(context, resource)
                        : null,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  // -------------------- Booking --------------------

  Future<void> _showBookingDialog(BuildContext context,
      SchedulableResource resource, DateTime initialStart) async {
    DateTime startDate =
        DateTime(initialStart.year, initialStart.month, initialStart.day);
    int startHour = initialStart.hour;
    final defaultEnd = initialStart.add(const Duration(hours: 1));
    DateTime endDate =
        DateTime(defaultEnd.year, defaultEnd.month, defaultEnd.day);
    int endHour = defaultEnd.hour;

    DateTime composeStart() =>
        DateTime(startDate.year, startDate.month, startDate.day, startHour);
    DateTime composeEnd() =>
        DateTime(endDate.year, endDate.month, endDate.day, endHour);

    final firstDate = DateTime.now().subtract(const Duration(days: 1));
    final lastDate = DateTime.now().add(const Duration(days: 365));

    // Training assignment options (aircraft bookings).
    final members = await SchedulerRepository.instance
        .watchMembers(widget.group.id)
        .first;
    final instructors =
        members.where((m) => m.isActive && m.isInstructor).toList();
    final packs = resource.isAircraft
        ? (await SchedulerRepository.instance
                .watchLessonPacks(widget.group.id)
                .first)
            .where((p) => p.isActive && p.hoursRemaining > 0)
            .toList()
        : <LessonPack>[];
    final myMembership = members.cast<SchedulerMember?>().firstWhere(
          (m) => m?.uid == FirebaseAuth.instance.currentUser?.uid,
          orElse: () => null,
        );
    SchedulerMember? selectedInstructor;
    if (myMembership?.assignedInstructorUid != null) {
      selectedInstructor = instructors.cast<SchedulerMember?>().firstWhere(
            (i) => i?.uid == myMembership!.assignedInstructorUid,
            orElse: () => null,
          );
    }
    String? selectedPackId;

    if (!context.mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final scheme = Theme.of(ctx).colorScheme;
            final start = composeStart();
            final end = composeEnd();
            final spanDays = end.difference(start).inDays;
            final valid = end.isAfter(start) &&
                end.difference(start) <=
                    const Duration(
                        days: SchedulerRepository.maxBookingDays);

            Widget pickerRow(String label, String value, VoidCallback onTap) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(width: 64, child: Text(label)),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onTap,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(value),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            Widget hourRow(String label, int hour, ValueChanged<int> onChanged) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(width: 64, child: Text(label)),
                    Expanded(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: hour,
                        items: [
                          for (int h = 0; h < 24; h++)
                            DropdownMenuItem(
                                value: h, child: Text(_fmtHour(h))),
                        ],
                        onChanged: (v) => onChanged(v ?? hour),
                      ),
                    ),
                  ],
                ),
              );
            }

            return AlertDialog(
              title: Text("Book ${resource.name}"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Starts",
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                            color: scheme.primary)),
                    pickerRow("Date", _fmtDay(startDate), () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: startDate,
                        firstDate: firstDate,
                        lastDate: lastDate,
                      );
                      if (picked != null) {
                        setLocal(() {
                          startDate = DateTime(
                              picked.year, picked.month, picked.day);
                          if (endDate.isBefore(startDate)) endDate = startDate;
                        });
                      }
                    }),
                    hourRow("Time", startHour,
                        (v) => setLocal(() => startHour = v)),
                    const SizedBox(height: 8),
                    Text("Ends",
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                            color: scheme.primary)),
                    pickerRow("Date", _fmtDay(endDate), () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate:
                            endDate.isBefore(startDate) ? startDate : endDate,
                        firstDate: startDate,
                        lastDate: lastDate,
                      );
                      if (picked != null) {
                        setLocal(() => endDate = DateTime(
                            picked.year, picked.month, picked.day));
                      }
                    }),
                    hourRow("Time", endHour,
                        (v) => setLocal(() => endHour = v)),
                    if (resource.isAircraft &&
                        (instructors.isNotEmpty || packs.isNotEmpty)) ...[
                      const SizedBox(height: 12),
                      Text("Training (optional)",
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.1,
                              color: scheme.primary)),
                      if (instructors.isNotEmpty)
                        DropdownButtonFormField<SchedulerMember?>(
                          initialValue: selectedInstructor,
                          decoration: const InputDecoration(
                            labelText: "Instructor",
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(
                                value: null, child: Text("None")),
                            for (final i in instructors)
                              DropdownMenuItem(
                                  value: i, child: Text(i.displayName)),
                          ],
                          onChanged: (v) =>
                              setLocal(() => selectedInstructor = v),
                        ),
                      if (packs.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String?>(
                          initialValue: selectedPackId,
                          decoration: const InputDecoration(
                            labelText: "Lesson pack",
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(
                                value: null, child: Text("None")),
                            for (final p in packs)
                              DropdownMenuItem(
                                value: p.id,
                                child: Text(
                                  "${p.name} (${p.hoursRemaining.toStringAsFixed(1)} hrs)",
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) =>
                              setLocal(() => selectedPackId = v),
                        ),
                      ],
                    ],
                    const SizedBox(height: 10),
                    Text(
                      "${_fmtDay(start)} ${_fmtHour(start.hour)}  →  "
                      "${_fmtDay(end)} ${_fmtHour(end.hour)}",
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (spanDays >= 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          "Spans $spanDays day${spanDays == 1 ? '' : 's'}",
                          style: TextStyle(
                              fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                      ),
                    const SizedBox(height: 4),
                    if (!valid)
                      Text(
                        end.isAfter(start)
                            ? "A reservation can be at most ${SchedulerRepository.maxBookingDays} days long."
                            : "End must be after start.",
                        style: TextStyle(fontSize: 11, color: scheme.error),
                      )
                    else
                      Text(
                        "If this resource is already booked for this time, "
                        "you'll be queued as a backup.",
                        style: TextStyle(
                            fontSize: 11, color: scheme.outline),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text("Cancel")),
                FilledButton(
                    onPressed:
                        valid ? () => Navigator.pop(ctx, true) : null,
                    child: const Text("Book")),
              ],
            );
          },
        );
      },
    );

    if (result != true || !context.mounted) return;

    final start = composeStart();
    final end = composeEnd();

    try {
      final r = await SchedulerRepository.instance.createReservation(
        widget.group.id,
        resource: resource,
        start: start,
        end: end,
        instructorUid: selectedInstructor?.uid,
        instructorName: selectedInstructor?.displayName,
        lessonPackId: selectedPackId,
      );
      if (!context.mounted) return;
      if (r.isBackup) {
        Toast.showToast(
            context,
            "Added as backup #${r.backupOrder} for ${resource.name}",
            const Icon(Icons.hourglass_bottom, color: Colors.blue),
            3);
      } else {
        Toast.showToast(context, "Booked ${resource.name}",
            const Icon(Icons.check, color: Colors.green), 3);
      }
    } catch (e) {
      if (context.mounted) {
        Toast.showToast(context, "Could not book: $e",
            const Icon(Icons.error, color: Colors.red), 4);
      }
    }
  }

  // -------------------- Reservation details / cancel --------------------

  void _showReservationSheet(
      BuildContext context, Reservation r, String? uid) {
    final isOwner = widget.isOwner;
    final mine = uid != null && r.schedulerUid == uid;
    final canCancel = isOwner || mine;
    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(r.isMain ? Icons.event_available : Icons.hourglass_bottom,
                        color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        r.resourceName,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (r.isBackup)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text("Backup #${r.backupOrder}",
                            style: const TextStyle(fontSize: 11)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text("Reserved by ${r.schedulerName}"),
                const SizedBox(height: 4),
                Text(
                  _fmtRange(r.start, r.end),
                  style: TextStyle(color: scheme.outline, fontSize: 13),
                ),
                if (r.instructorName != null) ...[
                  const SizedBox(height: 6),
                  Text("Instructor: ${r.instructorName}"),
                ],
                if (r.studentName != null) ...[
                  const SizedBox(height: 2),
                  Text("Student: ${r.studentName}"),
                ],
                if (r.lessonPackId != null) ...[
                  const SizedBox(height: 2),
                  Text("Lesson pack linked",
                      style: TextStyle(fontSize: 12, color: scheme.outline)),
                ],
                if (r.note != null && r.note!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(r.note!),
                ],
                const SizedBox(height: 16),
                if (canCancel)
                  FilledButton.tonalIcon(
                    style:
                        FilledButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _cancel(context, r);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: Text(r.isMain && !mine
                        ? "Cancel this reservation"
                        : "Cancel my reservation"),
                  )
                else
                  Text(
                    "Only ${r.schedulerName} or the owner can cancel this.",
                    style: TextStyle(fontSize: 12, color: scheme.outline),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _cancel(BuildContext context, Reservation r) =>
      _confirmCancelReservation(context, widget.group.id, r);

  // -------------------- Resource management (owner) --------------------

  Future<void> _showAddResourceDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    ResourceType type = ResourceType.aircraft;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text("Add resource"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<ResourceType>(
                  segments: const [
                    ButtonSegment(
                        value: ResourceType.aircraft,
                        icon: Icon(Icons.flight),
                        label: Text("Aircraft")),
                    ButtonSegment(
                        value: ResourceType.instructor,
                        icon: Icon(Icons.person),
                        label: Text("Instructor")),
                  ],
                  selected: {type},
                  onSelectionChanged: (s) =>
                      setLocal(() => type = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: type == ResourceType.aircraft
                        ? "Aircraft name / model"
                        : "Instructor name",
                    border: const OutlineInputBorder(),
                  ),
                ),
                TextField(
                  controller: idCtrl,
                  maxLength: 20,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: type == ResourceType.aircraft
                        ? "Tail number (optional)"
                        : "Identifier (optional)",
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("Cancel")),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("Add")),
            ],
          );
        });
      },
    );

    if (ok != true || !context.mounted) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      Toast.showToast(context, "Enter a name for the resource",
          const Icon(Icons.info, color: Colors.orange), 3);
      return;
    }
    try {
      await SchedulerRepository.instance.addResource(
        widget.group.id,
        name: name,
        type: type,
        identifier: idCtrl.text.trim(),
      );
      if (context.mounted) {
        Toast.showToast(context, "Added $name",
            const Icon(Icons.check, color: Colors.green), 2);
      }
    } catch (e) {
      if (context.mounted) {
        Toast.showToast(context, "Could not add resource: $e",
            const Icon(Icons.error, color: Colors.red), 4);
      }
    }
  }

  Future<void> _showManageResourceDialog(
      BuildContext context, SchedulableResource resource) async {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                    resource.isAircraft ? Icons.flight : Icons.person),
                title: Text(resource.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(resource.available
                    ? "Available"
                    : "Unavailable (out of service)"),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text("Available for booking"),
                subtitle: Text(resource.available
                    ? "Members can book this resource"
                    : "Shown in red; bookings are blocked"),
                value: resource.available,
                onChanged: (v) async {
                  Navigator.pop(ctx);
                  try {
                    await SchedulerRepository.instance.setResourceAvailability(
                        widget.group.id, resource.id, v);
                  } catch (e) {
                    if (context.mounted) {
                      Toast.showToast(context, "Update failed: $e",
                          const Icon(Icons.error, color: Colors.red), 4);
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text("Delete resource",
                    style: TextStyle(color: Colors.red)),
                subtitle: const Text("Removes the resource and its reservations"),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _confirmDeleteResource(context, resource);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteResource(
      BuildContext context, SchedulableResource resource) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Delete ${resource.name}?"),
        content: const Text(
            "This removes the resource and all of its reservations. This cannot be undone."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await SchedulerRepository.instance
          .deleteResource(widget.group.id, resource.id);
    } catch (e) {
      if (context.mounted) {
        Toast.showToast(context, "Could not delete: $e",
            const Icon(Icons.error, color: Colors.red), 4);
      }
    }
  }
}

String _fmtDay(DateTime d) {
  const months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
  ];
  const weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
  return "${weekdays[d.weekday - 1]} ${months[d.month - 1]} ${d.day}";
}

bool _isWeekendDay(DateTime d) =>
    d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;

/// Shared cancel confirmation + execution used by both the Schedule grid and
/// the "Mine" reservations list.
Future<void> _confirmCancelReservation(
    BuildContext context, String sgid, Reservation r) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text("Cancel reservation?"),
      content: Text(r.isMain
          ? "This frees up ${r.resourceName}. If anyone is on the backup list, the next backup becomes the main reservation."
          : "This removes your backup reservation for ${r.resourceName}."),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Keep")),
        FilledButton.tonal(
          style: FilledButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text("Cancel reservation"),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await SchedulerRepository.instance.cancelReservation(sgid, r);
    if (context.mounted) {
      Toast.showToast(context, "Reservation cancelled",
          const Icon(Icons.check, color: Colors.green), 2);
    }
  } catch (e) {
    if (context.mounted) {
      Toast.showToast(context, "Could not cancel: $e",
          const Icon(Icons.error, color: Colors.red), 4);
    }
  }
}

String _fmtHour(int h) {
  if (h == 0) return "12:00 AM";
  if (h == 24) return "12:00 AM";
  if (h == 12) return "12:00 PM";
  if (h < 12) return "$h:00 AM";
  return "${h - 12}:00 PM";
}

String _fmtTime(DateTime t) {
  final h = t.hour;
  final m = t.minute.toString().padLeft(2, '0');
  final ampm = h < 12 ? "AM" : "PM";
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return "$h12:$m $ampm";
}

/// Formats a reservation window. Single-day bookings read
/// "Sat Jun 27 · 9:00 AM – 11:00 AM"; multi-day bookings include the end
/// date so it isn't lost: "Sat Jun 27 9:00 AM – Sun Jun 28 11:00 AM".
String _fmtRange(DateTime start, DateTime end) {
  final sameDay = start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  if (sameDay) {
    return "${_fmtDay(start)}  ·  ${_fmtTime(start)} – ${_fmtTime(end)}";
  }
  return "${_fmtDay(start)} ${_fmtTime(start)} – "
      "${_fmtDay(end)} ${_fmtTime(end)}";
}

class _MyReservationsTab extends StatelessWidget {
  final SchedulerGroup group;
  const _MyReservationsTab({required this.group});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<List<Reservation>>(
      stream: SchedulerRepository.instance.watchMyReservations(group.id),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text("Couldn't load your reservations: ${snap.error}",
                  textAlign: TextAlign.center),
            ),
          );
        }
        final all = snap.data ?? const [];
        final now = DateTime.now();
        final upcoming = all.where((r) => r.end.isAfter(now)).toList();
        final past = all.where((r) => !r.end.isAfter(now)).toList()
          ..sort((a, b) => b.start.compareTo(a.start));

        if (all.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_busy, size: 48, color: scheme.outline),
                  const SizedBox(height: 12),
                  const Text("No reservations yet",
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(
                    "Book a resource from the Schedule tab and it'll show up here.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.outline, fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }

        final limits = <String>[
          if (group.maxReservationsPerMember > 0)
            "${upcoming.length}/${group.maxReservationsPerMember} active",
          if (group.maxWeekendReservations > 0)
            "${upcoming.where((r) => _isWeekendDay(r.start)).length}/${group.maxWeekendReservations} weekend",
        ];

        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            if (limits.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Wrap(
                  spacing: 8,
                  children: limits
                      .map((l) => Chip(
                            visualDensity: VisualDensity.compact,
                            avatar: const Icon(Icons.rule, size: 16),
                            label: Text(l,
                                style: const TextStyle(fontSize: 11)),
                          ))
                      .toList(),
                ),
              ),
            _header(context, "Upcoming (${upcoming.length})"),
            if (upcoming.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: Text("No upcoming reservations")),
              )
            else
              ...upcoming.map((r) => _tile(context, r, cancellable: true)),
            if (past.isNotEmpty) ...[
              _header(context, "Past (${past.length})"),
              ...past.map((r) => _tile(context, r, cancellable: false)),
            ],
          ],
        );
      },
    );
  }

  Widget _header(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, Reservation r,
      {required bool cancellable}) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        r.isMain ? Icons.event_available : Icons.hourglass_bottom,
        color: cancellable ? Colors.blue : scheme.outline,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(r.resourceName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (r.isBackup)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Chip(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                label: Text("Backup #${r.backupOrder}",
                    style: const TextStyle(fontSize: 10)),
              ),
            ),
          if (_isWeekendDay(r.start))
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Chip(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                label: Text("Weekend", style: TextStyle(fontSize: 10)),
              ),
            ),
        ],
      ),
      subtitle: Text(
        _fmtRange(r.start, r.end),
        style: TextStyle(fontSize: 12, color: scheme.outline),
      ),
      trailing: cancellable
          ? IconButton(
              tooltip: "Cancel",
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () =>
                  _confirmCancelReservation(context, group.id, r),
            )
          : null,
    );
  }
}

class _DayBar extends StatelessWidget {
  final String label;
  final bool isToday;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPick;
  final VoidCallback onToday;
  const _DayBar({
    required this.label,
    required this.isToday,
    required this.onPrev,
    required this.onNext,
    required this.onPick,
    required this.onToday,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
              onPressed: onPrev, icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: TextButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          if (!isToday)
            TextButton(onPressed: onToday, child: const Text("Today")),
          IconButton(
              onPressed: onNext, icon: const Icon(Icons.chevron_right)),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) {
    Widget swatch(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        children: [
          swatch(Colors.green.withValues(alpha: 0.4), "Available"),
          swatch(Colors.blue.shade600, "Booked"),
          swatch(Colors.red.withValues(alpha: 0.5), "Unavailable"),
        ],
      ),
    );
  }
}

class _AboutTab extends StatelessWidget {
  final SchedulerGroup group;
  const _AboutTab({required this.group});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.name,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(
                  group.description.isEmpty
                      ? "No description provided."
                      : group.description,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                _kv(context, "Owner", group.ownerName),
                _kv(context, "Visibility",
                    group.isPrivate ? "Private" : "Public"),
                if (group.homeAirport != null)
                  _kv(context, "Home airport", group.homeAirport!),
                _kv(context, "Members", "${group.memberCount}"),
                _kv(context, "Resources", "${group.resourceCount}"),
                _kv(
                    context,
                    "Max per member",
                    group.maxReservationsPerMember == 0
                        ? "Unlimited"
                        : "${group.maxReservationsPerMember}"),
                _kv(
                    context,
                    "Max weekend",
                    group.maxWeekendReservations == 0
                        ? "Unlimited"
                        : "${group.maxWeekendReservations}"),
                _kv(context, "Created",
                    group.createdAt.toLocal().toString().split(' ').first),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("How booking works",
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: scheme.primary)),
                const SizedBox(height: 8),
                const Text(
                  "• Tap a green slot in the Schedule to book a resource.\n"
                  "• If a resource is already booked for that time, you join "
                  "the backup queue and are promoted automatically if the "
                  "main reservation is cancelled.\n"
                  "• Only you or the owner can cancel your reservation.\n"
                  "• Use the Dispatch tab for shared fleet status, hobbs/tach "
                  "and MX due, squawks, and student lesson packs.\n"
                  "• The owner (or a dispatcher) can mark aircraft unavailable "
                  "and update meters; grounding squawks block booking.",
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(k,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 12)),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
