import 'package:flutter/material.dart';

/// Logo shown at launch. [background] matches the `flutter_native_splash`
/// color in pubspec.yaml.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  static const Color background = Color(0xFF141218);

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: background,
      body: Center(
        child: Image(
          image: AssetImage("assets/images/logo.png"),
          width: 200,
          height: 200,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
