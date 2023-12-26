
import 'package:avaremp/plate_screen.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'constants.dart';
import 'instrument_list.dart';
import 'map_screen.dart';
import 'find_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> {

  static const tabLocationMap = 0;
  static const tabLocationPlates = 1;
  static const tabLocationFind = 2;

  int _selectedIndex = tabLocationMap; // for various tab screens

  // define tabs here
  final List<Widget> _widgetOptions = [];

  MainScreenState() {
    _widgetOptions.insert(tabLocationMap, const MapScreen());
    _widgetOptions.insert(tabLocationPlates, const PlateScreen());
    _widgetOptions.insert(tabLocationFind, const FindScreen());
  }

  void mOnItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  static void gotoPlate() {
    final BottomNavigationBar navigationBar = Storage()
        .globalKeyBottomNavigationBar.currentWidget as BottomNavigationBar;
    navigationBar.onTap!(tabLocationPlates); // go to plate screen
  }

  static void gotoMap() {
    final BottomNavigationBar navigationBar = Storage()
        .globalKeyBottomNavigationBar.currentWidget as BottomNavigationBar;
    navigationBar.onTap!(tabLocationMap); // go to plate screen
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
              alignment: Alignment.centerLeft,
              child: const Text(
                'Do you really want to exit the app?',
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
        drawer: Drawer(
          child: ListView(children: [
            ListTile(title: const Text("avareMp"), subtitle: const Text("0.0.1"), trailing: IconButton(icon: const Icon(Icons.help), onPressed: () {  },), leading: Image.asset("assets/images/logo.png", width: 48, height: 48,)),
            ListTile(title: const Text("Settings"), leading: const Icon(Icons.settings), onTap: () => Navigator.pushNamed(context, '/settings')),
            ListTile(title: const Text("Download"), leading: const Icon(Icons.download), onTap: () => Navigator.pushNamed(context, '/download')),
          ],
        )),
        appBar: AppBar(
          leadingWidth: Constants.screenWidth(context) / 10, // for safe area
          backgroundColor: Constants.appBarBackgroundColor,
          iconTheme: const IconThemeData(color: Constants.appBarButtonColor),
          flexibleSpace: SafeArea(
            minimum: EdgeInsets.fromLTRB(Constants.screenWidth(context) / 10, 0, 0, 0),
            child: const InstrumentList()
          ),
        ),
        body: Center(
          child: _widgetOptions.elementAt(_selectedIndex),
        ),
        bottomNavigationBar: BottomNavigationBar(
          key: Storage().globalKeyBottomNavigationBar,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Constants.bottomNavBarBackgroundColor,
          selectedItemColor: Constants.bottomNavBarButtonColor,
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

