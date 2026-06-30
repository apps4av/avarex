import 'package:avaremp/gdl90/adsb_status.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';

import '../constants.dart';

/// Full screen showing live ADS-B receiver status, driven by the GDL90
/// heartbeat (connection + GPS/UTC/UAT status) and FIS-B ground uplink frames
/// (ground stations heard). Pushed from the ADSB instrument tile; the AppBar
/// provides the back button.
class AdsbStatusScreen extends StatelessWidget {
  const AdsbStatusScreen({super.key});

  Widget _statusTile(IconData icon, String title, String value, Color color) {
    return Card(
      child: ListTile(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text("ADS-B Status"),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge(
            [Storage().timeChange, Storage().adsbStatus.change]),
        builder: (context, _) {
          final AdsbStatus s = Storage().adsbStatus;
          final Color connColor = !s.connected
              ? Colors.grey
              : (!s.gpsValid ? Colors.amber : Colors.green);
          return ListView(
            padding: const EdgeInsets.all(16),
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
    );
  }
}
