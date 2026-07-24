import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants.dart';
import '../utils/toast.dart';
import 'data/scheduler_repository.dart';
import 'models/lesson_pack.dart';
import 'models/schedulable_resource.dart';
import 'models/scheduler_member.dart';
import 'models/squawk.dart';

/// Club dispatch board: shared fleet status, squawks, and lesson packs.
///
/// Embedded in [SchedulerDetailScreen] as the Dispatch tab, or pushed as a
/// standalone screen via [embedded] == false.
class SchedulerDispatchScreen extends StatefulWidget {
  final String groupId;
  final bool canDispatch;
  final bool isOwner;
  final bool canUse;
  final bool embedded;

  const SchedulerDispatchScreen({
    super.key,
    required this.groupId,
    required this.canDispatch,
    required this.isOwner,
    required this.canUse,
    this.embedded = false,
  });

  @override
  State<SchedulerDispatchScreen> createState() =>
      _SchedulerDispatchScreenState();
}

class _SchedulerDispatchScreenState extends State<SchedulerDispatchScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.flight), text: "Fleet"),
            Tab(icon: Icon(Icons.report_problem_outlined), text: "Squawks"),
            Tab(icon: Icon(Icons.school_outlined), text: "Lessons"),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _FleetTab(
                groupId: widget.groupId,
                canDispatch: widget.canDispatch,
                canUse: widget.canUse,
              ),
              _SquawksTab(
                groupId: widget.groupId,
                canDispatch: widget.canDispatch,
                canUse: widget.canUse,
              ),
              _LessonPacksTab(
                groupId: widget.groupId,
                isOwner: widget.isOwner,
                canUse: widget.canUse,
              ),
            ],
          ),
        ),
      ],
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text("Dispatch"),
      ),
      body: body,
    );
  }
}

// ---------------------------------------------------------------------------
// Fleet
// ---------------------------------------------------------------------------

class _FleetTab extends StatelessWidget {
  final String groupId;
  final bool canDispatch;
  final bool canUse;
  const _FleetTab({
    required this.groupId,
    required this.canDispatch,
    required this.canUse,
  });

  @override
  Widget build(BuildContext context) {
    if (!canUse) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "Join this scheduler to see the shared fleet status board.",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return StreamBuilder<List<SchedulableResource>>(
      stream: SchedulerRepository.instance.watchResources(groupId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final aircraft =
            (snap.data ?? const []).where((r) => r.isAircraft).toList();
        if (aircraft.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                "No aircraft in this fleet yet.\n"
                "The owner can add aircraft from the Schedule tab.",
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          itemCount: aircraft.length,
          itemBuilder: (context, i) {
            final r = aircraft[i];
            return _FleetAircraftCard(
              groupId: groupId,
              resource: r,
              canDispatch: canDispatch,
              canUse: canUse,
            );
          },
        );
      },
    );
  }
}

