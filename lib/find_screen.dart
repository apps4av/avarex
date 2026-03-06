import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/utils/geo_calculations.dart';
import 'package:avaremp/map_screen.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'constants.dart';
import 'package:avaremp/destination/destination.dart';
import 'io/gps.dart';
import 'data/main_database_helper.dart';
import 'main_screen.dart';

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

  String _getFilterLabel() {
    if (_searchText.isNotEmpty) return "Search Results";
    if (_recent) return "Recent";
    if (_runwayLength == 0) return "Nearest";
    return "Nearest ${_runwayLength ~/ 1000}K+ Runway";
  }

  @override
  Widget build(BuildContext context) {
    bool searching = true;
    return FutureBuilder(
      future: _searchText.isNotEmpty? (MainDatabaseHelper.db.findDestinations(_searchText)) : (_recent ? UserDatabaseHelper.db.getRecent() : MainDatabaseHelper.db.findNearestAirportsWithRunways(Gps.toLatLng(Storage().position), _runwayLength)),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          _currentItems = snapshot.data;
          searching = false;
        }
        return _makeContent(_currentItems, searching);
      },
    );
  }

  Widget _makeContent(List<Destination>? items, bool searching) {

    GeoCalculations geo = GeoCalculations();
    LatLng position = Gps.toLatLng(Storage().position);

    return Container(
        padding: EdgeInsets.fromLTRB(10, 0, 10, Constants.bottomPaddingSize(context)),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: TextFormField(
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: "Search",
                  hintText: "Airport, navaid, fix, address...",
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchText.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _searchText = "";
                            });
                          },
                        )
                      : null,
                  isDense: true,
                ),
                onChanged: (value) {
                  setState(() {
                    _searchText = value;
                    items != null && items.isNotEmpty ? widget.controller.jumpTo(0) : ();
                  });
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Text(
                    _getFilterLabel(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (items != null)
                    Text(
                      "(${items.length})",
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                    ),
                  const Spacer(),
                  if (searching)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
            ),
            Expanded(
              child: items == null || items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _searchText.isNotEmpty ? Icons.search_off : Icons.location_searching,
                            size: 48,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _searchText.isNotEmpty ? "No results found" : (_recent ? "No recent destinations" : "No airports found"),
                            style: TextStyle(color: Theme.of(context).colorScheme.outline),
                          ),
                          if (_searchText.isEmpty && _recent)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                "Search for a destination above",
                                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                              ),
                            ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: items.length,
                      controller: widget.controller,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final bearing = GeoCalculations.getMagneticHeading(
                          geo.calculateBearing(position, item.coordinate),
                          item.geoVariation ?? 0,
                        ).round();
                        final distance = geo.calculateDistance(item.coordinate, position).round();

                        return Dismissible(
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            color: Colors.red.withAlpha(50),
                            child: const Icon(Icons.delete, color: Colors.red),
                          ),
                          key: Key(Storage().getKey()),
                          direction: DismissDirection.endToStart,
                          onDismissed: (direction) {
                            UserDatabaseHelper.db.deleteRecent(item).then((value) {
                              setState(() {
                                items.removeAt(index);
                              });
                            });
                          },
                          child: Card(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            child: ListTile(
                              leading: DestinationFactory.getIcon(item.type, Theme.of(context).colorScheme.primary),
                              title: Row(
                                children: [
                                  Text(
                                    item.locationID,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item.facilityName,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      item.type,
                                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    ),
                                  ),
                                  if (item.type == Destination.typeGps)
                                    IconButton(
                                      icon: Icon(Icons.edit, size: 16, color: Theme.of(context).colorScheme.outline),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (BuildContext context) {
                                            return AlertDialog(
                                              title: const Text('Edit Name'),
                                              content: TextField(
                                                onSubmitted: (value) {
                                                  setState(() {
                                                    Destination d = GpsDestination(
                                                      locationID: item.locationID,
                                                      type: item.type,
                                                      facilityName: value,
                                                      coordinate: item.coordinate,
                                                    );
                                                    UserDatabaseHelper.db.addRecent(d);
                                                  });
                                                  Navigator.of(context).pop();
                                                },
                                                controller: TextEditingController()..text = item.facilityName,
                                                decoration: const InputDecoration(
                                                  border: OutlineInputBorder(),
                                                  labelText: 'Facility Name',
                                                ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.of(context).pop(),
                                                  child: const Text('Cancel'),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                      },
                                    ),
                                ],
                              ),
                              trailing: InkWell(
                                onTap: () {
                                  UserDatabaseHelper.db.addRecent(item);
                                  MapScreenState.showOnMap(item.coordinate);
                                  MainScreenState.gotoMap();
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        "$bearing\u00b0",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                      Text(
                                        "${distance}nm",
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              onTap: () {
                                setState(() {
                                  MapScreenState.showDestination(context, [item]);
                                });
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    TextButton(
                      style: _recent && _searchText.isEmpty
                          ? TextButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primaryContainer)
                          : null,
                      onPressed: () {
                        setState(() {
                          _recent = true;
                          _searchText = "";
                        });
                      },
                      child: const Text("Recent"),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      style: !_recent && _runwayLength == 0 && _searchText.isEmpty
                          ? TextButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primaryContainer)
                          : null,
                      onPressed: () {
                        setState(() {
                          _recent = false;
                          _runwayLength = 0;
                          _searchText = "";
                        });
                      },
                      child: const Text("Nearest"),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      style: !_recent && _runwayLength == 2000 && _searchText.isEmpty
                          ? TextButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primaryContainer)
                          : null,
                      onPressed: () {
                        setState(() {
                          _runwayLength = 2000;
                          _recent = false;
                          _searchText = "";
                        });
                      },
                      child: const Text("Nearest 2K"),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      style: !_recent && _runwayLength == 4000 && _searchText.isEmpty
                          ? TextButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primaryContainer)
                          : null,
                      onPressed: () {
                        setState(() {
                          _runwayLength = 4000;
                          _recent = false;
                          _searchText = "";
                        });
                      },
                      child: const Text("Nearest 4K"),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
    );
  }
}
