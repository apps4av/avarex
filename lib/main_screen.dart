import 'package:avaremp/plate_screen.dart';
import 'package:flutter/material.dart';
import 'map_screen.dart';
import 'find_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0; // for various tab screens

  // define tabs here
  static final List<Widget> _widgetOptions = <Widget>[
    const MapScreen(),
    const PlateScreen(),
    const FindScreen(),
  ];

  void mOnItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Future<bool> _onPop(BuildContext context) async {
    bool? exitResult = await showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Do you really want to exit the app?',
                style: Theme.of(context).textTheme.headlineSmall,
              )
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('CANCEL'),
                ),

                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('EXIT'),
                ),
              ],
            ),
          ],
        );
      },
    );
    return exitResult ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(onWillPop: () => _onPop(context),
      child:Scaffold(
        extendBodyBehindAppBar: true,
        extendBody: true,
        appBar: AppBar(
          actions: [
            IconButton(icon: const Icon(Icons.download), padding: const EdgeInsets.fromLTRB(15, 0, 15, 0), onPressed: () => Navigator.pushNamed(context, '/download')),
            IconButton(icon: const Icon(Icons.settings), padding: const EdgeInsets.fromLTRB(15, 0, 15, 0), onPressed: () => Navigator.pushNamed(context, '/settings')),
          ],
          backgroundColor: Theme.of(context).dialogBackgroundColor.withAlpha(156),
        ),
        body: Center(
          child: _widgetOptions.elementAt(_selectedIndex),
        ),

        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: Theme.of(context).dialogBackgroundColor.withAlpha(156),
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.map),
              label: 'MAP',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.book),
              label: 'PLATE',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.search),
              label: 'FIND',
            ),
          ],
          currentIndex: _selectedIndex,
          onTap: mOnItemTapped,
        ),
      )
    );
  }
}

