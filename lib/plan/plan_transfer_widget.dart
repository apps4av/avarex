import 'package:avaremp/constants.dart';
import 'package:avaremp/io/garmin_connext_transfer.dart';
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
  String _status = "";
  Color _statusColor = Colors.green;

  Future<void> _openBluetooth() async {
    await Navigator.pushNamed(context, '/io');
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _sendToGarmin() async {
    setState(() {
      _sending = true;
      _status = "";
    });

    final error = await GarminConnextTransfer.sendFlightPlan(Storage().route);
    if (!mounted) {
      return;
    }

    setState(() {
      _sending = false;
      if (error == null) {
        final device = GarminConnextTransfer.connectedDeviceLabel ?? "Garmin device";
        _status = "Flight plan sent to $device.";
        _statusColor = Colors.green;
      } else {
        _status = error;
        _statusColor = Colors.red;
      }
    });

    if (error == null) {
      Toast.showToast(context, "Sent flight plan to Garmin device",
          const Icon(Icons.check, color: Colors.green), 3);
    } else {
      Toast.showToast(context, error,
          const Icon(Icons.error, color: Colors.red), 4);
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = Storage().route;
    final destinations = route.getAllDestinations();
    final bool isConnected = GarminConnextTransfer.isConnected;
    final String connectionLabel =
        GarminConnextTransfer.connectedDeviceLabel ?? "Not connected";
    final bool canSend = isConnected &&
        destinations.length >= GarminConnextTransfer.minWaypoints &&
        !_sending;

    return Container(
        padding: const EdgeInsets.all(0),
        child: Column(children: [
          Expanded(
              flex: 1,
              child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                  child: const Text("Transfer",
                      style: TextStyle(fontWeight: FontWeight.w800)))),
          Expanded(
              flex: 2,
              child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                  alignment: Alignment.centerLeft,
                  child: const Text(
                      "Send the current flight plan to a Garmin device using Garmin Connext over Bluetooth."))),
          Expanded(
              flex: 1,
              child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                  child: Row(children: [
                    Icon(
                        isConnected
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth_disabled,
                        color: isConnected ? Colors.green : Colors.red),
                    const Padding(padding: EdgeInsets.all(6)),
                    Expanded(child: Text(connectionLabel)),
                  ]))),
          Expanded(
              flex: 1,
              child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                  alignment: Alignment.centerLeft,
                  child: Text(
                      "Plan: ${route.name} (${destinations.length} waypoints)"))),
          Expanded(
              flex: 2,
              child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                  child: Row(children: [
                    if (Constants.shouldShowBluetoothSpp)
                      TextButton(
                          onPressed: _openBluetooth,
                          child: const Text("Open Bluetooth")),
                    const Padding(padding: EdgeInsets.fromLTRB(6, 0, 6, 0)),
                    TextButton(
                        onPressed: canSend ? _sendToGarmin : null,
                        child: const Text("Send to Garmin")),
                    const Padding(padding: EdgeInsets.fromLTRB(10, 0, 0, 0)),
                    SizedBox(
                        width: 16,
                        height: 16,
                        child: Visibility(
                            visible: _sending,
                            child: const CircularProgressIndicator())),
                  ]))),
          Expanded(
              flex: 1,
              child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                  alignment: Alignment.centerLeft,
                  child: Text(_status,
                      style: TextStyle(color: _statusColor)))),
        ]));
  }
}