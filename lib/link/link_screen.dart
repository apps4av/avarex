import 'dart:async';
import 'dart:convert';

import 'package:avaremp/link/link_protocol.dart';
import 'package:avaremp/link/link_service.dart';
import 'package:flutter/material.dart';

/// Pick master or slave, see the other AvareX devices on this Wi-Fi, and
/// watch the JSON messages going back and forth.
class LinkScreen extends StatefulWidget {
  const LinkScreen({super.key});

  @override
  State<LinkScreen> createState() => _LinkScreenState();
}

class _LinkScreenState extends State<LinkScreen> {
  final LinkService _link = LinkService();
  late final TextEditingController _name;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _link.load();
    _name = TextEditingController(text: _link.deviceName);
    _link.change.addListener(_onLink);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _onLink() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _link.change.removeListener(_onLink);
    _name.dispose();
    super.dispose();
  }

  void _saveName(String value) {
    _link.setName(value);
    if (_name.text != _link.deviceName) {
      _name.text = _link.deviceName;
    }
  }

  Future<void> _selectRole(LinkRole role) async {
    if (role == LinkRole.master &&
        _link.role != LinkRole.master &&
        _link.otherMasterCount > 0) {
      final bool? ok = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text("Another master is already on this network"),
            content: const Text(
                "Slaves copy whichever master's plan arrives last. One master keeps every device on the same plan."),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Become master"),
              ),
            ],
          );
        },
      );
      if (ok != true) {
        return;
      }
    }
    _link.setRole(role);
  }

  IconData _roleIcon(LinkRole role) {
    switch (role) {
      case LinkRole.master:
        return Icons.cell_tower;
      case LinkRole.slave:
        return Icons.devices;
      case LinkRole.off:
        return Icons.portable_wifi_off;
    }
  }

  String _ago(DateTime time) {
    final int seconds = DateTime.now().difference(time).inSeconds;
    if (seconds < 2) {
      return "now";
    }
    return "${seconds}s ago";
  }

  String _clock(DateTime time) {
    String two(int value) => value < 10 ? "0$value" : "$value";
    return "${two(time.hour)}:${two(time.minute)}:${two(time.second)}";
  }

  String _pretty(String body) {
    try {
      return const JsonEncoder.withIndent("  ").convert(jsonDecode(body));
    } catch (_) {
      return body;
    }
  }

  Widget _note(Color background, IconData icon, String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _deviceTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool highlight,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: highlight ? Theme.of(context).colorScheme.primary : null),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<LinkPeer> peers = _link.peers;
    final List<LinkLogEntry> entries = _link.log;
    final String status = _link.bindError != null
        ? "Not listening. ${_link.bindError}"
        : _link.isRunning
            ? "UDP ${LinkMessage.port} on this Wi-Fi. ${peers.length} other device${peers.length == 1 ? "" : "s"}."
            : "Link is stopped.";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Link"),
        actions: [
          IconButton(
            tooltip: "Announce now",
            onPressed: _link.announce,
            icon: const Icon(Icons.wifi_tethering),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              children: [
                SegmentedButton<LinkRole>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment<LinkRole>(
                      value: LinkRole.off,
                      label: Text("Off"),
                      tooltip: "Does not announce or sync",
                    ),
                    ButtonSegment<LinkRole>(
                      value: LinkRole.master,
                      label: Text("Master"),
                      tooltip: "Sends this device's plan",
                    ),
                    ButtonSegment<LinkRole>(
                      value: LinkRole.slave,
                      label: Text("Slave"),
                      tooltip: "Copies the master's plan",
                    ),
                  ],
                  selected: {_link.role},
                  onSelectionChanged: (Set<LinkRole> next) {
                    _selectRole(next.first);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: "Name on the network",
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: _saveName,
                  onTapOutside: (_) => _saveName(_name.text),
                ),
                const SizedBox(height: 8),
                Text(status, style: TextStyle(fontSize: 12, color: scheme.outline)),
                if (_link.role == LinkRole.off)
                  _note(scheme.surfaceContainerHighest, Icons.info_outline,
                      "Off does not announce this device. Set one device to Master and the others to Slave. The choice is kept when the app restarts."),
                if (_link.role == LinkRole.master && _link.otherMasterCount > 0)
                  _note(scheme.errorContainer, Icons.warning_amber,
                      "More than one master is on this network. Slaves follow whichever plan arrives last."),
                if (_link.role == LinkRole.master && _link.otherMasterCount == 0)
                  _note(scheme.primaryContainer, Icons.cell_tower,
                      "This device sends its plan when the plan or the active waypoint changes."),
                if (_link.role == LinkRole.slave && _link.followedMasterName == null)
                  _note(scheme.surfaceContainerHighest, Icons.devices,
                      "Waiting for a master on this Wi-Fi."),
                if (_link.role == LinkRole.slave && _link.followedMasterName != null)
                  _note(scheme.tertiaryContainer, Icons.devices,
                      "Copying the plan from ${_link.followedMasterName}."),
                const SizedBox(height: 12),
                Text("DEVICES",
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                        color: scheme.primary)),
                _deviceTile(
                  icon: _roleIcon(_link.role),
                  title: "${_link.deviceName}  ·  this device",
                  subtitle: _link.role.name,
                  highlight: true,
                ),
                if (peers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      "No other AvareX devices yet. Open Link on each one, joined to the same Wi-Fi.",
                      style: TextStyle(fontSize: 13, color: scheme.outline),
                    ),
                  ),
                for (final LinkPeer peer in peers)
                  _deviceTile(
                    icon: _roleIcon(peer.role),
                    title: peer.name,
                    subtitle: "${peer.role.name}  ·  ${peer.address}  ·  ${_ago(peer.lastSeen)}",
                    highlight: peer.role == LinkRole.master,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Row(
              children: [
                Text("MESSAGES",
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                        color: scheme.primary)),
                const Spacer(),
                IconButton(
                  tooltip: _link.logPaused ? "Resume" : "Pause",
                  onPressed: () {
                    setState(() {
                      _link.logPaused = !_link.logPaused;
                    });
                  },
                  icon: Icon(_link.logPaused ? Icons.play_arrow : Icons.pause),
                ),
                IconButton(
                  tooltip: "Clear",
                  onPressed: _link.clearLog,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      "Messages sent and received show up here.",
                      style: TextStyle(color: scheme.outline),
                    ),
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (BuildContext context, int index) {
                      final LinkLogEntry entry = entries[index];
                      final Color tone = entry.outbound ? Colors.blue : Colors.green;
                      return ListTile(
                        dense: true,
                        onTap: () {
                          setState(() {
                            entry.expanded = !entry.expanded;
                          });
                        },
                        leading: Text(
                          entry.outbound ? "TX" : "RX",
                          style: TextStyle(color: tone, fontWeight: FontWeight.bold),
                        ),
                        title: Text(entry.summary, maxLines: entry.expanded ? 4 : 1, overflow: TextOverflow.ellipsis),
                        subtitle: entry.expanded
                            ? SelectableText(
                                _pretty(entry.body),
                                style: const TextStyle(fontFamily: "monospace", fontSize: 11),
                              )
                            : Text("${_clock(entry.time)}  ${entry.address}"),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
