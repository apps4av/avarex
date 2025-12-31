import 'dart:developer';
import 'package:flutter/foundation.dart';

class AppLog {
  static void logMessage(String message) {
    // In a real application, you might want to log to a file or external service
    if(kDebugMode) log(message);
  }
}