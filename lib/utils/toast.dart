import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

import '../ai/ai_screen.dart';
import '../constants.dart';

class Toast {
  static void showToast(BuildContext context, String text, Widget? icon, int duration, {bool translate = false}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    Toastification().dismissAll();
    Toastification().show(
      alignment: Alignment.bottomRight,
      context: context,
      closeOnClick: true,
      closeButton: ToastCloseButton(showType: CloseButtonShowType.none),
      description: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(text, style: TextStyle(fontWeight: FontWeight.w500),),
        if(Constants.shouldShowProServices && translate)
          TextButton(onPressed:() {
            Toastification().dismissAll();
            // put in database for AI query history to pick up, go to pro screen
            AiScreenState.teleportToAiScreen(context, "translate: $text");
          } , child: Text("Translate")),
      ]),
      autoCloseDuration: Duration(seconds: duration),
      icon: CircleAvatar(radius: 16, backgroundColor: Colors.white, child: icon),
      showIcon: icon == null ? false : true,
      backgroundColor: colorScheme.surfaceDim, // Using a theme color
      foregroundColor: colorScheme.onSurface, // Using a theme c
    );
  }


}