class _FleetAircraftCard extends StatelessWidget {
  final String groupId;
  final SchedulableResource resource;
  final bool canDispatch;
  final bool canUse;
  const _FleetAircraftCard({
    required this.groupId,
    required this.resource,
    required this.canDispatch,
    required this.canUse,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StreamBuilder<List<Squawk>>(
      stream: SchedulerRepository.instance
          .watchOpenSquawksForResource(groupId, resource.id),
      builder: (context, sSnap) {
        final open = sSnap.data ?? const [];
        final grounding = open.where((s) => s.isGrounding).length;
        final caution = open.where((s) => s.severity == SquawkSeverity.caution).length;

        Color statusColor;
        String statusLabel;
        if (!resource.available || grounding > 0) {
          statusColor = Colors.red;
          statusLabel = grounding > 0 ? "GROUNDED" : "OUT OF SERVICE";
        } else if (resource.hundredHourOverdue ||
            resource.mxDueSoon(warnDays: 0)) {
          statusColor = Colors.orange;
          statusLabel = "MX DUE";
        } else if (resource.mxDueSoon() || caution > 0) {
          statusColor = Colors.amber.shade800;
          statusLabel = "ATTENTION";
        } else {
          statusColor = Colors.green;
          statusLabel = "READY";
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openDetail(context),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.flight, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              resource.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                            if (resource.identifier != null)
                              Text(
                                resource.identifier!,
                                style: TextStyle(
                                    fontSize: 12, color: scheme.outline),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: statusColor),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _meterChip("Hobbs", resource.hobbs),
                      _meterChip("Tach", resource.tach),
                      if (resource.annualDue != null)
                        _dateChip("Annual", resource.annualDue!),
                      if (resource.hundredHourDueHobbs != null)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            "100hr @ ${resource.hundredHourDueHobbs!.toStringAsFixed(1)}",
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      if (open.isNotEmpty)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(Icons.report_problem,
                              size: 16,
                              color: grounding > 0
                                  ? Colors.red
                                  : scheme.onSurfaceVariant),
                          label: Text(
                            "${open.length} open squawk${open.length == 1 ? '' : 's'}",
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                  if (resource.mxNotes != null &&
                      resource.mxNotes!.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      resource.mxNotes!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _meterChip(String label, double? value) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(
        value == null ? "$label —" : "$label ${value.toStringAsFixed(1)}",
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  Widget _dateChip(String label, DateTime d) {
    final overdue = d.isBefore(DateTime.now());
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: overdue ? Colors.orange.withValues(alpha: 0.2) : null,
      label: Text(
        "$label ${_fmtShortDate(d)}${overdue ? ' (due)' : ''}",
        style: TextStyle(
            fontSize: 11, color: overdue ? Colors.orange.shade900 : null),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AircraftDispatchSheet(
        groupId: groupId,
        resource: resource,
        canDispatch: canDispatch,
        canUse: canUse,
      ),
    );
  }
}

class _AircraftDispatchSheet extends StatelessWidget {
  final String groupId;
  final SchedulableResource resource;
  final bool canDispatch;
  final bool canUse;
  const _AircraftDispatchSheet({
    required this.groupId,
    required this.resource,
    required this.canDispatch,
    required this.canUse,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(resource.name,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              if (resource.identifier != null)
                Text(resource.identifier!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.outline)),
              const SizedBox(height: 12),
              _kv("Hobbs", resource.hobbs?.toStringAsFixed(1) ?? "—"),
              _kv("Tach", resource.tach?.toStringAsFixed(1) ?? "—"),
              _kv("Annual due",
                  resource.annualDue == null
                      ? "—"
                      : _fmtShortDate(resource.annualDue!)),
              _kv(
                  "100-hour due (hobbs)",
                  resource.hundredHourDueHobbs?.toStringAsFixed(1) ?? "—"),
              _kv(
                  "Transponder due",
                  resource.transponderDue == null
                      ? "—"
                      : _fmtShortDate(resource.transponderDue!)),
              _kv(
                  "ELT due",
                  resource.eltDue == null
                      ? "—"
                      : _fmtShortDate(resource.eltDue!)),
              if (resource.mxNotes != null && resource.mxNotes!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(resource.mxNotes!),
                ),
              const SizedBox(height: 16),
              if (canDispatch) ...[
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _editStatus(context);
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text("Update meters / MX"),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Available for booking"),
                  value: resource.available,
                  onChanged: (v) async {
                    Navigator.pop(context);
                    try {
                      await SchedulerRepository.instance
                          .setResourceAvailability(groupId, resource.id, v);
                    } catch (e) {
                      if (context.mounted) {
                        Toast.showToast(context, "Update failed: $e",
                            const Icon(Icons.error, color: Colors.red), 4);
                      }
                    }
                  },
                ),
              ],
              if (canUse)
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _fileSquawk(context);
                  },
                  icon: const Icon(Icons.report_problem_outlined),
                  label: const Text("File squawk"),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 150, child: Text(k, style: const TextStyle(fontSize: 13))),
          Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Future<void> _editStatus(BuildContext context) async {
    final hobbsCtrl =
        TextEditingController(text: resource.hobbs?.toStringAsFixed(1) ?? "");
    final tachCtrl =
        TextEditingController(text: resource.tach?.toStringAsFixed(1) ?? "");
    final hundredCtrl = TextEditingController(
        text: resource.hundredHourDueHobbs?.toStringAsFixed(1) ?? "");
    final notesCtrl = TextEditingController(text: resource.mxNotes ?? "");
    DateTime? annualDue = resource.annualDue;
    DateTime? xpdrDue = resource.transponderDue;
    DateTime? eltDue = resource.eltDue;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text("Update ${resource.name}"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: hobbsCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                    ],
                    decoration: const InputDecoration(
                      labelText: "Hobbs",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: tachCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                    ],
                    decoration: const InputDecoration(
                      labelText: "Tach",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: hundredCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                    ],
                    decoration: const InputDecoration(
                      labelText: "100-hour due (hobbs)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(annualDue == null
                        ? "Annual due: not set"
                        : "Annual due: ${_fmtShortDate(annualDue!)}"),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: annualDue ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) setLocal(() => annualDue = picked);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(xpdrDue == null
                        ? "Transponder due: not set"
                        : "Transponder due: ${_fmtShortDate(xpdrDue!)}"),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: xpdrDue ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) setLocal(() => xpdrDue = picked);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(eltDue == null
                        ? "ELT due: not set"
                        : "ELT due: ${_fmtShortDate(eltDue!)}"),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: eltDue ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now().add(const Duration(days: 3650)),
                      );
                      if (picked != null) setLocal(() => eltDue = picked);
                    },
                  ),
                  TextField(
                    controller: notesCtrl,
                    maxLength: 500,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: "MX notes",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
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

    double? parse(String s) {
      final t = s.trim();
      if (t.isEmpty) return null;
      return double.tryParse(t);
    }

    try {
      await SchedulerRepository.instance.updateResourceDispatchStatus(
        groupId,
        resource.id,
        hobbs: parse(hobbsCtrl.text),
        tach: parse(tachCtrl.text),
        hundredHourDueHobbs: parse(hundredCtrl.text),
        annualDue: annualDue,
        transponderDue: xpdrDue,
        eltDue: eltDue,
        mxNotes: notesCtrl.text,
        clearHundredHourDueHobbs: hundredCtrl.text.trim().isEmpty,
      );
      if (context.mounted) {
        Toast.showToast(context, "Fleet status updated",
            const Icon(Icons.check, color: Colors.green), 2);
      }
    } catch (e) {
      if (context.mounted) {
        Toast.showToast(context, "Could not update: $e",
            const Icon(Icons.error, color: Colors.red), 4);
      }
    }
  }

  Future<void> _fileSquawk(BuildContext context) async {
    await showFileSquawkDialog(context, groupId, resource);
  }
}

// ---------------------------------------------------------------------------
// Squawks
// ---------------------------------------------------------------------------

class _SquawksTab extends StatelessWidget {
  final String groupId;
  final bool canDispatch;
  final bool canUse;
  const _SquawksTab({
    required this.groupId,
    required this.canDispatch,
    required this.canUse,
  });

  @override
  Widget build(BuildContext context) {
    if (!canUse) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text("Join this scheduler to view and file squawks.",
              textAlign: TextAlign.center),
        ),
      );
    }

    return StreamBuilder<List<Squawk>>(
      stream: SchedulerRepository.instance.watchSquawks(groupId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final all = snap.data ?? const [];
        final open = all.where((s) => s.isOpen).toList();
        final resolved = all.where((s) => !s.isOpen).toList();

        return Column(
          children: [
            if (canUse)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: TextButton.icon(
                    onPressed: () => _pickAircraftAndFile(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text("File squawk"),
                  ),
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                children: [
                  _section(context, "Open (${open.length})"),
                  if (open.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text("No open squawks."),
                    )
                  else
                    ...open.map((s) => _squawkTile(context, s)),
                  if (resolved.isNotEmpty) ...[
                    _section(context, "Resolved (${resolved.length})"),
                    ...resolved.take(20).map((s) => _squawkTile(context, s)),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _section(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
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

  Widget _squawkTile(BuildContext context, Squawk s) {
    final scheme = Theme.of(context).colorScheme;
    Color sevColor;
    switch (s.severity) {
      case SquawkSeverity.grounding:
        sevColor = Colors.red;
        break;
      case SquawkSeverity.caution:
        sevColor = Colors.orange;
        break;
      case SquawkSeverity.info:
        sevColor = scheme.outline;
        break;
    }
    return Card(
      child: ListTile(
        leading: Icon(Icons.report_problem, color: sevColor),
        title: Text(s.title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          "${s.resourceName} · ${squawkSeverityLabel(s.severity)}"
          "${s.description.isEmpty ? '' : '\n${s.description}'}"
          "\nby ${s.reportedByName}",
        ),
        isThreeLine: true,
        trailing: s.isOpen
            ? IconButton(
                tooltip: "Resolve",
                icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                onPressed: () async {
                  try {
                    await SchedulerRepository.instance.resolveSquawk(groupId, s);
                    if (context.mounted) {
                      Toast.showToast(context, "Squawk resolved",
                          const Icon(Icons.check, color: Colors.green), 2);
                    }
                  } catch (e) {
                    if (context.mounted) {
                      Toast.showToast(context, "Could not resolve: $e",
                          const Icon(Icons.error, color: Colors.red), 4);
                    }
                  }
                },
              )
            : (canDispatch
                ? IconButton(
                    tooltip: "Delete",
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () async {
                      try {
                        await SchedulerRepository.instance
                            .deleteSquawk(groupId, s.id);
                      } catch (e) {
                        if (context.mounted) {
                          Toast.showToast(context, "Could not delete: $e",
                              const Icon(Icons.error, color: Colors.red), 4);
                        }
                      }
                    },
                  )
                : null),
      ),
    );
  }

  Future<void> _pickAircraftAndFile(BuildContext context) async {
    final resources =
        await SchedulerRepository.instance.watchResources(groupId).first;
    final aircraft = resources.where((r) => r.isAircraft).toList();
    if (aircraft.isEmpty) {
      if (context.mounted) {
        Toast.showToast(context, "Add an aircraft before filing a squawk",
            const Icon(Icons.info, color: Colors.orange), 3);
      }
      return;
    }
    if (!context.mounted) return;
    SchedulableResource? picked =
        aircraft.length == 1 ? aircraft.first : null;
    picked ??= await showDialog<SchedulableResource>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("Which aircraft?"),
        children: [
          for (final a in aircraft)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, a),
              child: Text(a.identifier == null
                  ? a.name
                  : "${a.name} (${a.identifier})"),
            ),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    await showFileSquawkDialog(context, groupId, picked);
  }
}

Future<void> showFileSquawkDialog(
  BuildContext context,
  String groupId,
  SchedulableResource resource,
) async {
  final titleCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  SquawkSeverity severity = SquawkSeverity.caution;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          title: Text("Squawk on ${resource.name}"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: "Title",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: "Description",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<SquawkSeverity>(
                  initialValue: severity,
                  decoration: const InputDecoration(
                    labelText: "Severity",
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final s in SquawkSeverity.values)
                      DropdownMenuItem(
                        value: s,
                        child: Text(squawkSeverityLabel(s)),
                      ),
                  ],
                  onChanged: (v) =>
                      setLocal(() => severity = v ?? SquawkSeverity.caution),
                ),
                if (severity == SquawkSeverity.grounding)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      "Grounding squawks block booking and show as GROUNDED "
                      "on the fleet board.",
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(ctx).colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Cancel")),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("File")),
          ],
        );
      });
    },
  );
  if (ok != true || !context.mounted) return;
  try {
    await SchedulerRepository.instance.createSquawk(
      groupId,
      resource: resource,
      title: titleCtrl.text,
      description: descCtrl.text,
      severity: severity,
    );
    if (context.mounted) {
      Toast.showToast(context, "Squawk filed",
          const Icon(Icons.check, color: Colors.green), 2);
    }
  } catch (e) {
    if (context.mounted) {
      Toast.showToast(context, "Could not file squawk: $e",
          const Icon(Icons.error, color: Colors.red), 4);
    }
  }
}

// ---------------------------------------------------------------------------
// Lesson packs
// ---------------------------------------------------------------------------

class _LessonPacksTab extends StatelessWidget {
  final String groupId;
  final bool isOwner;
  final bool canUse;
  const _LessonPacksTab({
    required this.groupId,
    required this.isOwner,
    required this.canUse,
  });

  @override
  Widget build(BuildContext context) {
    if (!canUse) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text("Join this scheduler to see lesson packs.",
              textAlign: TextAlign.center),
        ),
      );
    }

