import 'package:avaremp/aircraft.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import 'constants.dart';

class AircraftScreen extends StatefulWidget {
  const AircraftScreen({super.key});
  @override
  AircraftScreenState createState() => AircraftScreenState();
}

class AircraftScreenState extends State<AircraftScreen> {

  List<Aircraft>? _currentItems;

  Widget _makeContent(List<Aircraft>? items) {

    if(null == items) {
      return Container();
    }

    return ListView.separated(
      itemCount: items.length,
      padding: const EdgeInsets.all(5),
      itemBuilder: (context, index) {
        final item = items[index];
        return Dismissible( // able to delete with swipe
          background: Container(alignment: Alignment.centerRight,child: const Icon(Icons.delete_forever),),
          key: Key(Storage().getKey()),
          direction: DismissDirection.endToStart,
          onDismissed:(direction) async {
            // Remove the item from the data source.
            await UserDatabaseHelper.db.deleteAircraft(item.tail);
            setState(() {
              items.removeAt(index);
            });
          },
          child: ListTile(
              title: Row(
                  children:[
                    Text(item.tail),
                    TextButton(
                        onPressed: () {
                        },
                        child: const Text("Modify")
                    )
                  ]
              ),
              subtitle: Text(item.type),
              dense: true,
              isThreeLine: true,
              leading: Icon(MdiIcons.airplane),
              trailing: Text(item.pic),
          ),
        );
      },
      separatorBuilder: (context, index) {
        return const Divider();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          backgroundColor: Constants.appBarBackgroundColor,
          title: const Text("Aircraft"),
          actions: [TextButton(onPressed: () {}, child: const Text("New"))],
        ),
        body: FutureBuilder(
          future: UserDatabaseHelper.db.getAllAircraft(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              _currentItems = snapshot.data;
            }
            return _makeContent(_currentItems);
          },
    ));
  }
  
}
