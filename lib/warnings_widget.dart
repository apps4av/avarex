
import 'dart:core';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class WarningsButtonWidget extends StatefulWidget {
  WarningsButtonWidget({super.key, required this.warning});

  bool warning;

  @override
  State<StatefulWidget> createState() => WarningsButtonWidgetState();
}

// a button to show if there is an issue
class WarningsButtonWidgetState extends State<WarningsButtonWidget> {


  @override
  Widget build(BuildContext context) {

    if(widget.warning) {
      return IconButton(
        icon: const Icon(Icons.warning, color: Colors.red, size: 64),
          onPressed: () {
            Scaffold.of(context).openEndDrawer();
          },
        );
    }

    return(Container());
  }
}

class WarningsWidget extends StatefulWidget {
  WarningsWidget({super.key, required this.gpsNotPermitted,
    required this.gpsDisabled, required this.chartsMissing, required this.dataExpired});

  bool gpsNotPermitted;
  bool gpsDisabled;
  bool chartsMissing;
  bool dataExpired;

  @override
  State<StatefulWidget> createState() => WarningsWidgetState();
}

class WarningsWidgetState extends State<WarningsWidget> {

  @override
  Widget build(BuildContext context) {

    List<ListTile> list = [
      const ListTile(
        title: Text("Issues", style: TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text("Tapping on the issue will help you resolve it."),
        leading: Icon(Icons.warning, color: Colors.red,), dense: false,)];

    String gpsPermissionMessage = !widget.gpsNotPermitted ? "" :
    "GPS permission is denied, please enable it in device settings.";
    if(gpsPermissionMessage.isNotEmpty) {
      list.add(ListTile(title: const Text("GPS Permission"),
          leading: const Icon(Icons.gpp_good_sharp),
          subtitle: Text(gpsPermissionMessage),
          dense: true,
          onTap: () => { Geolocator.openAppSettings()}));
    }

    String gpsEnabledMessage = !widget.gpsDisabled ? "" :
    "GPS is disabled, please enable it in device settings.";
    if(gpsEnabledMessage.isNotEmpty) {
      list.add(ListTile(title: const Text("GPS"),
          leading: const Icon(Icons.gps_off_sharp),
          subtitle: Text(gpsEnabledMessage),
          dense: true,
          onTap: () => {Geolocator.openLocationSettings()}));
    }

    String dataAvailableMessage = !widget.chartsMissing ? "" :
    "Critical data is missing, please download the databases and some charts using the Download menu.";
    if(dataAvailableMessage.isNotEmpty) {
      list.add(ListTile(title: const Text("Data"),
          leading: const Icon(Icons.download),
          subtitle: Text(dataAvailableMessage),
          dense: true,
          onTap: () => {Navigator.pushNamed(context, '/download')}));
    }

    String dataCurrentMessage = !widget.dataExpired ? "" :
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