    return StreamBuilder<List<LessonPack>>(
      stream: SchedulerRepository.instance.watchLessonPacks(groupId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final packs = snap.data ?? const [];
        return Column(
          children: [
            if (isOwner)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: TextButton.icon(
                    onPressed: () => _createPack(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text("New lesson pack"),
                  ),
                ),
              ),
            Expanded(
              child: packs.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          "No lesson packs yet.\n"
                          "Owners can create prepaid hour blocks for students.",
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      itemCount: packs.length,
                      itemBuilder: (context, i) =>
                          _packTile(context, packs[i]),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _packTile(BuildContext context, LessonPack p) {
    final scheme = Theme.of(context).colorScheme;
    final progress =
        p.totalHours <= 0 ? 0.0 : (p.hoursUsed / p.totalHours).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(p.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    lessonPackStatusToString(p.status),
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
            Text(
              "${p.studentName}"
              "${p.instructorName == null ? '' : ' · CFI ${p.instructorName}'}",
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 4),
            Text(
              "${p.hoursRemaining.toStringAsFixed(1)} of "
              "${p.totalHours.toStringAsFixed(1)} hrs remaining"
              " (${p.hoursUsed.toStringAsFixed(1)} used)",
              style: const TextStyle(fontSize: 12),
            ),
            if (p.isActive) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: () => _logHours(context, p),
                    child: const Text("Log hours"),
                  ),
                  if (isOwner) ...[
                    TextButton(
                      onPressed: () async {
                        try {
                          await SchedulerRepository.instance.setLessonPackStatus(
                              groupId, p.id, LessonPackStatus.cancelled);
                        } catch (e) {
                          if (context.mounted) {
                            Toast.showToast(context, "$e",
                                const Icon(Icons.error, color: Colors.red), 4);
                          }
                        }
                      },
                      child: const Text("Cancel pack"),
                    ),
                    IconButton(
                      tooltip: "Delete",
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () async {
                        try {
                          await SchedulerRepository.instance
                              .deleteLessonPack(groupId, p.id);
                        } catch (e) {
                          if (context.mounted) {
                            Toast.showToast(context, "$e",
                                const Icon(Icons.error, color: Colors.red), 4);
                          }
                        }
                      },
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _logHours(BuildContext context, LessonPack p) async {
    final ctrl = TextEditingController(text: "1.0");
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Log lesson hours"),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: "Hours",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Log")),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final hours = double.tryParse(ctrl.text.trim());
    if (hours == null || hours <= 0) {
      Toast.showToast(context, "Enter a positive number of hours",
          const Icon(Icons.info, color: Colors.orange), 3);
      return;
    }
    try {
      await SchedulerRepository.instance
          .logLessonPackHours(groupId, p.id, hours: hours);
      if (context.mounted) {
        Toast.showToast(context, "Logged ${hours.toStringAsFixed(1)} hrs",
            const Icon(Icons.check, color: Colors.green), 2);
      }
    } catch (e) {
      if (context.mounted) {
        Toast.showToast(context, "Could not log hours: $e",
            const Icon(Icons.error, color: Colors.red), 4);
      }
    }
  }

  Future<void> _createPack(BuildContext context) async {
    final members =
        await SchedulerRepository.instance.watchMembers(groupId).first;
    final students = members
        .where((m) => m.isActive && (m.isStudent || !m.isOwner))
        .toList();
    final instructors =
        members.where((m) => m.isActive && m.isInstructor).toList();
    if (students.isEmpty) {
      if (context.mounted) {
        Toast.showToast(
            context,
            "Add and approve members first, then set a student role on Members",
            const Icon(Icons.info, color: Colors.orange),
            4);
      }
      return;
    }

    final nameCtrl = TextEditingController(text: "10-hour block");
    final hoursCtrl = TextEditingController(text: "10");
    SchedulerMember student = students.first;
    SchedulerMember? instructor =
        instructors.isEmpty ? null : instructors.first;

    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text("New lesson pack"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    maxLength: 60,
                    decoration: const InputDecoration(
                      labelText: "Pack name",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: hoursCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: "Total hours",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<SchedulerMember>(
                    initialValue: student,
                    decoration: const InputDecoration(
                      labelText: "Student",
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final m in students)
                        DropdownMenuItem(value: m, child: Text(m.displayName)),
                    ],
                    onChanged: (v) => setLocal(() => student = v ?? student),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<SchedulerMember?>(
                    initialValue: instructor,
                    decoration: const InputDecoration(
                      labelText: "Instructor (optional)",
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text("None")),
                      for (final m in instructors)
                        DropdownMenuItem(value: m, child: Text(m.displayName)),
                    ],
                    onChanged: (v) => setLocal(() => instructor = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("Cancel")),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("Create")),
            ],
          );
        });
      },
    );
    if (ok != true || !context.mounted) return;
    final hours = double.tryParse(hoursCtrl.text.trim());
    if (hours == null || hours <= 0) {
      Toast.showToast(context, "Enter total hours greater than zero",
          const Icon(Icons.info, color: Colors.orange), 3);
      return;
    }
    try {
      await SchedulerRepository.instance.createLessonPack(
        groupId,
        name: nameCtrl.text,
        totalHours: hours,
        studentUid: student.uid,
        studentName: student.displayName,
        instructorUid: instructor?.uid,
        instructorName: instructor?.displayName,
      );
      if (context.mounted) {
        Toast.showToast(context, "Lesson pack created",
            const Icon(Icons.check, color: Colors.green), 2);
      }
    } catch (e) {
      if (context.mounted) {
        Toast.showToast(context, "Could not create pack: $e",
            const Icon(Icons.error, color: Colors.red), 4);
      }
    }
  }
}

String _fmtShortDate(DateTime d) {
  const months = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
  ];
  return "${months[d.month - 1]} ${d.day}, ${d.year}";
}
