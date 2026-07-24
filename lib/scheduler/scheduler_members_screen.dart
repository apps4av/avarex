import 'package:flutter/material.dart';

import '../constants.dart';
import '../utils/toast.dart';
import 'data/scheduler_repository.dart';
import 'models/scheduler_member.dart';

/// Members list with owner-only approve/remove controls and club-role
/// assignment (student → instructor).
///
/// Can be used as a top-level screen or embedded inside a TabBarView via the
/// [embedded] flag.
class SchedulerMembersScreen extends StatelessWidget {
  final String groupId;
  final bool isOwner;
  final bool embedded;

  const SchedulerMembersScreen({
    super.key,
    required this.groupId,
    required this.isOwner,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context) {
    final body = StreamBuilder<List<SchedulerMember>>(
      stream: SchedulerRepository.instance.watchMembers(groupId),
      builder: (context, allSnap) {
        if (allSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (allSnap.hasError) {
          final err = allSnap.error.toString().toLowerCase();
          final isPrivate = err.contains("permission");
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                isPrivate
                    ? "Member list is private. Join this scheduler to see who else is here."
                    : "Couldn't load members: ${allSnap.error}",
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final all = allSnap.data ?? const [];
        final active = all.where((m) => m.isActive).toList();
        final pending = all.where((m) => m.isPending).toList();
        final instructors = active.where((m) => m.isInstructor).toList();
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            if (isOwner && pending.isNotEmpty) ...[
              _header(context, "Pending requests (${pending.length})"),
              ...pending.map((m) => _memberTile(
                    context,
                    m,
                    instructors: instructors,
                    actions: [
                      IconButton(
                        tooltip: "Approve",
                        icon: const Icon(Icons.check_circle,
                            color: Colors.green),
                        onPressed: () => _approve(context, m),
                      ),
                      IconButton(
                        tooltip: "Reject",
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        onPressed: () => _remove(context, m),
                      ),
                    ],
                  )),
              const Divider(),
            ],
            _header(context, "Members (${active.length})"),
            if (active.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text("No members yet")),
              )
            else
              ...active.map(
                (m) => _memberTile(
                  context,
                  m,
                  instructors: instructors,
                  actions: isOwner && !m.isOwner
                      ? [
                          IconButton(
                            tooltip: "Club role",
                            icon: const Icon(Icons.badge_outlined),
                            onPressed: () =>
                                _editClubRole(context, m, instructors),
                          ),
                          IconButton(
                            tooltip: "Remove",
                            icon: const Icon(Icons.person_remove,
                                color: Colors.red),
                            onPressed: () => _confirmRemove(context, m),
                          ),
                        ]
                      : (isOwner && m.isOwner
                          ? [
                              IconButton(
                                tooltip: "Club role",
                                icon: const Icon(Icons.badge_outlined),
                                onPressed: () =>
                                    _editClubRole(context, m, instructors),
                              ),
                            ]
                          : null),
                ),
              ),
          ],
        );
      },
    );

    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text("Members"),
      ),
      body: body,
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

  Widget _memberTile(
    BuildContext context,
    SchedulerMember m, {
    required List<SchedulerMember> instructors,
    List<Widget>? actions,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: scheme.primaryContainer,
        child: Text(
          m.displayName.isEmpty
              ? "?"
              : m.displayName.substring(0, 1).toUpperCase(),
          style: TextStyle(
              color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              m.displayName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (m.isOwner)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Chip(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                label: Text("Owner", style: TextStyle(fontSize: 10)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Chip(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              label: Text(clubRoleLabel(m.clubRole),
                  style: const TextStyle(fontSize: 10)),
            ),
          ),
        ],
      ),
      subtitle: Text(
        [
          "joined ${m.joinedAt.toLocal().toString().split(' ').first}",
          if (m.isStudent && m.assignedInstructorName != null)
            "CFI: ${m.assignedInstructorName}",
        ].join(" · "),
        style: TextStyle(fontSize: 11, color: scheme.outline),
      ),
      trailing: actions == null
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: actions),
    );
  }

  Future<void> _editClubRole(
    BuildContext context,
    SchedulerMember m,
    List<SchedulerMember> instructors,
  ) async {
    ClubRole role = m.clubRole;
    SchedulerMember? assigned = instructors
        .cast<SchedulerMember?>()
        .firstWhere(
          (i) => i?.uid == m.assignedInstructorUid,
          orElse: () => null,
        );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text("Role for ${m.displayName}"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<ClubRole>(
                  initialValue: role,
                  decoration: const InputDecoration(
                    labelText: "Club role",
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final r in ClubRole.values)
                      DropdownMenuItem(
                          value: r, child: Text(clubRoleLabel(r))),
                  ],
                  onChanged: (v) => setLocal(() => role = v ?? role),
                ),
                if (role == ClubRole.student) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<SchedulerMember?>(
                    initialValue: assigned,
                    decoration: const InputDecoration(
                      labelText: "Assigned instructor",
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text("None")),
                      for (final i in instructors.where((x) => x.uid != m.uid))
                        DropdownMenuItem(
                            value: i, child: Text(i.displayName)),
                    ],
                    onChanged: (v) => setLocal(() => assigned = v),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("Cancel")),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("Save")),
            ],
          );
        });
      },
    );
    if (ok != true || !context.mounted) return;
    try {
      await SchedulerRepository.instance.updateMemberClubRole(
        groupId,
        m.uid,
        clubRole: role,
        assignedInstructorUid: assigned?.uid,
        assignedInstructorName: assigned?.displayName,
      );
      if (context.mounted) {
        Toast.showToast(context, "Updated ${m.displayName}",
            const Icon(Icons.check, color: Colors.green), 2);
      }
    } catch (e) {
      if (context.mounted) {
        Toast.showToast(context, "Could not update role: $e",
            const Icon(Icons.error, color: Colors.red), 4);
      }
    }
  }

  Future<void> _approve(BuildContext context, SchedulerMember m) async {
    try {
      await SchedulerRepository.instance.approveMember(groupId, m.uid);
      if (context.mounted) {
        Toast.showToast(context, "Approved ${m.displayName}",
            const Icon(Icons.check, color: Colors.green), 2);
      }
    } catch (e) {
      if (context.mounted) {
        Toast.showToast(context, "Could not approve: $e",
            const Icon(Icons.error, color: Colors.red), 4);
      }
    }
  }

  Future<void> _remove(BuildContext context, SchedulerMember m) async {
    try {
      await SchedulerRepository.instance.removeMember(groupId, m.uid);
    } catch (e) {
      if (context.mounted) {
        Toast.showToast(context, "Could not remove: $e",
            const Icon(Icons.error, color: Colors.red), 4);
      }
    }
  }

  Future<void> _confirmRemove(BuildContext context, SchedulerMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Remove ${m.displayName}?"),
        content: const Text("They'll be removed from this scheduler."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Remove"),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _remove(context, m);
    }
  }
}
