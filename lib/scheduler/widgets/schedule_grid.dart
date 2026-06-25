import 'package:flutter/material.dart';
import 'package:flutter_material_design_icons/flutter_material_design_icons.dart';

import '../models/reservation.dart';
import '../models/schedulable_resource.dart';

/// A day timeline grid: resources are stacked vertically (rows), time runs
/// horizontally (columns of hours).
///
/// Colour key (per product spec):
///   * green  = available (free) slot on an in-service resource
///   * blue   = booked (a reservation occupies the slot)
///   * red    = unavailable (resource is out of service)
class ScheduleGrid extends StatefulWidget {
  final DateTime day;
  final List<SchedulableResource> resources;
  final List<Reservation> reservations;
  final String? currentUid;

  /// Called when a member taps an empty (green) part of an available
  /// resource row. [startHour] is the whole hour that was tapped.
  final void Function(SchedulableResource resource, DateTime startHour)
      onTapEmpty;

  /// Called when a reservation block is tapped.
  final void Function(Reservation reservation) onTapReservation;

  /// Called when a resource's left-hand label is tapped (owner management).
  final void Function(SchedulableResource resource)? onTapResource;

  const ScheduleGrid({
    super.key,
    required this.day,
    required this.resources,
    required this.reservations,
    required this.currentUid,
    required this.onTapEmpty,
    required this.onTapReservation,
    this.onTapResource,
  });

  static const double labelWidth = 120;
  static const double rowHeight = 64;
  static const double hourWidth = 64;
  static const double headerHeight = 28;
  static const int startHour = 0;
  static const int endHour = 24;

  @override
  State<ScheduleGrid> createState() => _ScheduleGridState();
}

