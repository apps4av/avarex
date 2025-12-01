import 'package:avaremp/onboarding_screen.dart';
import 'package:avaremp/plan/plan_screen.dart';
import 'package:avaremp/plate_screen.dart';
import 'package:avaremp/services/revenue_cat.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'constants.dart';
import 'map_screen.dart';
import 'find_screen.dart';
import 'package:yaml/yaml.dart';
import 'package:flutter/services.dart';

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

  bool _drawerOpen = false;
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if(didPop) {
          return;
        }
        else {
          if(_selectedIndex != tabLocationMap) {
            gotoMap(); // go to map on back
          }
          else if(_drawerOpen) {
            Navigator.pop(context); // close drawer
          }
          else {
            showDialog(context: context, builder: (BuildContext context) {
              return AlertDialog(
                title: const Text('Exit App?'),
                content: const Text("Do you want to exit this app?"),
                actions: <Widget>[
                  TextButton(
                    child: const Text('Yes'),
                    onPressed: () {
                      SystemNavigator.pop();
                    },
                  ),
                  TextButton(
                    child: const Text('No'),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              );
            });
          }
        }
      },
      child: Scaffold(
        onDrawerChanged: (isOpened) {
          _drawerOpen = isOpened;
        },
        appBar: AppBar(toolbarHeight: 0,), // no appbar needed but use it for safe area
        extendBodyBehindAppBar: false,
        extendBody: true,
        endDrawerEnableOpenDragGesture: false,
        drawerEnableOpenDragGesture: false,
        drawer: Padding(padding: EdgeInsets.fromLTRB(0, Constants.screenHeight(context) / 8, 0, Constants.screenHeight(context) / 12),
          child: Drawer(
            child: ListView(children: [
              ListTile(
                title: const Text("AvareX"),
                subtitle: FutureBuilder( // get version from pubspec.yaml
                    future: rootBundle.loadString("pubspec.yaml"),
                    builder: (context, snapshot) {
                      String version = "Unknown";
                      if (snapshot.hasData) {
                        var yaml = loadYaml(snapshot.data!);
                        version = yaml["version"];
                      }
                      return Text('Version: $version');
                    }),
                trailing: IconButton(icon: Icon(MdiIcons.exitToApp),
                  onPressed: () {
                    Storage().settings.setIntro(true);
                    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const OnBoardingScreen()),);
                  },
                ),
                leading: Image.asset("assets/images/logo.png", width: 48, height: 48,), dense: true,),
              ListTile(title: const Text("Download"), leading: const Icon(Icons.download), onTap: () {Navigator.pop(context); Navigator.pushNamed(context, '/download');}, dense: true,),
              ListTile(title: const Text("Documents"), leading: Icon(MdiIcons.fileDocument), onTap: () {Navigator.pop(context); Navigator.pushNamed(context, '/documents');}, dense: true,),
              ListTile(title: const Text("Aircraft"), leading: Icon(MdiIcons.airplane), onTap: () {Navigator.pop(context); Navigator.pushNamed(context, '/aircraft');}, dense: true,),
              ListTile(title: const Text("Check Lists"), leading: Icon(MdiIcons.check), onTap: () {Navigator.pop(context); Navigator.pushNamed(context, '/checklists');}, dense: true,),
              ListTile(title: const Text("W&B"), leading: Icon(MdiIcons.scaleUnbalanced), onTap: () {Navigator.pop(context); Navigator.pushNamed(context, '/wnb');}, dense: true,),
              ListTile(title: const Text("Log Book"), leading: Icon(Icons.notes), onTap: () {Navigator.pop(context); Navigator.pushNamed(context, '/logbook');}, dense: true,),
              if(Constants.shouldShowBluetoothSpp) ListTile(title: const Text("IO"), leading: const Icon(Icons.compare_arrows_rounded), onTap: () {Navigator.pop(context); Navigator.pushNamed(context, '/io');}, dense: true,),
              if(Constants.shouldShowDonation) ListTile(title: const Text("Donate"), leading: const Icon(Icons.celebration), onTap: () {Navigator.pushNamed(context, '/donate');}, dense: true,),
              if(Constants.shouldShowProServices) ListTile(title: const Text("Pro Services"), leading: Icon(MdiIcons.accountTieHat),
                onTap: () async {
                  try {
                    if (Constants.shouldShowProServices) {
                      RevenueCatService.presentPaywallIfNeeded().then((
                          entitled) {
                        if (mounted) {
                          if (entitled) {
                            Navigator.pop(context);
                            Navigator.pushNamed(context, '/pro');
                          }
                          else {
                            Navigator.pop(context);
                            MapScreenState.showToast(context,
                                "Unable to start the Pro services due to system error.",
                                Icon(Icons.info, color: Colors.red), 3);
                          }
                        }
                      });
                    }
                  }
                  catch(e) {
                    Storage().setException("Unable to initialize Pro Services: $e");
                  }
                },
                dense: true,),
            ],
          ))
        ),
        body: Center(
          child: _widgetOptions.elementAt(_selectedIndex),
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.all(5),
          child:BottomNavigationBar(
            key: Storage().globalKeyBottomNavigationBar,
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.transparent,
            showUnselectedLabels: false,
            selectedItemColor: Colors.white,
            items: <BottomNavigationBarItem>[
              BottomNavigationBarItem(
                icon: Icon(Icons.map, size: 24, color: Constants.bottomNavBarIconColor, shadows: const [Shadow(offset: Offset(1, 1))]),
                label: 'MAP',
                tooltip: "View the maps and overlays",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.book, size: 24, color: Constants.bottomNavBarIconColor, shadows: const [Shadow(offset: Offset(1, 1))]),
                label: 'PLATE',
                tooltip: "Look at approach plates, airport diagrams, CSUP, Minimums, etc.",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.route, size: 24, color: Constants.bottomNavBarIconColor, shadows: const [Shadow(offset: Offset(1, 1))]),
                label: 'PLAN',
                tooltip: "Create a flight plan",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.search, size: 24, color: Constants.bottomNavBarIconColor, shadows: const [Shadow(offset: Offset(1, 1))],),
                label: 'FIND',
                tooltip: "Search for Airports, NavAids, etc.",
              ),
            ],
            currentIndex: _selectedIndex,
            onTap: mOnItemTapped,
          ),
        )
      )
    );
  }

  @override
  void dispose() {
    Storage().stopIO();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    Storage().startIO();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        // start GPS
        Storage().startIO();
        break;
      default:
        Storage().stopIO();
        break;
    }
  }
}

