import 'package:avaremp/onboarding_screen.dart';
import 'package:avaremp/plan/plan_screen.dart';
import 'package:avaremp/plate_screen.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/utils/pdf_viewer.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:universal_io/io.dart';
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

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (iconColor ?? Theme.of(context).colorScheme.primary).withAlpha(30),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: iconColor ?? Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
        drawer: Padding(
          padding: EdgeInsets.fromLTRB(0, Constants.screenHeight(context) / 8, 0, Constants.screenHeight(context) / 12),
          child: Drawer(
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).colorScheme.primaryContainer,
                      ],
                    ),
                    borderRadius: const BorderRadius.only(topRight: Radius.circular(20)),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(50),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Image.asset("assets/images/logo.png", width: 40, height: 40),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "AvareX",
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                FutureBuilder(
                                  future: rootBundle.loadString("pubspec.yaml"),
                                  builder: (context, snapshot) {
                                    String version = "Unknown";
                                    if (snapshot.hasData) {
                                      var yaml = loadYaml(snapshot.data!);
                                      version = yaml["version"];
                                    }
                                    return Text(
                                      'v$version',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white.withAlpha(200),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(MdiIcons.exitToApp, color: Colors.white.withAlpha(200)),
                            tooltip: "Show intro screens",
                            onPressed: () {
                              Storage().settings.setIntro(true);
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(builder: (_) => const OnBoardingScreen()),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      _buildSectionHeader(context, "Data"),
                      _buildMenuItem(
                        context,
                        icon: Icons.download,
                        title: "Download",
                        subtitle: "Charts & databases",
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/download');
                        },
                      ),
                      _buildMenuItem(
                        context,
                        icon: MdiIcons.fileDocument,
                        title: "Documents",
                        subtitle: "PDFs, checklists & files",
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/documents');
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildSectionHeader(context, "Flight"),
                      _buildMenuItem(
                        context,
                        icon: MdiIcons.airplane,
                        title: "Aircraft",
                        subtitle: "Manage your aircraft",
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/aircraft');
                        },
                      ),
                      _buildMenuItem(
                        context,
                        icon: MdiIcons.checkboxMarkedOutline,
                        title: "Check Lists",
                        subtitle: "Pre-flight & procedures",
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/checklists');
                        },
                      ),
                      _buildMenuItem(
                        context,
                        icon: MdiIcons.scaleUnbalanced,
                        title: "Weight & Balance",
                        subtitle: "Calculate W&B",
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/wnb');
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildSectionHeader(context, "Records"),
                      _buildMenuItem(
                        context,
                        icon: MdiIcons.notebook,
                        title: "Log Book",
                        subtitle: "Flight records",
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/logbook');
                        },
                      ),
                      if (Constants.shouldShowBluetoothSpp) ...[
                        const SizedBox(height: 8),
                        _buildSectionHeader(context, "Connectivity"),
                        _buildMenuItem(
                          context,
                          icon: Icons.compare_arrows_rounded,
                          title: "IO",
                          subtitle: "Bluetooth & connections",
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushNamed(context, '/io');
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                      _buildSectionHeader(context, "Support"),
                      if (Constants.shouldShowDonation)
                        _buildMenuItem(
                          context,
                          icon: Icons.favorite_outline,
                          iconColor: Colors.red,
                          title: "Donate",
                          subtitle: "Support development",
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushNamed(context, '/donate');
                          },
                        ),
                      if (Constants.shouldShowPdf)
                        _buildMenuItem(
                          context,
                          icon: Icons.help_outline,
                          title: "Help",
                          subtitle: "User manual",
                          onTap: () async {
                            Navigator.pop(context);
                            final String pdfPath = '${Storage().dataDir}/USER_MANUAL.pdf';
                            final File pdfFile = File(pdfPath);
                            if (!await pdfFile.exists()) {
                              final ByteData data = await rootBundle.load('assets/docs/USER_MANUAL.pdf');
                              await pdfFile.writeAsBytes(data.buffer.asUint8List());
                            }
                            if (context.mounted) {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (context) => PdfViewer(pdfPath)),
                              );
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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

