
import 'package:avaremp/settings_cache_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_settings_screen_ex/flutter_settings_screen_ex.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'db_general.dart';
import 'download_screen.dart';
import 'gps.dart';
import 'main_screen.dart';
import 'appsettings_screen.dart';

void main()  {
  DbGeneral.set(); // set database platform
  WidgetsFlutterBinding.ensureInitialized();
  WakelockPlus.enable(); // keep screen on
  Gps.checkPermissions();

  initSettings().then((accentColor) {
    runApp(const MainApp());
  });
}

Future<void> initSettings() async {
  await Settings.init(
    cacheProvider: SettingsCacheProvider(),
  );
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => const MainScreen(),
        '/download': (context) => const DownloadScreen(),
        '/settings': (context) => const AppSettingsScreen(),
      },
      theme : ThemeData(
        brightness: Brightness.dark,
      ),
    );
  }
}


