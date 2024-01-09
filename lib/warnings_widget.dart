
import 'dart:core';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

class WarningsButtonWidget extends StatefulWidget {
  const WarningsButtonWidget({super.key, required this.warning});

  final bool warning;

  @override
  State<StatefulWidget> createState() => WarningsButtonWidgetState();
}

// a button to show if there is an issue
class WarningsButtonWidgetState extends State<WarningsButtonWidget> {


  @override
  Widget build(BuildContext context) {

    if(widget.warning) {
      return IconButton(
        icon: Icon(MdiIcons.alertCircle, color: Colors.red, size: 48),
          onPressed: () {
            Scaffold.of(context).openEndDrawer();
          },
        );
    }

    return(Container());
  }
}

class WarningsWidget extends StatefulWidget {
  const WarningsWidget({super.key, required this.gpsNotPermitted,
    required this.gpsDisabled, required this.chartsMissing, required this.dataExpired});

  final bool gpsNotPermitted;
  final bool gpsDisabled;
  final bool chartsMissing;
  final bool dataExpired;

  @override
  State<StatefulWidget> createState() => WarningsWidgetState();
}

class WarningsWidgetState extends State<WarningsWidget> {

  @override
  Widget build(BuildContext context) {

    List<ListTile> list = [
      ListTile(
        title: const Text("Issues", style: TextStyle(fontWeight: FontWeight.w900)),
        subtitle: const Text("Tapping on the issue will help you resolve it."),
        leading: Icon(MdiIcons.alertCircle, color: Colors.red,), dense: false,)];

    String gpsPermissionMessage = !widget.gpsNotPermitted ? "" :
    "GPS permission is denied, please enable it in device settings.";
    if(gpsPermissionMessage.isNotEmpty) {
      list.add(ListTile(title: const Text("GPS Permission"),
          leading: const Icon(Icons.gpp_good_sharp),
          subtitle: Text(gpsPermissionMessage),
          dense: true,
          onTap: () { Geolocator.openAppSettings(); Scaffold.of(context).closeEndDrawer();}));
    }

    String gpsEnabledMessage = !widget.gpsDisabled ? "" :
    "GPS is disabled, please enable it in device settings.";
    if(gpsEnabledMessage.isNotEmpty) {
      list.add(ListTile(title: const Text("GPS"),
          leading: const Icon(Icons.gps_off_sharp),
          subtitle: Text(gpsEnabledMessage),
          dense: true,
          onTap: () {Geolocator.openLocationSettings(); Scaffold.of(context).closeEndDrawer();}));
    }

    String dataAvailableMessage = !widget.chartsMissing ? "" :
    "Critical data is missing, please download the databases and some charts using the Download menu.";
    if(dataAvailableMessage.isNotEmpty) {
      list.add(ListTile(title: const Text("Data"),
          leading: const Icon(Icons.download),
          subtitle: Text(dataAvailableMessage),
          dense: true,
          onTap: () {Navigator.pushNamed(context, '/download'); Scaffold.of(context).closeEndDrawer();}));
    }

    String dataCurrentMessage = !widget.dataExpired ? "" :
    "Some or all the data has expired, please update the data using the Download menu.";
    if(dataCurrentMessage.isNotEmpty) {
      list.add(ListTile(title: const Text("Update"),
          leading: const Icon(Icons.update),
          subtitle: Text(dataCurrentMessage),
          dense: true,
          onTap: () {Navigator.pushNamed(context, '/download'); Scaffold.of(context).closeEndDrawer();}));
    }

    return Drawer(
        child: ListView(children: list,
        )
    );
  }

}