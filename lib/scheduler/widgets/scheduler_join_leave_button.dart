import 'package:flutter/material.dart';

import '../data/scheduler_repository.dart';
import '../models/scheduler_group.dart';
import '../models/scheduler_member.dart';

/// Smart button that switches between Join / Requested / Leave / Owner-only
/// based on the user's current membership in a scheduler group.
class SchedulerJoinLeaveButton extends StatefulWidget {
  final SchedulerGroup group;
  final SchedulerMember? membership;
  final void Function(String message)? onMessage;

  const SchedulerJoinLeaveButton({
    super.key,
    required this.group,
    required this.membership,
    this.onMessage,
  });

  @override
  State<SchedulerJoinLeaveButton> createState() =>
      _SchedulerJoinLeaveButtonState();
}

class _SchedulerJoinLeaveButtonState extends State<SchedulerJoinLeaveButton> {
  bool _busy = false;

  void _say(String m) {
    if (!mounted) return;
    final cb = widget.onMessage;
    if (cb != null) cb(m);
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    try {
      final status =
          await SchedulerRepository.instance.joinGroup(widget.group.id);
      _say(status == SchedulerMemberStatus.pending
          ? "Request sent. Waiting for owner approval."
          : "Joined ${widget.group.name}");
    } catch (e) {
      _say("Could not join: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    setState(() => _busy = true);
    try {
      await SchedulerRepository.instance.leaveGroup(widget.group.id);
      _say("Left ${widget.group.name}");
    } catch (e) {
      _say("Could not leave: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const SizedBox(
        width: 28,
        height: 28,
        child: Padding(
          padding: EdgeInsets.all(4),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final m = widget.membership;
    if (m == null) {
      return FilledButton.icon(
        onPressed: _join,
        icon: Icon(widget.group.isPrivate ? Icons.lock_outline : Icons.add),
        label: Text(widget.group.isPrivate ? "Request to Join" : "Join"),
      );
    }
    if (m.isOwner) {
      return const Chip(
        avatar: Icon(Icons.star, size: 16),
        label: Text("Owner"),
      );
    }
    if (m.isPending) {
      return OutlinedButton.icon(
        onPressed: _leave,
        icon: const Icon(Icons.hourglass_empty),
        label: const Text("Requested"),
      );
    }
    return OutlinedButton.icon(
      onPressed: _leave,
      icon: const Icon(Icons.logout),
      label: const Text("Leave"),
    );
  }
}
