
import 'package:avaremp/storage.dart';
import 'package:avaremp/terms_screen.dart';
import 'package:flutter/material.dart';
import 'download_screen.dart';
import 'main_screen.dart';

void main()  {

  Storage().init().then((accentColor) {
    runApp(const MainApp());
  });

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
        '/terms': (context) => const TermsScreen(),
      },
      theme : ThemeData(
        brightness: Brightness.dark,
      ),
    );
  }
}


