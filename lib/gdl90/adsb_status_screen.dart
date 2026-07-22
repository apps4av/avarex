import 'package:avaremp/gdl90/adsb_status.dart';
import 'package:avaremp/gdl90/ground_station_cache.dart';
import 'package:avaremp/gdl90/stratus_open_mode.dart';
import 'package:avaremp/gdl90/traffic_report_message.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:avaremp/utils/toast.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

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

  Future<void> _sendStratusOpenMode() async {
    bool ok = await StratusOpenMode.send();
    if(!mounted) {
      return;
    }
    if(ok) {
      Toast.showToast(context, "Sent Stratus Open ADS-B Mode command",
          const Icon(Icons.check, color: Colors.green), 3);
    }
    else {
      Toast.showToast(context, "Failed to send Stratus Open ADS-B Mode command",
          const Icon(Icons.error, color: Colors.red), 4);
    }
  }

  // One-shot control to put a Stratus 3 / 3i into Open ADS-B (GDL90) mode.
  Widget _stratusOpenModeButton() {
    return Card(
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.wifi_tethering),
        title: const Text("Stratus Open ADS-B Mode"),
        subtitle: const Text("Send once while on Stratus Wi-Fi"),
        trailing: TextButton(
          onPressed: _sendStratusOpenMode,
          child: const Text("Send"),
        ),
      ),
    );
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

  // Unique color per GDL90 message type. The same colors are used to tint the
  // log rows and to mark each type in the filter list, so the two stay in sync.
  static const Map<int, Color> _typeColors = {
    0x00: Colors.blueGrey,   // Heartbeat
    0x07: Colors.teal,       // Uplink (FIS-B)
    0x0A: Colors.orange,     // Ownship
    0x0B: Colors.deepOrange, // Ownship geo. altitude
    0x14: Colors.blue,       // Traffic
    0x1E: Colors.indigo,     // Basic report
    0x1F: Colors.cyan,       // Long report
    0x4C: Colors.green,      // AHRS
    0x7A: Colors.brown,      // Device
    0xCC: Colors.purple,     // Roll reverse
  };

  // Color for a message type; unknown/unlisted types fall back to grey.
  Color _typeColor(int typeId) => _typeColors[typeId] ?? Colors.grey;

  // Small filled swatch used to mark a message type's color in the filter list.
  Widget _swatch(Color color) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  // List of the ground stations currently being received, with distance and
  // bearing from ownship (nearest first). Empty when none are heard.
  Widget _stationList(AdsbStatus s) {
    final List<GroundStation> stations = s.groundStations();
    if (stations.isEmpty) {
      return const SizedBox.shrink();
    }
    final pos = Storage().position;
    final bool havePos = !(pos.latitude == 0 && pos.longitude == 0);
    final LatLng here = LatLng(pos.latitude, pos.longitude);
    final GeoCalculations geo = GeoCalculations();
    final String unit = Storage().settings.getUnits() == "Imperial" ? "sm" : "nm";

    // pair each station with distance/bearing from ownship (null if no fix)
    final List<(GroundStation, double?, double?)> entries = stations.map((st) {
      final double? dist = havePos ? geo.calculateDistance(here, st.coordinates) : null;
      final double? brg = havePos ? geo.calculateBearing(here, st.coordinates) : null;
      return (st, dist, brg);
    }).toList();
    if (havePos) {
      entries.sort((a, b) => (a.$2 ?? 0).compareTo(b.$2 ?? 0));
    }

    return Column(
      children: [for (final e in entries) _stationTile(e.$1, e.$2, e.$3, unit)],
    );
  }

  // One ground-station row: identity (TIS-B site / slot), distance+bearing from
  // ownship, position, and how long ago it was last heard.
  Widget _stationTile(GroundStation st, double? dist, double? brg, String unit) {
    final int agoS =
        ((DateTime.now().millisecondsSinceEpoch - st.lastSeenMs) / 1000).floor();
    final String name =
        st.tisbSiteId > 0 ? "TIS-B site ${st.tisbSiteId}" : "Ground station";
    final String db = (dist != null && brg != null)
        ? "${dist.toStringAsFixed(1)} $unit \u2022 ${brg.toStringAsFixed(0)}\u00b0"
        : "position unknown";
    final String coords =
        "${st.coordinates.latitude.toStringAsFixed(3)}\u00b0, ${st.coordinates.longitude.toStringAsFixed(3)}\u00b0";
    return Card(
      margin: const EdgeInsets.fromLTRB(24, 0, 8, 4),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: const Icon(Icons.cell_tower, size: 20),
        title: Text("$name \u2022 slot ${st.slotId}"),
        subtitle: Text("$db\n$coords"),
        isThreeLine: true,
        trailing: Text("${agoS}s"),
      ),
    );
  }

  // Diagnostics: reception-quality counters to help debug ADS-B issues.
  // Collapsed by default so it doesn't crowd the status tiles.
  Widget _diagnostics(AdsbStatus s) {
    final int tracked = Storage().trafficCache.getTraffic().length;
    // Fixed set/order of stats so nothing reflows as values update each second.
    final List<Widget> cells = [
      _diagCell("Msgs", "${s.totalMessages}"),
      _diagCell("Rate", "${s.messagesPerSecond.toStringAsFixed(1)}/s"),
      _diagCell("Heartbeat", "${s.typeCount(0x00)}"),
      _diagCell("HB seen", _ago(s.secondsSinceHeartbeat)),
      _diagCell("HB up/traf", "${s.lastUplinkCount}/${s.lastTrafficCount}"),
      _diagCell("Uplink", "${s.typeCount(0x07)}"),
      _diagCell("Ownship", "${s.typeCount(0x0A)}"),
      _diagCell("Ownship seen", _ago(s.secondsSinceOwnship)),
      _diagCell("Traffic", "${s.trafficMessageCount}"),
      _diagCell("Traffic seen", _ago(s.secondsSinceTraffic)),
      _diagCell("Tracked", "$tracked"),
      _diagCell("AHRS", "${s.typeCount(0x4C)}"),
      _diagCell("Filt own", "${s.filteredOwnshipCount}"),
      _diagCell("Filt range", "${s.filteredRangeCount}"),
      _diagCell("CRC err", "${s.crcErrors}", warn: true),
      _diagCell("Frame err", "${s.frameErrors}", warn: true),
      _diagCell("Parse err", "${s.parseErrors}", warn: true),
    ];
    // Lay out cells in a stable two-column grid.
    final List<Widget> rows = [];
    for (int i = 0; i < cells.length; i += 2) {
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cells[i],
          const SizedBox(width: 16),
          i + 1 < cells.length ? cells[i + 1] : const Expanded(child: SizedBox()),
        ],
      ));
    }
    return Card(
      child: ExpansionTile(
        dense: true,
        leading: const Icon(Icons.analytics_outlined),
        title: const Text("Diagnostics"),
        subtitle: Text("${s.totalMessages} messages received"),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => Storage().adsbStatus.resetDiagnostics(),
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text("Reset"),
            ),
          ),
          ...rows,
        ],
      ),
    );
  }

  // "Ns" since an event, or "—" when it has never occurred.
  String _ago(int seconds) => seconds < 0 ? "\u2014" : "${seconds}s";

  // One label/value stat occupying a fixed half-width cell. The label is left-
  // aligned and the value right-aligned, so changing values never shift the
  // layout. When [warn] is set and the value is non-zero it turns red.
  Widget _diagCell(String label, String value, {bool warn = false}) {
    final bool alert = warn && value != "0";
    final Color? color = alert ? Colors.red : null;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            ),
            const SizedBox(width: 6),
            Text(value,
                style: TextStyle(fontSize: 12, fontFeatures: const [FontFeature.tabularFigures()], color: color)),
          ],
        ),
      ),
    );
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
                      secondary: _swatch(_typeColor(entry.key)),
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
          // Live receiver status. Bounded + scrollable so expanding the
          // Diagnostics card can't overflow the screen; the message log below
          // keeps its own space.
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55),
            child: SingleChildScrollView(
              child: AnimatedBuilder(
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
                      _stationList(s),
                      _stratusOpenModeButton(),
                      _diagnostics(s),
                    ],
                  );
                },
              ),
            ),
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
                    // Each message type has its own color (matching the filter
                    // list). Any traffic filtering is noted as a text tag.
                    final Color accent = _typeColor(m.typeId);
                    final Color tileColor = accent.withValues(alpha: 0.14);
                    final String? filterTag = m.filter == TrafficFilter.ownship
                        ? "filtered: ownship"
                        : (m.filter == TrafficFilter.range
                            ? "filtered: out of range"
                            : null);
                    final String titleText = [
                      m.type,
                      if (m.summary.isNotEmpty) m.summary,
                      if (filterTag != null) filterTag,
                    ].join("  \u2014  ");
                    return ExpansionTile(
                      key: ValueKey(m),
                      dense: true,
                      backgroundColor: tileColor,
                      collapsedBackgroundColor: tileColor,
                      iconColor: accent,
                      collapsedIconColor: accent,
                      title: Text(
                        titleText,
                        style: TextStyle(color: accent, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        _formatTime(m.time),
                        style: TextStyle(color: accent.withValues(alpha: 0.8)),
                      ),
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
