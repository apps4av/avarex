import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:universal_io/io.dart';


class RevenueCatService {
  static String iosKey = "@@___revenuecat_ios_api_key__@@";
  static String androidKey = "@@___revenuecat_android_api_key__@@";
  static String entitlementId = "Pro";
  static Future<void> initPlatformState() async {
    await Purchases.setLogLevel(LogLevel.debug);

    PurchasesConfiguration configuration;
    if (Platform.isAndroid) {
      configuration = PurchasesConfiguration(androidKey);
      await Purchases.configure(configuration);
    } else if (Platform.isIOS) {
      configuration = PurchasesConfiguration(iosKey);
      await Purchases.configure(configuration);
    }
  }

  static Future<CustomerInfo> getCustomerInfo() async {
    final CustomerInfo info = await Purchases.getCustomerInfo();
    return info;
  }

  static Future<void> logOut() async {
    await Purchases.logOut();
  }

  static Future<bool> logIn(String userId) async {
    bool loggedIn = false;
    try {
      await Purchases.logIn(userId);
      loggedIn = true;
    }
    catch(e) {// ignore
      loggedIn = false;
    }
    return loggedIn;
  }

  static Future<bool> presentPaywallIfNeeded() async {
    bool entitled = false;
    try {
      final Offerings offerings = await Purchases.getOfferings();
      final paywallResult = await RevenueCatUI.presentPaywallIfNeeded(
          entitlementId, offering: offerings.current);
      // Handle result if needed.
      switch (paywallResult) {
        case PaywallResult.restored:
        case PaywallResult.notPresented:
        case PaywallResult.purchased:
        case PaywallResult.cancelled:
        case PaywallResult.error:
          break;
      }
      await RevenueCatService.getCustomerInfo().then((customerInfo) {
        if (customerInfo.entitlements.all[entitlementId] != null &&
            customerInfo.entitlements.all[entitlementId]!.isActive) {
          entitled = true;
        }
      });
    }
    catch(e) {
      return false;
    }

    return entitled;
  }
}