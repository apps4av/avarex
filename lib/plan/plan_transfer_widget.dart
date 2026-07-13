import 'package:avaremp/avidyne/avidyne_discovery.dart';
import 'package:avaremp/avidyne/avidyne_ifd.dart';
import 'package:avaremp/avidyne/avidyne_message_log.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/toast.dart';
import 'package:flutter/material.dart';

class PlanTransferWidget extends StatefulWidget {
  const PlanTransferWidget({super.key});

  @override
  State<StatefulWidget> createState() => PlanTransferWidgetState();
}

class PlanTransferWidgetState extends State<PlanTransferWidget> {
  final AvidyneIfd _avidyne = AvidyneIfd();
  final AvidyneMessageLog _log = AvidyneMessageLog();

  String? _sendingToIfdIp; // ip currently being sent to, if any
  String? _importingFromIfdIp; // ip currently being read from, if any
  String _ifdStatus = "";
  Color _ifdStatusColor = Colors.green;

  @override
  void initState() {
    super.initState();
    // Discovery is normally already running (started with network IO for
    // Capstone ADS-B); this just makes sure it is up while the transfer UI is
    // open. It is intentionally left running on dispose.
    _avidyne.start();
    // Run the hex log live while the transfer screen is open.
    _log.logPaused = false;
  }

  @override
  void dispose() {
    // Leaving the screen pauses the message log so it stops updating.
    _log.logPaused = true;
    super.dispose();
  }

  Future<void> _sendToIfd(AvidyneDevice device) async {
    setState(() {
      _sendingToIfdIp = device.ipAddress;
      _ifdStatus = "Sending to ${device.label} \u2026";
      _ifdStatusColor = Colors.blue;
    });

    final error = await _avidyne.sendFlightPlan(device, Storage().route);
    if (!mounted) {
      return;
    }

    setState(() {
      _sendingToIfdIp = null;
      if (error == null) {
        _ifdStatus = "Flight plan sent to ${device.label}.";
        _ifdStatusColor = Colors.green;
      } else {
        _ifdStatus = error;
        _ifdStatusColor = Colors.red;
      }
    });

    if (error == null) {
      Toast.showToast(context, "Sent flight plan to Avidyne IFD",
          const Icon(Icons.check, color: Colors.green), 3);
    } else {
      Toast.showToast(
          context, error, const Icon(Icons.error, color: Colors.red), 4);
    }
  }

  Future<void> _getFromIfd(AvidyneDevice device) async {
    setState(() {
      _importingFromIfdIp = device.ipAddress;
      _ifdStatus = "Getting flight plan from ${device.label} \u2026";
      _ifdStatusColor = Colors.blue;
    });

    final (route, error) = await _avidyne.importFlightPlan(device);
    if (!mounted) {
      return;
    }

    if (error == null && route != null) {
      Storage().route.copyFrom(route);
    }

    setState(() {
      _importingFromIfdIp = null;
      if (error == null && route != null) {
        _ifdStatus =
            "Loaded ${route.length} waypoints from ${device.label} into the active plan.";
        _ifdStatusColor = Colors.green;
      } else {
        _ifdStatus = error ?? "Could not read the flight plan.";
        _ifdStatusColor = Colors.red;
      }
    });

    if (error == null && route != null) {
      Toast.showToast(context, "Loaded flight plan from Avidyne IFD",
          const Icon(Icons.check, color: Colors.green), 3);
    } else {
      Toast.showToast(context, _ifdStatus,
          const Icon(Icons.error, color: Colors.red), 4);
    }
  }

  // Broadcasts the "AVISDK" discovery trigger (the same message Storage's IO
  // startup sends) so nearby IFDs re-announce themselves without waiting for
  // the next periodic broadcast.
  Future<void> _searchIfds() async {
    await _avidyne.triggerDiscovery();
    if (!mounted) {
      return;
    }
    Toast.showToast(context, "Searching for Avidyne IFDs\u2026",
        const Icon(Icons.wifi_tethering, color: Colors.blue), 2);
  }

