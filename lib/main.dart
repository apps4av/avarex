import 'package:avaremp/donate_screen.dart';
import 'package:avaremp/logbook_screen.dart';
import 'package:avaremp/longpress_screen.dart';
import 'package:avaremp/plan/plan_action_screen.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/wnb_screen.dart';
import 'package:avaremp/writing_screen.dart';
import 'package:flutter/material.dart';
import 'aircraft_screen.dart';
import 'package:avaremp/pro_screen.dart';
import 'package:avaremp/revenuecat_service.dart';
import 'package:avaremp/upgrade_screen.dart';
import 'checklist_screen.dart';
import 'constants.dart';
import 'destination/destination.dart';
import 'documents_screen.dart';
import 'download_screen.dart';
import 'io_screen.dart';
import 'main_screen.dart';
import 'onboarding_screen.dart';

class CustomWidgetsBinding extends WidgetsFlutterBinding {
  @override
  ImageCache createImageCache() => Storage().imageCache;
}

void main()  {
  // this is to control cache. Nexrad needs it or image caching will make it impossible to animate weather
  CustomWidgetsBinding();

  Storage().init().then((accentColor) async {
    await RevenueCatService().init();
    runApp(const MainApp());
  });

}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeData>(
        valueListenable: Storage().themeNotifier,
        builder: (context, value, child) {
          return SafeArea(child: MaterialApp(
            debugShowCheckedModeBanner: false,
            initialRoute: '/',
            routes: {
              '/': (context) =>
              Storage().settings.showIntro()
                  ? const OnBoardingScreen()
                  : const MainScreen(),
              '/download': (context) => const DownloadScreen(),
              '/documents': (context) => const DocumentsScreen(),
              '/aircraft': (context) => const AircraftScreen(),
              '/checklists': (context) => const ChecklistScreen(),
              '/wnb': (context) => const WnbScreen(),
              '/logbook': (context) => const LogbookScreen(),
              '/donate': (context) => const DonateScreen(),
              if(Constants.shouldShowBluetoothSpp) '/io': (context) => const IoScreen(),
              '/notes': (context) => const WritingScreen(),
              '/plan_actions': (context) => const PlanActionScreen(),
              '/popup': (context) {
                  final args = ModalRoute.of(context)!.settings.arguments as List<Destination>;
                  return LongPressScreen(destinations: args);
                }
              , '/pro': (context) => const ProScreen()
              , '/upgrade': (context) => const UpgradeScreen()
            },
            theme: value,
          )); // Safe Area so things from OS do not get in the way
        });
    }
  }
