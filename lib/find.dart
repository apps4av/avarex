import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import 'main_database_helper.dart';

class Find extends SearchDelegate {

  List<FindDestination>? curItems;

  @override
  List<Widget>? buildActions(BuildContext context) => [];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(onPressed: () {close(context, 0);}, icon: const Icon(Icons.arrow_back_outlined));

  @override
  Widget buildResults(BuildContext context) => Container();

  @override
  Widget buildSuggestions(BuildContext context) {

    return FutureBuilder(
      future: MainDatabaseHelper.db.findDestinations(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          curItems = snapshot.data;
        }
        return makeContent(curItems);
      },
    );
  }

  Widget makeContent(List<FindDestination>? items) {
    if(null == items || query.isEmpty) {
      return Container();
    }
    return Scaffold(
        body: ListView.separated(
          itemCount: items.length,
          padding: const EdgeInsets.all(30),
          itemBuilder: (context, index) {
            return ListTile(
              title: Text(items[index].id),
              subtitle: Text("${items[index].name} - ${items[index].type}"),
              leading: TypeIcons.getIcon(items[index].type),
              onTap: () {},
              onLongPress: () {},
            );
          },
          separatorBuilder: (context, index) {
            return const Divider();
          },
        )
    );

  }
}

class TypeIcons {

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
    else if(
    type == "AIRPORT" ||
        type == "SEAPLANE BAS" ||
        type == "HELIPORT" ||
        type == "ULTRALIGHT" ||
        type == "GLIDERPORT" ||
        type == "BALLOONPORT") {
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

