import 'package:firebase_auth/firebase_auth.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:universal_io/io.dart';


class RevenueCatService {
  static Future<void> initPlatformState() async {
    await Purchases.setLogLevel(LogLevel.debug);
    String appleKey = "@@___revenuecat_apple_api_key__@@";
    String androidKey = "@@___revenuecat_android_api_key__@@";

    PurchasesConfiguration configuration;
    if (Platform.isAndroid) {
      configuration = PurchasesConfiguration(androidKey);
      await Purchases.configure(configuration);
    } else if (Platform.isIOS || Platform.isMacOS) {
      configuration = PurchasesConfiguration(appleKey);
      await Purchases.configure(configuration);
    }
  }

  static Future<void> logOut() async {
    await Purchases.logOut();
  }

  static Future<void> logIn() async {
    // log in with user ID from Firebase Auth
    await Purchases.logIn(FirebaseAuth.instance.currentUser!.uid);
  }

  static Future<bool> presentPaywallIfNeeded() async {
    final paywallResult = await RevenueCatUI.presentPaywallIfNeeded("Pro");
    // Handle result if needed.
    switch (paywallResult) {
      case PaywallResult.purchased:
        return true;

      default:
        return false;
    }
  }
}