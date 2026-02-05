import 'package:avaremp/constants.dart';
import 'package:avaremp/io/io_screen.dart';
import 'package:avaremp/plan/avidyne_transfer.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/toast.dart';
import 'package:flutter/material.dart';

class PlanTransferWidget extends StatefulWidget {
  const PlanTransferWidget({super.key});

  @override
  State<StatefulWidget> createState() => PlanTransferWidgetState();
}

class PlanTransferWidgetState extends State<PlanTransferWidget> {
  bool _sending = false;
  String _status = '';
  Color? _statusColor;

  Future<void> _sendPlan(AvidyneTransferPayload payload) async {
    if (!Constants.shouldShowBluetoothSpp) {
      Toast.showToast(context, "Bluetooth transfer is available on Android only.", null, 3);
      return;
    }
    if (!IoScreenState.isConnected) {
      Toast.showToast(context, "Connect to your Avidyne device in IO first.", null, 3);
      return;
    }
    setState(() {
      _sending = true;
      _status = '';
      _statusColor = null;
    });

    bool ok = await IoScreenState.sendPlanData(payload.data);
    if (!mounted) {
      return;
    }
    setState(() {
      _sending = false;
      if (ok) {
        _status = "Transfer complete (${payload.waypointCount} waypoints).";
        if (payload.userWaypointCount > 0) {
          _status += " ${payload.userWaypointCount} user waypoints created.";
        }
        _statusColor = Colors.green;
      } else {
        _status = "Transfer failed. Check Bluetooth connection.";
        _statusColor = Colors.red;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Storage().route.change,
      builder: (context, value, child) {
        final AvidyneTransferPayload? payload = AvidyneTransfer.buildTransfer(Storage().route);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Transfer (Avidyne)", style: TextStyle(fontWeight: FontWeight.w800)),
            const Padding(padding: EdgeInsets.all(6)),
            const Text("Send the current flight plan to Avidyne equipment using Bluetooth."),
            const Padding(padding: EdgeInsets.all(6)),
            Row(
              children: [
                Icon(
                  IoScreenState.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: IoScreenState.isConnected ? Colors.green : Colors.grey,
                ),
                const Padding(padding: EdgeInsets.fromLTRB(6, 0, 0, 0)),
                Expanded(
                  child: Text(
                    IoScreenState.isConnected
                        ? "Connected to ${IoScreenState.connectionName ?? "device"}"
                        : "Not connected",
                  ),
                ),
              ],
            ),
            const Padding(padding: EdgeInsets.all(6)),
            if (!Constants.shouldShowBluetoothSpp)
              const Text("Bluetooth transfer is not available on this platform."),
            if (payload == null)
              const Text("No flight plan to transfer."),
            if (payload != null) ...[
              Text("Route ID: ${payload.routeId}"),
              Text("Waypoints: ${payload.waypointCount}"),
              if (payload.userWaypointCount > 0)
                Text("User waypoints: ${payload.userWaypointCount}"),
              Text("NMEA sentences: ${payload.sentenceCount}"),
              const Padding(padding: EdgeInsets.all(6)),
              Row(
                children: [
                  TextButton(
                    onPressed: _sending ? null : () => _sendPlan(payload),
                    child: const Text("Send to Avidyne"),
                  ),
                  const Padding(padding: EdgeInsets.fromLTRB(10, 0, 0, 0)),
                  if (_sending) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator()),
                ],
              ),
              if (_status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
                  child: Text(_status, style: TextStyle(color: _statusColor)),
                ),
            ],
          ],
        );
      },
    );
  }
}