class _ScheduleGridState extends State<ScheduleGrid> {
  final ScrollController _headerH = ScrollController();
  final ScrollController _bodyH = ScrollController();
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _headerH.addListener(() => _sync(_headerH, _bodyH));
    _bodyH.addListener(() => _sync(_bodyH, _headerH));
  }

  // Keep the header and body horizontal scroll positions locked together.
  void _sync(ScrollController from, ScrollController to) {
    if (_syncing) return;
    if (!to.hasClients || !from.hasClients) return;
    if (to.offset == from.offset) return;
    _syncing = true;
    to.jumpTo(from.offset.clamp(
      to.position.minScrollExtent,
      to.position.maxScrollExtent,
    ));
    _syncing = false;
  }

  @override
  void dispose() {
    _headerH.dispose();
    _bodyH.dispose();
    super.dispose();
  }

  int get _hours => ScheduleGrid.endHour - ScheduleGrid.startHour;
  double get _totalWidth => _hours * ScheduleGrid.hourWidth;
  DateTime get _dayStart =>
      DateTime(widget.day.year, widget.day.month, widget.day.day);

  String _hourLabel(int hour) {
    final h = hour % 24;
    if (h == 0) return "12a";
    if (h == 12) return "12p";
    if (h < 12) return "${h}a";
    return "${h - 12}p";
  }

  @override
  Widget build(BuildContext context) {
    if (widget.resources.isEmpty) {
      return const _GridEmptyState();
    }
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ----- Header: corner + hour labels -----
        Row(
          children: [
            Container(
              width: ScheduleGrid.labelWidth,
              height: ScheduleGrid.headerHeight,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                "Resource",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: scheme.primary,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _headerH,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: _totalWidth,
                  height: ScheduleGrid.headerHeight,
                  child: Row(
                    children: [
                      for (int h = ScheduleGrid.startHour;
                          h < ScheduleGrid.endHour;
                          h++)
                        Container(
                          width: ScheduleGrid.hourWidth,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 4),
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: scheme.outlineVariant,
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: Text(
                            _hourLabel(h),
                            style: TextStyle(
                                fontSize: 11, color: scheme.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const Divider(height: 1),
        // ----- Body: labels + timeline rows -----
        Expanded(
          child: SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children:
                      widget.resources.map(_buildLabelCell).toList(),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: _bodyH,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: _totalWidth,
                      child: Column(
                        children:
                            widget.resources.map(_buildTimelineRow).toList(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLabelCell(SchedulableResource resource) {
    final scheme = Theme.of(context).colorScheme;
    final cell = Container(
      width: ScheduleGrid.labelWidth,
      height: ScheduleGrid.rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 0.5),
          right: BorderSide(color: scheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            resource.isAircraft ? MdiIcons.airplane : MdiIcons.accountTie,
            size: 18,
            color: resource.available ? scheme.primary : Colors.red,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  resource.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                if (resource.identifier != null &&
                    resource.identifier!.isNotEmpty)
                  Text(
                    resource.identifier!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                  ),
                if (!resource.available)
                  const Text(
                    "Unavailable",
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.red,
                        fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          if (widget.onTapResource != null)
            Icon(Icons.more_vert, size: 16, color: scheme.outline),
        ],
      ),
    );
    if (widget.onTapResource == null) return cell;
    return InkWell(onTap: () => widget.onTapResource!(resource), child: cell);
  }

  Widget _buildTimelineRow(SchedulableResource resource) {
    final scheme = Theme.of(context).colorScheme;
    final available = resource.available;
    final resvs = widget.reservations
        .where((r) => r.resourceId == resource.id)
        .toList();
    final mains = resvs.where((r) => r.isMain).toList();
    final backups = resvs.where((r) => r.isBackup).toList();

    return SizedBox(
      width: _totalWidth,
      height: ScheduleGrid.rowHeight,
      child: Stack(
        children: [
          // Background hour cells (green available / red unavailable) with
          // tap-to-book on free space.
          Row(
            children: [
              for (int h = ScheduleGrid.startHour;
                  h < ScheduleGrid.endHour;
                  h++)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: available
                      ? () => widget.onTapEmpty(
                          resource, _dayStart.add(Duration(hours: h)))
                      : null,
                  child: Container(
                    width: ScheduleGrid.hourWidth,
                    height: ScheduleGrid.rowHeight,
                    decoration: BoxDecoration(
                      color: available
                          ? Colors.green.withValues(alpha: 0.16)
                          : Colors.red.withValues(alpha: 0.28),
                      border: Border(
                        left: BorderSide(
                            color: scheme.outlineVariant, width: 0.5),
                        bottom: BorderSide(
                            color: scheme.outlineVariant, width: 0.5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Main reservations (blue).
          for (final r in mains) _buildReservationBlock(r, isBackup: false),
          // Backup reservations (lighter blue, bottom strip).
          for (final r in backups) _buildReservationBlock(r, isBackup: true),
        ],
      ),
    );
  }

  Widget _buildReservationBlock(Reservation r, {required bool isBackup}) {
    final startOffsetHours =
        r.start.difference(_dayStart).inMinutes / 60.0 - ScheduleGrid.startHour;
    final durationHours = r.end.difference(r.start).inMinutes / 60.0;

    double left = startOffsetHours * ScheduleGrid.hourWidth;
    double width = durationHours * ScheduleGrid.hourWidth;
    // Clamp to the visible window.
    if (left < 0) {
      width += left;
      left = 0;
    }
    if (width <= 0) return const SizedBox.shrink();
    if (left + width > _totalWidth) {
      width = _totalWidth - left;
    }

    final mine =
        widget.currentUid != null && r.schedulerUid == widget.currentUid;
    final color =
        isBackup ? Colors.blue.withValues(alpha: 0.45) : Colors.blue.shade600;

    final block = Container(
      width: width,
      height: isBackup ? 18 : ScheduleGrid.rowHeight - 24,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: mine ? Colors.white : Colors.blue.shade900,
          width: mine ? 1.5 : 0.5,
        ),
      ),
      child: ClipRect(
        child: Row(
          children: [
            if (isBackup)
              const Icon(Icons.hourglass_bottom, size: 10, color: Colors.white),
            Expanded(
              child: Text(
                isBackup
                    ? "Backup ${r.backupOrder}: ${r.schedulerName}"
                    : r.schedulerName,
                maxLines: isBackup ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );

    return Positioned(
      left: left,
      top: isBackup ? ScheduleGrid.rowHeight - 22 : 4,
      child: GestureDetector(
        onTap: () => widget.onTapReservation(r),
        child: block,
      ),
    );
  }
}

class _GridEmptyState extends StatelessWidget {
  const _GridEmptyState();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(MdiIcons.airplaneOff, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            const Text("No resources yet",
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              "The scheduler owner can add aircraft and instructors to book.",
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.outline, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
