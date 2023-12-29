
import 'dart:core';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'gps.dart';

class WarningsFuture {

  bool gpsPermission = false;
  bool gpsEnabled = false;
  bool dataCurrent = false;

  // get all warnings
  Future<void> _getAll() async {
    LocationPermission permission = await Gps().checkPermissions();
    gpsPermission =
    LocationPermission.denied == permission ||
        LocationPermission.deniedForever == permission ||
        LocationPermission.unableToDetermine == permission ? false : true;
    gpsEnabled = await Gps().checkEnabled();
  }

  Future<WarningsFuture> getAll() async {
    await _getAll();
    return this;
  }
}

// a button to show if there is an issue
class WarningsButtonWidget extends StatelessWidget {
  const WarningsButtonWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: WarningsFuture().getAll(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            bool warn = snapshot.data!.gpsPermission == false ||
                snapshot.data!.gpsEnabled == false;
            if(warn) {
              return IconButton(
                icon: const Icon(Icons.warning, color: Colors.red,),
                onPressed: () {
                  Scaffold.of(context).openEndDrawer();
                },
              );
            }
          }
          return(Container());
        }
    );
  }
}

class WarningsWidget extends StatelessWidget {
  const WarningsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: WarningsFuture().getAll(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return(_makeContent(snapshot.data));
          }
          else {
            return _makeContent(null);
          }
        }
    );
  }

  Widget _makeContent(WarningsFuture? future) {
    if(null == future) {
      return const Drawer();
    }

    List<ListTile> list = [const ListTile(title: Text("Issues"), leading: Icon(Icons.warning, color: Colors.red,), dense: true,)];

    String gpsPermissionMessage = future.gpsPermission ? "" :
        "GPS permission is denied, please enable it from device settings.";
    if(gpsPermissionMessage.isNotEmpty) {
      list.add(ListTile(title: const Text("GPS Permission"),
          leading: const Icon(Icons.gpp_good_sharp),
          subtitle: Text(gpsPermissionMessage),
          dense: true,
          onTap: () => {}));
    }

    String gpsEnabledMessage = future.gpsEnabled ? "" :
        "GPS is disabled, please enable it from device settings.";
    if(gpsEnabledMessage.isNotEmpty) {
      list.add(ListTile(title: const Text("GPS"),
          leading: const Icon(Icons.gps_off_sharp),
          subtitle: Text(gpsEnabledMessage),
          dense: true,
          onTap: () => {}));
    }

    return Drawer(
        child: ListView(children: list,
        )
    );
  }
}