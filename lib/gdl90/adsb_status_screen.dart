import 'package:avaremp/gdl90/adsb_status.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';

import '../constants.dart';

/// Full screen showing live ADS-B receiver status (from the GDL90 heartbeat and
/// FIS-B ground uplinks) plus a scrolling log of the last received messages.
/// Tap a message to expand its decoded fields; pause/resume freezes the log.
/// Pushed from the ADSB instrument tile; the AppBar provides the back button.
class AdsbStatusScreen extends StatefulWidget {
  const AdsbStatusScreen({super.key});

  @override
  State<AdsbStatusScreen> createState() => _AdsbStatusScreenState();
}

class _AdsbStatusScreenState extends State<AdsbStatusScreen> {

  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Run the log live while the screen is open.
    Storage().adsbStatus.logPaused = false;
  }

  @override
  void dispose() {
    // Leaving the screen pauses the message log so it stops scrolling/updating.
    Storage().adsbStatus.logPaused = true;
    _scroll.dispose();
    super.dispose();
  }

  Widget _statusTile(IconData icon, String title, String value, Color color) {
    return Card(
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: color),
        title: Text(title),
        trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _boolTile(IconData icon, String title, bool value) {
    return _statusTile(icon, title, value ? "Yes" : "No",
        value ? Colors.green : Colors.grey);
  }

  String _formatTime(DateTime t) {
    String two(int v) => v < 10 ? "0$v" : "$v";
    return "${two(t.hour)}:${two(t.minute)}:${two(t.second)}";
  }

  void _showFilters() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final AdsbStatus s = Storage().adsbStatus;
            return SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text("Show message types",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  for (final entry in AdsbStatus.filterTypes.entries)
                    CheckboxListTile(
                      dense: true,
                      title: Text(entry.value),
                      value: s.enabledTypes.contains(entry.key),
                      onChanged: (v) {
                        s.setTypeEnabled(entry.key, v ?? false);
                        setSheetState(() {});
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text("ADS-B Status"),
      ),
      body: Column(
        children: [
          // Live receiver status
          AnimatedBuilder(
            animation: Listenable.merge(
                [Storage().timeChange, Storage().adsbStatus.change]),
            builder: (context, _) {
              final AdsbStatus s = Storage().adsbStatus;
              final Color connColor = !s.connected
                  ? Colors.grey
                  : (!s.gpsValid ? Colors.amber : Colors.green);
              return Column(
                children: [
                  _statusTile(
                    Icons.settings_input_antenna,
                    "Receiver",
                    s.connected ? "Connected" : "Disconnected",
                    connColor,
                  ),
                  _boolTile(Icons.gps_fixed, "GPS position valid", s.gpsValid),
                  _boolTile(Icons.access_time, "UTC timing OK", s.utcOk),
                  _boolTile(Icons.power_settings_new, "UAT initialized", s.uatInitialized),
                  _statusTile(
                    Icons.cell_tower,
                    "Ground stations received",
                    "${s.towerCount}",
                    s.towerCount > 0 ? Colors.green : Colors.grey,
                  ),
                ],
              );
            },
          ),
          const Divider(height: 1),
          // Messages header with pause/resume
          AnimatedBuilder(
            animation: Storage().adsbStatus.logChange,
            builder: (context, _) {
              final bool paused = Storage().adsbStatus.logPaused;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(
                  children: [
                    const Text("Messages (last 50)",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      tooltip: "Filter types",
                      onPressed: _showFilters,
                      icon: const Icon(Icons.filter_list),
                    ),
                    TextButton.icon(
                      onPressed: () => Storage().adsbStatus.toggleLogPaused(),
                      icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                      label: Text(paused ? "Resume" : "Pause"),
                    ),
                  ],
                ),
              );
            },
          ),
          // Scrolling message list, newest first; tap to expand decoded fields
          Expanded(
            child: AnimatedBuilder(
              animation: Storage().adsbStatus.logChange,
              builder: (context, _) {
                final List<AdsbLogEntry> msgs = Storage().adsbStatus.messages();
                if (msgs.isEmpty) {
                  return const Center(child: Text("No messages received"));
                }
                return ListView.builder(
                  controller: _scroll,
                  itemCount: msgs.length,
                  itemBuilder: (context, i) {
                    final AdsbLogEntry m = msgs[i];
                    return ExpansionTile(
                      key: ValueKey(m),
                      dense: true,
                      title: Text(m.summary.isEmpty
                          ? m.type
                          : "${m.type}  \u2014  ${m.summary}"),
                      subtitle: Text(_formatTime(m.time)),
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.decoded.isEmpty ? "No decode available" : m.decoded,
                                style: const TextStyle(fontFamily: "monospace"),
                              ),
                              const SizedBox(height: 8),
                              const Text("Raw bytes:",
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              SelectableText(
                                m.raw.isEmpty ? "-" : m.raw,
                                style: const TextStyle(fontFamily: "monospace", fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
