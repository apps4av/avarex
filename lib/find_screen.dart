import 'package:avaremp/longpress_widget.dart';
import 'package:avaremp/main_screen.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/user_database_helper.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import 'airport.dart';
import 'destination.dart';
import 'main_database_helper.dart';

class FindScreen extends StatefulWidget {
  FindScreen({super.key});
  @override
  State<StatefulWidget> createState() => FindScreenState();

  final ScrollController controller = ScrollController();

}

class FindScreenState extends State<FindScreen> {

  List<Destination>? _curItems;
  String _searchText = "";
  double? _height;

  Future<bool> showDestination(BuildContext context, Destination destination) async {
    bool? exitResult = await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return LongPressWidget(destination: destination);
      },
    );
    return exitResult ?? false;
  }


  @override
  Widget build(BuildContext context) {
    _height = Scaffold.of(context).appBarMaxHeight;
    bool searching = true;
    return FutureBuilder(
      future: _searchText.isEmpty? UserDatabaseHelper.db.getRecent() : MainDatabaseHelper.db.findDestinations(_searchText), // find recents when not searching
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          _curItems = snapshot.data;
          searching = false;
        }
        return _makeContent(_curItems, searching);
      },
    );
  }

  void addRecent(Destination d) {
    UserDatabaseHelper.db.addRecent(d);
  }

  Widget _makeContent(List<Destination>? items, bool searching) {

    return Container(
        padding: EdgeInsets.fromLTRB(10, _height ?? 0, 20, 0),
        child : Stack(children: [
          Align(alignment: Alignment.center, child: searching? const CircularProgressIndicator() : const SizedBox(width: 0, height:  0,),), // search indication
          Column (children: [
            Expanded(
                flex: 3,
                child: Container(
                  alignment: Alignment.bottomLeft,
                  child: TextFormField(
                    onChanged: (value) {
                      setState(() {
                        _searchText = value;
                        searching = true;
                        items != null && items.isNotEmpty ? widget.controller.jumpTo(0) : ();
                      });
                    },
                    decoration: const InputDecoration(border: UnderlineInputBorder(), labelText: 'Find')
                  )
                )
            ),
            Expanded(
                flex: 20,
                child: null == items ? Container() : ListView.separated(
                  itemCount: items.length,
                  padding: const EdgeInsets.all(5),
                  controller: widget.controller,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Dismissible( // able to delete with swipe
                      background: Container(alignment: Alignment.centerRight,child: const Icon(Icons.delete_forever),),
                      key: Key(item.facilityName),
                      direction: DismissDirection.endToStart,
                      onDismissed:(direction) async {
                        // Remove the item from the data source.
                        await UserDatabaseHelper.db.deleteRecent(item);
                        setState(() {
                          items.removeAt(index);
                        });
                      },
                      child: ListTile(
                        title: Text(item.locationID),
                        subtitle: Text("${item.facilityName} ( ${item.type} )"),
                        dense: true,
                        isThreeLine: true,
                        onTap: () {
                          UserDatabaseHelper.db.addRecent(item);
                          Storage().settings.setCenterLongitude(item.coordinate.longitude.value);
                          Storage().settings.setCenterLatitude(item.coordinate.latitude.value);
                          MainScreenState.gotoMap();
                        },
                        onLongPress: () {
                          setState(() {
                            if(Airport.isAirport(item.type)) {
                              showDestination(context, item);
                            }
                          });
                        },
                        leading: _TypeIcons.getIcon(item.type)
                      ),
                    );
                  },
                  separatorBuilder: (context, index) {
                    return const Divider();
                  },
                )),
            ]
          )
        ]
        )
      );
  }
}

class _TypeIcons {

  static Icon getIcon(String type) {
    if(type == "TACAN" ||
        type == "NDB/DME" ||
        type == "MARINE NDB" ||
        type == "UHF/NDB" ||
        type == "NDB" ||
        type == "VOR/DME" ||
        type == "VOT" ||
        type == "VORTAC" ||
        type == "FAN MARKER" ||
        type == "VOR") {

      return Icon(MdiIcons.hexagonOutline);
    }
    else if(Airport.isAirport(type)) {
      return Icon(MdiIcons.airport);
    }
    else if(
    type == "YREP-PT" ||
        type == "YRNAV-WP" ||
        type == "NARTCC-BDRY" ||
        type == "NAWY-INTXN" ||
        type == "NTURN-PT" ||
        type == "YWAYPOINT" ||
        type == "YMIL-REP-PT" ||
        type == "YCOORDN-FIX" ||
        type == "YMIL-WAYPOINT" ||
        type == "YNRS-WAYPOINT" ||
        type == "YVFR-WP" ||
        type == "YGPS-WP" ||
        type == "YCNF" ||
        type == "YRADAR" ||
        type == "NDME-FIX" ||
        type == "NNOT-ASSIGNED" ||
        type == "NDP-TRANS-XING" ||
        type == "NSTAR-TRANS-XIN" ||
        type == "NBRG-INTXN") {
      return Icon(MdiIcons.triangleOutline);
    }
    else if(type == "GPS") {
      return Icon(MdiIcons.crosshairsGps);
    }
    else if(type == "Maps") {
      return Icon(MdiIcons.mapMarker);
    }
    else if(type == "UDW") {
      return Icon(MdiIcons.flagTriangle);
    }
    return Icon(MdiIcons.help);
  }
}

