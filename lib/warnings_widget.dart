
import 'dart:core';

import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'constants.dart';
import 'gps.dart';

class WarningsFuture {

  bool gpsPermissionAllowed = false;
  bool gpsEnabled = false;
  bool dataAvailable = false;
  bool dataCurrent = false;

  // get all warnings
  Future<void> _getAll() async {
    LocationPermission permission = await Gps().checkPermissions();
    gpsPermissionAllowed =
    LocationPermission.denied == permission ||
        LocationPermission.deniedForever == permission ||
        LocationPermission.unableToDetermine == permission ? false : true;
    gpsEnabled = await Gps().checkEnabled();
    dataAvailable = Storage().chartsExist;
    dataCurrent = Storage().dataExpired;
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
            bool warn =
                snapshot.data!.gpsPermissionAllowed == false ||
                snapshot.data!.gpsEnabled == false ||
                snapshot.data!.dataAvailable == false ||
                snapshot.data!.dataCurrent == false;
            if(warn) {
              return CircleAvatar(
                  backgroundColor: Constants.centerButtonBackgroundColor,
                  child: IconButton(icon: const Icon(Icons.warning, color: Colors.red),
                    onPressed: () {
                      Scaffold.of(context).openEndDrawer();
                    },
                  )
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
            return(_makeContent(snapshot.data, context));
          }
          else {
            return _makeContent(null, context);
          }
        }
    );
  }

  Widget _makeContent(WarningsFuture? future, BuildContext context) {
    if(null == future) {
      return const Drawer();
    }

    List<ListTile> list = [
      const ListTile(
        title: Text("Issues", style: TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text("Tapping on the issue will help you resolve it."),
        leading: Icon(Icons.warning, color: Colors.red,), dense: false,)];

    String gpsPermissionMessage = future.gpsPermissionAllowed ? "" :
        "GPS permission is denied, please enable it in device settings.";
    if(gpsPermissionMessage.isNotEmpty) {
      list.add(ListTile(title: const Text("GPS Permission"),
          leading: const Icon(Icons.gpp_good_sharp),
          subtitle: Text(gpsPermissionMessage),
          dense: true,
          onTap: () => { Geolocator.openAppSettings()}));
    }

    String gpsEnabledMessage = future.gpsEnabled ? "" :
        "GPS is disabled, please enable it in device settings.";
    if(gpsEnabledMessage.isNotEmpty) {
      list.add(ListTile(title: const Text("GPS"),
          leading: const Icon(Icons.gps_off_sharp),
          subtitle: Text(gpsEnabledMessage),
          dense: true,
          onTap: () => {Geolocator.openLocationSettings()}));
    }

    String dataAvailableMessage = future.dataAvailable ? "" :
        "Critical data is missing, please download the databases and some charts using the Download menu.";
    if(dataAvailableMessage.isNotEmpty) {
      list.add(ListTile(title: const Text("Data"),
          leading: const Icon(Icons.download),
          subtitle: Text(dataAvailableMessage),
          dense: true,
          onTap: () => {Navigator.pushNamed(context, '/download')}));
    }

    String dataCurrentMessage = future.dataCurrent ? "" :
        "Some or all the data has expired, please update the data using the Download menu.";
    if(dataCurrentMessage.isNotEmpty) {
      list.add(ListTile(title: const Text("Update"),
          leading: const Icon(Icons.update),
          subtitle: Text(dataCurrentMessage),
          dense: true,
          onTap: () => {Navigator.pushNamed(context, '/download')}));
    }

    return Drawer(
        child: ListView(children: list,
        )
    );
  }
}