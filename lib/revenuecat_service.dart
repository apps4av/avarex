import 'dart:io';

import 'package:avaremp/constants.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class RevenueCatService {
  RevenueCatService._internal();
  static final RevenueCatService _instance = RevenueCatService._internal();
  factory RevenueCatService() => _instance;

  final ValueNotifier<bool> isPro = ValueNotifier<bool>(false);
  bool _isConfigured = false;

  bool get isSupportedPlatform {
    if (kIsWeb) {
      return false;
    }
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows) {
      return true;
    }
    return false; // treat Linux as unsupported
  }

  Future<void> init() async {
    if (!isSupportedPlatform) {
      // Treat unsupported platforms as Pro-enabled so features remain accessible
      isPro.value = true;
      return;
    }

    if (_isConfigured) {
      return;
    }

    String? apiKey;
    if (Platform.isAndroid) {
      apiKey = Constants.revenueCatPublicSdkKeyAndroid;
    } else if (Platform.isIOS) {
      apiKey = Constants.revenueCatPublicSdkKeyIOS;
    } else if (Platform.isMacOS) {
      apiKey = Constants.revenueCatPublicSdkKeyMacOS.isNotEmpty
          ? Constants.revenueCatPublicSdkKeyMacOS
          : Constants.revenueCatPublicSdkKeyIOS;
    } else if (Platform.isWindows) {
      apiKey = Constants.revenueCatPublicSdkKeyWindows.isNotEmpty
          ? Constants.revenueCatPublicSdkKeyWindows
          : Constants.revenueCatPublicSdkKeyAndroid;
    }

    if (apiKey == null || apiKey.isEmpty) {
      // If no key provided, consider Pro disabled but don't crash
      isPro.value = false;
      return;
    }

    final configuration = PurchasesConfiguration(apiKey);
    await Purchases.configure(configuration);
    _isConfigured = true;
    await refreshCustomerInfo();
  }

  Future<void> refreshCustomerInfo() async {
    if (!isSupportedPlatform || !_isConfigured) {
      return;
    }
    try {
      final CustomerInfo info = await Purchases.getCustomerInfo();
      final bool hasPro = info.entitlements.active.containsKey(Constants.revenueCatEntitlementPro);
      isPro.value = hasPro;
    } catch (_) {
      isPro.value = false;
    }
  }

  Future<bool> isProUser() async {
    if (!isSupportedPlatform) {
      return true;
    }
    await refreshCustomerInfo();
    return isPro.value;
  }
}

