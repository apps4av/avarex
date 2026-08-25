import 'package:flutter/foundation.dart';

class OpenAipChanges {
  OpenAipChanges._();

  static final ValueNotifier<int> notifier = ValueNotifier<int>(0);

  static void notifyChanged() => notifier.value++;
}
