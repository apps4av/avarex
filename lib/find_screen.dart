import 'package:avaremp/geo_calculations.dart';
import 'package:avaremp/longpress_widget.dart';
import 'package:avaremp/main_screen.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'chart.dart';
import 'constants.dart';
import 'destination.dart';
import 'gps.dart';
import 'data/main_database_helper.dart';

class FindScreen extends StatefulWidget {
  FindScreen({super.key});
  @override
  State<StatefulWidget> createState() => FindScreenState();

  final ScrollController controller = ScrollController();
}

class FindScreenState extends State<FindScreen> {

  List<Destination>? _currentItems;
  String _searchText = "";
  bool _recent = true;
  int _runwayLength = 0;

  Future<bool> showDestination(BuildContext context, Destination destination) async {
    bool? exitResult = await showModalBottomSheet(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return LongPressWidget(destination: destination);
      },
    );
    return exitResult ?? false;
  }

  @override
  Widget build(BuildContext context) {
    bool searching = true;
    return FutureBuilder(
      future: _searchText.isNotEmpty? (MainDatabaseHelper.db.findDestinations(_searchText)) : (_recent ? UserDatabaseHelper.db.getRecent() : MainDatabaseHelper.db.findNearestAirportsWithRunways(Gps.toLatLng(Storage().position), _runwayLength)), // find recent when not searching
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          _currentItems = snapshot.data;
          searching = false;
        }
        return _makeContent(_currentItems, searching);
      },
    );
  }

  String _filterToDescription() {
    if(_searchText.startsWith(" ")) {
      return "Airport by ID ( )";
    }
    else if(_searchText.startsWith(".")) {
      return "Navigation AID (.)";
    }
    else if(_searchText.startsWith(",")) {
      return "Fix (,)";
    }
    else if(_searchText.startsWith("!")) {
      return "Airport by Name (!)";
    }
    return("( .,!)");
  }

  Widget _makeContent(List<Destination>? items, bool searching) {

    GeoCalculations geo = GeoCalculations();
    LatLng position = Gps.toLatLng(Storage().position);

    return Container(
        padding: EdgeInsets.fromLTRB(10, 0, 20, Constants.bottomPaddingSize(context)),
        child : Stack(children: [
          Align(alignment: Alignment.center, child: searching? const CircularProgressIndicator() : const SizedBox(width: 0, height:  0,),), // search indication
          Column (children: [
            Expanded(
                flex: 2,
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
                    decoration: InputDecoration(border: const UnderlineInputBorder(), labelText: 'Find ${_filterToDescription()}')
                  )
                )
            ),
            Expanded(
                flex: 7,
                child: null == items ? Container() : ListView.separated(
                  itemCount: items.length,
                  padding: const EdgeInsets.all(5),
                  controller: widget.controller,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Dismissible( // able to delete with swipe
                      background: Container(alignment: Alignment.centerRight,child: const Icon(Icons.delete_forever),),
                      key: Key(Storage().getKey()),
                      direction: DismissDirection.endToStart,
                      onDismissed:(direction) async {
                        // Remove the item from the data source.
                        await UserDatabaseHelper.db.deleteRecent(item);
                        setState(() {
                          items.removeAt(index);
                        });
                      },
                      child: ListTile(
                        title: Row(
                            children:[
                              Text(item.locationID),
                              TextButton(
                                onPressed: () {
                                  UserDatabaseHelper.db.addRecent(item);
                                  Storage().settings.setCenterLongitude(item.coordinate.longitude);
                                  Storage().settings.setCenterLatitude(item.coordinate.latitude);
                                  Storage().settings.setZoom(ChartCategory.chartTypeToZoom(Storage().settings.getChartType()).toDouble());
                                  MainScreenState.gotoMap();
                                },
                                child: const Text("Show")
                              )
                            ]
                        ),
                        subtitle: Text("${item.facilityName} ( ${item.type} )"),
                        dense: true,
                        isThreeLine: true,
                        trailing: Text("${geo.calculateDistance(item.coordinate, position).round()}NM\n${GeoCalculations.getMagneticHeading(geo.calculateBearing(position, item.coordinate), geo.getVariation(item.coordinate)).round()}\u00b0"),
                        onLongPress: () {
                          setState(() {
                            showDestination(context, item);
                          });
                        },
                        leading: DestinationFactory.getIcon(item.type, null)
                      ),
                    );
                  },
                  separatorBuilder: (context, index) {
                    return const Divider();
                  },
                )
            ),
            Expanded(
              flex: 2,
              child: Row(children:[
                TextButton(onPressed: () {
                  setState(() {
                    _recent = true;
                  });
                }, child: const Text("Recent"),),
                TextButton(onPressed: () {
                  setState(() {
                    _recent = false;
                    _runwayLength = 0;
                  });
                }, child: const Text("Nearest"),),
                TextButton(onPressed: () {
                  setState(() {
                    _runwayLength = 2000;
                    _recent = false;
                  });
                }, child: const Text("Nearest 2K"),),
                TextButton(onPressed: () {
                  setState(() {
                    _runwayLength = 4000;
                    _recent = false;
                  });
                }, child: const Text("Nearest 4K"),),
              ]
            ))
          ]),
        ]
      )
    );
  }
}