  Widget _sectionTitle(String title) {
    return Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
        child: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)));
  }

  String _formatTime(DateTime t) {
    String two(int v) => v < 10 ? "0$v" : "$v";
    return "${two(t.hour)}:${two(t.minute)}:${two(t.second)}";
  }

  Widget _buildAvidyneSection() {
    final route = Storage().route;
    final destinations = route.getAllDestinations();
    final bool hasEnoughWaypoints = destinations.length >= 2;

    return ValueListenableBuilder<int>(
        valueListenable: _avidyne.change,
        builder: (context, _, __) {
          final devices = _avidyne.devices;
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _sectionTitle("Avidyne IFD (Wi-Fi)"),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _searchIfds(),
                    child: const Text("Search"),
                  ),
                ]),
                const Text(
                    "Send the active flight plan to an Avidyne IFD440/540/550 over "
                    "Wi-Fi, or get the IFD's flight plan into AvareX. Connect this "
                    "device to the same Wi-Fi network as the IFD, then wait for it "
                    "to appear below."),
                const Padding(padding: EdgeInsets.all(4)),
                Text("Plan: ${route.name} (${destinations.length} waypoints)"),
                const Padding(padding: EdgeInsets.all(4)),
                if (devices.isEmpty)
                  Row(children: const [
                    SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    Padding(padding: EdgeInsets.all(6)),
                    Expanded(child: Text("Searching for Avidyne IFDs\u2026")),
                  ])
                else
                  ...devices.map((device) =>
                      _buildIfdTile(device, hasEnoughWaypoints)),
                if (_ifdStatus.isNotEmpty)
                  Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(_ifdStatus,
                          style: TextStyle(color: _ifdStatusColor))),
              ]);
        });
  }

  Widget _buildIfdTile(AvidyneDevice device, bool hasEnoughWaypoints) {
    final bool busy = _sendingToIfdIp != null || _importingFromIfdIp != null;
    final bool workingThis = _sendingToIfdIp == device.ipAddress ||
        _importingFromIfdIp == device.ipAddress;
    final bool canSend = hasEnoughWaypoints &&
        device.acceptsFlightPlans &&
        !busy &&
        !_avidyne.transferInProgress;
    final bool canGet = !busy && !_avidyne.transferInProgress;

    String subtitle = "Software ${device.versionLabel}";
    if (!device.acceptsFlightPlans) {
      subtitle += " \u2022 flight plan input not enabled";
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.flight, color: Colors.green),
      title: Text(device.label),
      subtitle: Text(subtitle),
      trailing: workingThis
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton(
                onPressed: canGet ? () => _getFromIfd(device) : null,
                child: const Text("Get"),
              ),
              TextButton(
                onPressed: canSend ? () => _sendToIfd(device) : null,
                child: const Text("Send"),
              ),
            ]),
    );
  }

  Widget _buildMessageHeader() {
    return AnimatedBuilder(
      animation: _log.logChange,
      builder: (context, _) {
        final bool paused = _log.logPaused;
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
          child: Row(
            children: [
              const Text("Messages (last 50)",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _log.clear(),
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text("Clear"),
              ),
              TextButton.icon(
                onPressed: () => _log.toggleLogPaused(),
                icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                label: Text(paused ? "Resume" : "Pause"),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageList() {
    return AnimatedBuilder(
      animation: _log.logChange,
      builder: (context, _) {
        final List<AvidyneLogEntry> msgs = _log.messages();
        if (msgs.isEmpty) {
          return const Center(
              child: Text("No transfer messages yet — use Send or Get"));
        }
        return ListView.builder(
          itemCount: msgs.length,
          itemBuilder: (context, i) {
            final AvidyneLogEntry m = msgs[i];
            final Color dirColor =
                m.outbound ? Colors.blue : Colors.green;
            return ExpansionTile(
              key: ValueKey(m),
              dense: true,
              leading: Text(m.directionLabel,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: dirColor,
                      fontFamily: "monospace")),
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
                      const Text("Raw bytes:",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      SelectableText(
                        m.raw.isEmpty ? "-" : m.raw,
                        style: const TextStyle(
                            fontFamily: "monospace", fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Parent already gives us a bounded height (Expanded). Cap the device
    // section so a long description cannot starve the hex log; put the
    // scrolling message list in the remaining space (ADS-B Status layout).
    final double maxTop = MediaQuery.sizeOf(context).height * 0.45;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxTop),
            child: SingleChildScrollView(child: _buildAvidyneSection()),
          ),
          const Divider(height: 16),
          _buildMessageHeader(),
          Expanded(child: _buildMessageList()),
        ],
      ),
    );
  }
}
