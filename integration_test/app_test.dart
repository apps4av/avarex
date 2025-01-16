
import 'dart:io';

import 'package:avaremp/faa_dates.dart';
import 'package:avaremp/path_utils.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avaremp/main.dart';
import 'package:integration_test/integration_test.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('end-to-end test', () {
    testWidgets('Onboarding',
            (tester) async {

          Directory dir = await getApplicationDocumentsDirectory();
          String dataDir = PathUtils.getFilePath(dir.path, "avarex"); // put files in a folder
          try {
                await PathUtils.deleteFile("$dataDir/databasesx");
                await PathUtils.deleteFile("$dataDir/user.db");
          }
          catch (e) {
            print(e);
          }
          await Storage().init();
          await tester.pumpWidget(const MainApp());
          Future.delayed(const Duration(seconds: 1));

          // sign
          var fab = find.widgetWithText(TextButton, "Tap here to sign");
          await tester.dragUntilVisible(fab, find.byType(IntroductionScreen), const Offset(0, -250));
          await tester.tap(fab);
          await tester.pumpAndSettle();

          // Verify the signing was successful
          expect(find.text("You have signed this document. Please continue on to the next screen."), findsOneWidget);

          // go to download screen
          fab = find.widgetWithIcon(TextButton, Icons.arrow_forward);
          await tester.tap(fab);
          await tester.pumpAndSettle();

          fab = find.widgetWithIcon(TextButton, Icons.arrow_forward);
          await tester.tap(fab);
          await tester.pumpAndSettle();

          fab = find.widgetWithIcon(TextButton, Icons.arrow_forward);
          await tester.tap(fab);
          await tester.pumpAndSettle();

          fab = find.widgetWithIcon(TextButton, Icons.arrow_forward);
          await tester.tap(fab);
          await tester.pumpAndSettle();

          // go to download
          fab = find.widgetWithText(TextButton, "Download");
          await tester.tap(fab);
          await tester.pumpAndSettle();

          // download databases
          fab = find.widgetWithText(ExpansionTile, "Databases");
          await tester.tap(fab);
          await tester.pumpAndSettle();

          // download databases
          fab = find.widgetWithText(ListTile, "DatabasesX");
          await tester.tap(fab);
          await tester.pumpAndSettle();

          fab = find.widgetWithText(TextButton, "Start");
          await tester.tap(fab);
          await tester.pumpAndSettle();

          // give time to download
          await Future.delayed(const Duration(seconds: 10));
          await tester.pumpAndSettle();

          String cycle = FaaDates.getCurrentCycle();
          String range = FaaDates.getVersionRange(cycle);
          expect(find.widgetWithText(ListTile, "$cycle $range"), findsOneWidget);

          // go to register
          fab = find.byTooltip("Back");
          await tester.tap(fab);
          await tester.pumpAndSettle();

          fab = find.widgetWithIcon(TextButton, Icons.arrow_forward);
          await tester.tap(fab);
          await tester.pumpAndSettle();

          fab = find.widgetWithIcon(TextButton, Icons.arrow_forward);
          await tester.tap(fab);
          await tester.pumpAndSettle();

          fab = find.widgetWithIcon(TextButton, Icons.arrow_forward);
          await tester.tap(fab);
          await tester.pumpAndSettle();

          // register

          fab = find.ancestor(of: find.text("1800wxbrief.com Username / Email"), matching: find.byType(TextFormField));
          await tester.enterText(fab, "apps4av@gmail.com");
          await tester.pumpAndSettle();

          fab = find.widgetWithText(TextButton, "Register");
          await tester.tap(fab);
          await tester.pumpAndSettle();

          // give time to register
          await Future.delayed(const Duration(seconds: 10));
          await tester.pumpAndSettle();
          expect(find.widgetWithText(TextButton, "Unregister"), findsOneWidget);

          // press Done button
          fab = find.widgetWithIcon(TextButton, Icons.arrow_forward);
          await tester.tap(fab);
          await tester.pumpAndSettle();

          fab = find.widgetWithText(TextButton, "Done");
          await tester.tap(fab);
          await tester.pumpAndSettle();

          await Future.delayed(const Duration(seconds: 1));
          await tester.pumpAndSettle();

          expect(find.widgetWithText(TextButton, "Center"), findsOneWidget);

        });
  });
}