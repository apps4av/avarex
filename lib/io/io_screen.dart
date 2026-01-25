import 'dart:async';
import 'dart:convert';
import 'package:avaremp/utils/toast.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';


class IoScreen extends StatefulWidget {
  const IoScreen({super.key});
  final bool start = true;
  @override
  State<StatefulWidget> createState() => IoScreenState();
}

class IoScreenState extends State<IoScreen> {

  StreamSubscription<BluetoothDiscoveryResult>? _streamSubscription;
  List<BluetoothDiscoveryResult> results = List<BluetoothDiscoveryResult>.empty(growable: true);
  bool isDiscovering = false;
  static BluetoothConnection? connection;
  static BluetoothDevice? connectedDevice;// this should stay in memory, not putting in storage as this is platform specific


  // send data to remote
  static void sendData(String data) async {
    // this sends autopilot data
    if(connection == null || (!connection!.isConnected)) {
      return;
    }
    try {
      connection!.output.add(utf8.encode(data));
      await connection!.output.allSent;
    }
    catch(e) {
      Storage().setException("Failed to drive the autopilot.");
      return;
    }
  }

  void _startDiscovery() {
    _streamSubscription?.cancel();
    _streamSubscription =
        FlutterBluetoothSerial.instance.startDiscovery().listen((r) {
          setState(() {
            final existingIndex = results.indexWhere(
                    (element) => element.device.address == r.device.address);
            if (existingIndex >= 0) {
              results[existingIndex] = r;
            }
            else {
              results.add(r);
            }
          });
        });

    _streamSubscription!.onDone(() {
      setState(() {
        isDiscovering = false;
      });
    });
  }

  void _restartDiscovery() {
    setState(() {
      results.clear();
      isDiscovering = true;
    });

    _startDiscovery();
  }


  @override
  void initState() {
    super.initState();
    isDiscovering = widget.start;
    if(isDiscovering) {
      _startDiscovery();
    }
  }

