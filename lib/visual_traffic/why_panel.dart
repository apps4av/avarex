import 'package:avaremp/visual_traffic/decision_board.dart';
import 'package:flutter/material.dart';

/// A small window on the camera screen that says, in words, what the
/// detector is doing and why it kept or threw out each target.
///
/// Rebuilds whenever its parent does, so the parent just keeps the
/// [DecisionBoard] up to date.
class WhyPanel extends StatefulWidget {
  const WhyPanel({super.key, required this.board, required this.onClose});

  final DecisionBoard board;
  final VoidCallback onClose;

  @override
  State<WhyPanel> createState() => _WhyPanelState();
}

enum _Tab { targets, sensors, adsb, history }

class _WhyPanelState extends State<WhyPanel> {
  _Tab _tab = _Tab.targets;

  static Color _color(Tone tone) {
    switch (tone) {
      case Tone.alert:
        return const Color(0xFFFF6B6B);
      case Tone.caution:
        return const Color(0xFFFFD60A);
      case Tone.good:
        return const Color(0xFF7CE38B);
      case Tone.warn:
        return const Color(0xFFFFA94D);
      case Tone.info:
        return Colors.white;
      case Tone.muted:
        return Colors.white54;
    }
  }

  static String _clock(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final DecisionBoard board = widget.board;
    final double maxHeight = (MediaQuery.of(context).size.height * 0.42).clamp(140.0, 260.0);
    final List<Widget> rows = [];
    switch (_tab) {
      case _Tab.targets:
        rows.addAll(board.targets.map(_line));
      case _Tab.sensors:
        rows.addAll(board.sensors.map(_line));
      case _Tab.adsb:
        rows.addAll(board.adsb.isEmpty
            ? [_line(const BoardLine('Nothing to report.', Tone.muted))]
            : board.adsb.map(_line));
      case _Tab.history:
        final List<BoardEvent> recent = board.events.reversed.take(30).toList();
        rows.addAll(recent.isEmpty
            ? [_line(const BoardLine('No decisions yet.', Tone.muted))]
            : recent.map((BoardEvent e) => _line(BoardLine('${_clock(e.time)}  ${e.text}', e.tone))));
    }
    return Material(
      color: Colors.black.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      children: [
                        _chip('Targets', _Tab.targets),
                        _chip('Sensors', _Tab.sensors),
                        _chip('ADS-B', _Tab.adsb),
                        _chip('History', _Tab.history),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                  tooltip: 'Close',
                  onPressed: widget.onClose,
                ),
              ],
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                shrinkWrap: true,
                children: rows,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, _Tab tab) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: _tab == tab,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => setState(() => _tab = tab),
      ),
    );
  }

  Widget _line(BoardLine line) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        line.text,
        style: TextStyle(color: _color(line.tone), fontSize: 11.5, height: 1.25),
      ),
    );
  }
}
