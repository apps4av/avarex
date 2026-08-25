import 'package:avaremp/logbook/logbook_screen.dart';
import 'package:avaremp/longpress_screen.dart';
import 'package:avaremp/plan/plan_action_screen.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/writing_screen.dart';
import 'aircraft/aircraft_performance_screen.dart';
import 'package:flutter/material.dart';
import 'about_screen.dart';
import 'ai/ai_screen.dart';
import 'checklist/checklist_screen.dart';
import 'gdl90/opensky_settings_screen.dart';
import 'constants.dart';
import 'destination/destination.dart';
import 'documents_screen.dart';
import 'chart/download_screen.dart';
import 'io/io_screen.dart';
import 'main_screen.dart';
import 'onboarding_screen.dart';
import 'ofm/ofm_download_screen.dart';
import 'ofm/ofm_chart_library_screen.dart';
import 'openaip/openaip_download_screen.dart';
import 'weather/open_meteo_settings_screen.dart';
import 'weather/flybrief_download_screen.dart';
import 'weather/terrain_download_screen.dart';

class CustomWidgetsBinding extends WidgetsFlutterBinding {
  @override
  ImageCache createImageCache() => Storage().imageCache;
}

void main() {
  // this is to control cache. Nexrad needs it or image caching will make it impossible to animate weather
  CustomWidgetsBinding();
  Storage().init().then((accentColor) async {
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
              '/ofm_download': (context) => const OfmDownloadScreen(),
              '/ofm_charts': (context) => const OfmChartLibraryScreen(),
              '/openaip': (context) => const OpenAipDownloadScreen(),
              '/open_meteo': (context) => const OpenMeteoSettingsScreen(),
              '/flybrief': (context) => const FlybriefDownloadScreen(),
              '/terrain': (context) => const TerrainDownloadScreen(),
              '/documents': (context) => const DocumentsScreen(),
              '/checklists': (context) => const ChecklistScreen(),
              '/performance': (context) => const AircraftPerformanceScreen(),
              '/logbook': (context) => const LogbookScreen(),
              if(Constants.shouldShowBluetoothSpp) '/io': (context) => const IoScreen(),
              '/notes': (context) => const WritingScreen(),
              '/plan_actions': (context) => const PlanActionScreen(),
              '/ai': (context) => const AiScreen(),
              '/about': (context) => const AboutScreen(),
              '/opensky': (context) => const OpenSkySettingsScreen(),
              '/popup': (context) {
                  final args = ModalRoute.of(context)!.settings.arguments as List<Destination>;
                  return LongPressScreen(destinations: args);
                }
            },
            theme: value,
          )); // Safe Area so things from OS do not get in the way
        });
    }
  }