  @override
  void dispose() {
    // Avoid memory leak (`setState` after dispose) and cancel discovery
    _streamSubscription?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IO (Bluetooth)'),
        actions: <Widget>[
          isDiscovering
              ? FittedBox(
            child: Container(
              margin: const EdgeInsets.all(16.0),
              child: const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          )
              : IconButton(
            icon: const Icon(Icons.replay),
            onPressed: _restartDiscovery,
          )
        ],
      ),
      body: Column(children: [Expanded(flex: 8, child:ListView.builder(
        itemCount: results.length,
        itemBuilder: (BuildContext context, index) {
          BluetoothDiscoveryResult result = results[index];
          return _BluetoothDeviceListEntry(
            device: result.device,
            rssi: result.rssi,
            onTap: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: Text(result.device.name ?? result.device.address),
                    content: const Text('Choose an operation with this device.'),
                    actions: <Widget>[
                      if(!(result.device.isConnected) && result.device.isBonded) TextButton(
                        child: const Text("Connect\u2190"),
                        onPressed: () {
                          BluetoothConnection.toAddress(result.device.address).then((value) {
                            if(mounted) {
                              setState(() {
                                if(value.isConnected) {
                                  results[results.indexOf(result)] =
                                      makeResult(result, true,
                                          result.device.bondState);

                                  connection = value;
                                  connectedDevice = result.device;
                                  Storage().setBtStream(connection!.input);
                                }
                                else {
                                  Toast.showToast(context, "Failed to connect to ${result.device.name ?? result.device.address}", const Icon(Icons.error, color: Colors.red), 3);
                                }
                              });
                            }
                          }).onError((error, stackTrace) {
                            if(mounted) {
                              setState(() {
                                Toast.showToast(context, "Failed to connect to ${result.device.name ?? result.device.address}", const Icon(Icons.error, color: Colors.red,), 3);
                              });
                            }
                          });
                          Toast.showToast(context, "Connecting to ${result.device.name ?? result.device.address}", const Icon(Icons.error, color: Colors.red,), 3);
                          Navigator.of(context).pop();
                        },
                      ),
                      if(result.device.isBonded) TextButton(
                        child: const Text("Unpair"),
                        onPressed: () {
                          FlutterBluetoothSerial.instance.removeDeviceBondWithAddress(result.device.address).then((value) {
                            if(mounted) {
                              setState(() {
                                results[results.indexOf(result)] =
                                  makeResult(result, result.device.isConnected, BluetoothBondState.none);
                              });
                            }
                          })
                          .onError((error, stackTrace) {
                            if(mounted) {
                              setState(() {
                                Toast.showToast(context, "Failed to unpair with ${result.device.name ?? result.device.address}", const Icon(Icons.error, color: Colors.red), 3);
                              });
                            }
                          });
                          Toast.showToast(context, "Unpairing with ${result.device.name ?? result.device.address} ...", null, 3);
                          Navigator.of(context).pop();
                        },
                      ),
                      if(!result.device.isBonded) TextButton(
                        child: const Text("Pair"),
                        onPressed: () {
                          FlutterBluetoothSerial.instance.bondDeviceAtAddress(result.device.address).then((value) {
                            if(mounted) {
                              setState(() {
                                results[results.indexOf(result)] = makeResult(result, result.device.isConnected,
                                  value == null
                                    ? BluetoothBondState.none
                                    : value ? BluetoothBondState
                                    .bonded : BluetoothBondState.none,
                                );
                              });
                            }
                          })
                          .onError((error, stackTrace) {
                            if(mounted) {
                              setState(() {
                                Toast.showToast(context, "Failed to pair with ${result.device.name ?? result.device.address}", const Icon(Icons.error, color: Colors.red), 3);
                              });
                            }
                          });
                          Toast.showToast(context, "Pairing with ${result.device.name ?? result.device.address} ...", null, 3);
                          Navigator.of(context).pop();
                        },
                      ),
                      TextButton(
                        child: const Text("Cancel"),
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      )),
      Expanded(flex: 1, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(connectedDevice == null? "Not connected" : "Connected to ${connectedDevice!.name ?? connectedDevice!.address}"),
      if(connectedDevice != null) TextButton(
        child: const Text("Disconnect"),
        onPressed: () {
          disconnect();
          Toast.showToast(context, "Disconnecting ...", null, 3);
        },
      ),
      ])),
      ]),
    );

  }

  BluetoothDiscoveryResult makeResult(BluetoothDiscoveryResult result, bool isConnected, BluetoothBondState bondState) {
    return BluetoothDiscoveryResult(
        device: BluetoothDevice(
          name: result.device.name ?? '',
          address: result.device.address,
          type: result.device.type,
          bondState: bondState,
          isConnected: isConnected,
        ),
        rssi: result.rssi);
  }

  void disconnect() {
    if(mounted && connectedDevice != null) {
      setState(() {
        int index = results.indexWhere((element) => element.device.address == connectedDevice!.address);
        if(index >= 0) {
          BluetoothDiscoveryResult result = results[index];
          results[index] = makeResult(result, false, result.device.bondState);
        }
      });
    }

    connection?.dispose();
    connection = null;
    connectedDevice = null;
    Storage().setBtStream(null);
  }
}

class _BluetoothDeviceListEntry extends ListTile {
  _BluetoothDeviceListEntry({
    required BluetoothDevice device,
    int? rssi,
    super.onTap,
  }) : super(
    leading:
    const Icon(Icons.devices),
    title: Text(device.name ?? ""),
    subtitle: Text(device.address.toString()),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        rssi != null
            ? Container(
          margin: const EdgeInsets.all(8.0),
          child: DefaultTextStyle(
            style: _computeTextStyle(rssi),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(rssi.toString()),
                const Text('dBm'),
              ],
            ),
          ),
        )
            : const SizedBox(width: 0, height: 0),
        device.isConnected
            ? const Icon(Icons.import_export)
            : const SizedBox(width: 0, height: 0),
        device.isBonded
            ? const Icon(Icons.link)
            : const SizedBox(width: 0, height: 0),
      ],
    ),
  );

  static TextStyle _computeTextStyle(int rssi) {
    if (rssi >= -35) {
      return TextStyle(color: Colors.greenAccent[700]);
    }
    else if (rssi >= -45) {
      return TextStyle(
          color: Color.lerp(
              Colors.greenAccent[700], Colors.lightGreen, -(rssi + 35) / 10));
    }
    else if (rssi >= -55) {
      return TextStyle(
          color: Color.lerp(
              Colors.lightGreen, Colors.lime[600], -(rssi + 45) / 10));
    }
    else if (rssi >= -65) {
      return TextStyle(
          color: Color.lerp(Colors.lime[600], Colors.amber, -(rssi + 55) / 10));
    }
    else if (rssi >= -75) {
      return TextStyle(
          color: Color.lerp(
              Colors.amber, Colors.deepOrangeAccent, -(rssi + 65) / 10));
    }
    else if (rssi >= -85) {
      return TextStyle(
          color: Color.lerp(
              Colors.deepOrangeAccent, Colors.redAccent, -(rssi + 75) / 10));
    }
    else {
      /*code symmetry*/
      return const TextStyle(color: Colors.redAccent);
    }
  }
}


