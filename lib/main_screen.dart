
import 'package:avaremp/plan_screen.dart';
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

class MainScreenState extends State<MainScreen> with WidgetsBindingObserver { // for checking GPS state on app resume

  static const tabLocationMap = 0;
  static const tabLocationPlates = 1;
  static const tabLocationPlan = 2;
  static const tabLocationFind = 3;

  int _selectedIndex = tabLocationMap; // for various tab screens

  // define tabs here
  final List<Widget> _widgetOptions = [];

  MainScreenState() {
    _widgetOptions.insert(tabLocationMap, const MapScreen());
    _widgetOptions.insert(tabLocationPlates, const PlateScreen());
    _widgetOptions.insert(tabLocationPlan, const PlanScreen());
    _widgetOptions.insert(tabLocationFind, FindScreen());
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

  static void gotoPlan() {
    final BottomNavigationBar navigationBar = Storage()
        .globalKeyBottomNavigationBar.currentWidget as BottomNavigationBar;
    navigationBar.onTap!(tabLocationPlan); // go to plate screen
  }

  static void gotoMap() {
    final BottomNavigationBar navigationBar = Storage()
        .globalKeyBottomNavigationBar.currentWidget as BottomNavigationBar;
    navigationBar.onTap!(tabLocationMap); // go to plate screen
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: false,
      extendBody: true,
      endDrawerEnableOpenDragGesture: false,
      drawerEnableOpenDragGesture: false,
      drawer: Padding(padding: EdgeInsets.fromLTRB(0, Constants.screenHeight(context) / 8, 0, Constants.screenHeight(context) / 10),
        child: Drawer(
          child: ListView(children: [
            ListTile(title: const Text("avareMp"), subtitle: const Text("0.0.1"), trailing: IconButton(icon: const Icon(Icons.help), onPressed: () { },), leading: Image.asset("assets/images/logo.png", width: 48, height: 48,), dense: true,),
            ListTile(title: const Text("Download"), leading: const Icon(Icons.download), onTap: () => Navigator.pushNamed(context, '/download'), dense: true,),
          ],
        ))
      ),
      appBar: AppBar(
        actions: [Container()], // do not show warnings button
        leading: Container(),
        backgroundColor: Constants.appBarBackgroundColor,
        iconTheme: const IconThemeData(color: Constants.appBarButtonColor),
        flexibleSpace: const SafeArea(
          minimum: EdgeInsets.fromLTRB(0, 0, 0, 0),
          child: InstrumentList()
        ),
      ),
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(5),
        child:BottomNavigationBar(
          unselectedFontSize: 10,
          selectedFontSize: 14,
          key: Storage().globalKeyBottomNavigationBar,
          type: BottomNavigationBarType.fixed,
          backgroundColor: Constants.bottomNavBarBackgroundColor,
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
              icon: Icon(Icons.route),
              label: 'PLAN',
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // start GPS
        Storage().startGps();
        break;
      default:
        Storage().stopGps();
        break;
    }
  }
}

