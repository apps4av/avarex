import 'package:flutter/material.dart';

import '../constants.dart';
import '../utils/toast.dart';
import 'data/scheduler_repository.dart';
import 'models/scheduler_group.dart';

/// Owner-only screen to configure booking rules for a scheduler:
///   * how many reservations a member may hold at a time
///   * how many of those may fall on a weekend
///
/// A value of 0 means "unlimited".
class SchedulerAdminScreen extends StatefulWidget {
  final SchedulerGroup group;
  const SchedulerAdminScreen({super.key, required this.group});

  @override
  State<SchedulerAdminScreen> createState() => _SchedulerAdminScreenState();
}

class _SchedulerAdminScreenState extends State<SchedulerAdminScreen> {
  late int _maxPerMember;
  late int _maxWeekend;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _maxPerMember = widget.group.maxReservationsPerMember;
    _maxWeekend = widget.group.maxWeekendReservations;
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await SchedulerRepository.instance.updateBookingRules(
        widget.group.id,
        maxReservationsPerMember: _maxPerMember,
        maxWeekendReservations: _maxWeekend,
      );
      if (!mounted) return;
      Toast.showToast(context, "Booking rules saved",
          const Icon(Icons.check, color: Colors.green), 2);
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        Toast.showToast(context, "Could not save rules: $e",
            const Icon(Icons.error, color: Colors.red), 4);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text("Booking Rules"),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text("Private scheduler"),
                subtitle: const Text(
                    "All schedulers are private. Members must be approved "
                    "before they can book."),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "RESERVATION LIMITS",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            _StepperTile(
              icon: Icons.event_note,
              title: "Reservations per member",
              subtitle:
                  "Most current/upcoming reservations a member can hold at once.",
              value: _maxPerMember,
              onChanged: (v) => setState(() => _maxPerMember = v),
            ),
            _StepperTile(
              icon: Icons.weekend,
              title: "Weekend reservations",
              subtitle:
                  "Most weekend (Sat/Sun) reservations a member can hold at once.",
              value: _maxWeekend,
              onChanged: (v) => setState(() => _maxWeekend = v),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                "Set a value to 0 for unlimited. The scheduler owner is exempt "
                "from these limits.",
                style: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text("Save rules"),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepperTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int value;
  final ValueChanged<int> onChanged;

  const _StepperTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.outline)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: value <= 0 ? null : () => onChanged(value - 1),
            ),
            SizedBox(
              width: 56,
              child: Text(
                value == 0 ? "∞" : "$value",
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: value >= 99 ? null : () => onChanged(value + 1),
            ),
          ],
        ),
      ),
    );
  }
}
