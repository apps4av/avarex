
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
        icon: CircleAvatar(backgroundColor: Colors.black, radius: 20, child: Icon(MdiIcons.alertCircle, color: Colors.red, size: 40)),
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
    required this.gpsDisabled, required this.chartsMissing, required this.dataExpired, required this.signed, required this.gpsNoLock, required this.exceptions});

  final bool gpsNotPermitted;
  final bool gpsDisabled;
  final bool chartsMissing;
  final bool dataExpired;
  final bool signed;
  final bool gpsNoLock;
  final List<String> exceptions;

  @override
  State<StatefulWidget> createState() => WarningsWidgetState();
}

class WarningsWidgetState extends State<WarningsWidget> {

  @override
  Widget build(BuildContext context) {

    List<ListTile> list = [
      ListTile(
        title: const Text("Issues", style: TextStyle(fontWeight: FontWeight.w900)),
        subtitle: const Text("Tapping on the issue may help you resolve it."),
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

    String gpsLockedMessage = !widget.gpsNoLock ? "" :
    "GPS lock cannot be obtained. Move to an open area where GPS signal can be received.";
    if(gpsLockedMessage.isNotEmpty) {
      list.add(ListTile(title: const Text("GPS Signal"),
          leading: const Icon(Icons.gps_not_fixed),
          subtitle: Text(gpsLockedMessage),
          dense: true,
          onTap: () {Navigator.pop(context);}));
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
    "Some or all of your data has expired. Tap this text or use the Download menu to Update.";
    if(dataCurrentMessage.isNotEmpty) {
      list.add(ListTile(title: const Text("Update"),
          leading: const Icon(Icons.update),
          subtitle: Text(dataCurrentMessage),
          dense: true,
          onTap: () {Navigator.pushNamed(context, '/download'); Scaffold.of(context).closeEndDrawer();}));
    }

    String signMessage = widget.signed ? "" :
    "You must sign the Terms of Use to use this software.";
    if(signMessage.isNotEmpty) {
      list.add(ListTile(title: const Text("Sign Terms of Use"),
          leading: const Icon(Icons.verified_user_outlined),
          subtitle: Text(signMessage),
          dense: true,
          onTap: () {Navigator.pushNamed(context, '/terms'); Scaffold.of(context).closeEndDrawer();}));
    }

    for(String exception in widget.exceptions) {
      list.add(ListTile(title: const Text("Notice"),
          leading: const Icon(Icons.message),
          subtitle: Text(exception),
          dense: true,
          onTap: () {widget.exceptions.remove(exception); Navigator.pop(context);}));
    }

    return Drawer(
        child: ListView(children: list,
        )
    );
  }

}