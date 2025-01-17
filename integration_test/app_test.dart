
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
          }
          catch (e) {
          }
          try {
                await PathUtils.deleteFile("$dataDir/user.db");
          }
          catch (e) {
          }
          await Storage().init();
          await tester.pumpWidget(const MainApp());
          Future.delayed(const Duration(seconds: 1));

          late Finder fab;

          Future<void> signTest() async {
                // sign
                fab = find.widgetWithText(TextButton, "Tap here to sign");
                await tester.dragUntilVisible(
                    fab, find.byType(IntroductionScreen),
                    const Offset(0, -250));
                await tester.tap(fab);
                await tester.pumpAndSettle();

                // Verify the signing was successful
                expect(find.text(
                    "You have signed this document. Please continue on to the next screen."),
                    findsOneWidget);
          }

          await signTest();

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

          Future<void> downloadTest() async {
                // go to download
                fab = find.widgetWithText(TextButton, "Download");
                await tester.dragUntilVisible(
                    fab, find.byType(IntroductionScreen),
                    const Offset(0, -250));
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
                await Future.delayed(const Duration(seconds: 30));
                await tester.pumpAndSettle();

                String cycle = FaaDates.getCurrentCycle();
                String range = FaaDates.getVersionRange(cycle);
                expect(find.widgetWithText(ListTile, "$cycle $range"),
                    findsOneWidget);

                // go back
                fab = find.byTooltip("Back");
                await tester.tap(fab);
                await tester.pumpAndSettle();
          }

          await downloadTest();

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
          Future<void> registerTest() async {
                fab = find.ancestor(
                    of: find.text("1800wxbrief.com Username / Email"),
                    matching: find.byType(TextFormField));
                await tester.enterText(fab, "apps4av@gmail.com");
                await tester.pumpAndSettle();

                fab = find.widgetWithText(TextButton, "Register");
                await tester.tap(fab);
                await tester.pumpAndSettle();

                // give time to register
                await Future.delayed(const Duration(seconds: 10));
                await tester.pumpAndSettle();
                expect(find.widgetWithText(TextButton, "Unregister"),
                    findsOneWidget);
          }

          await registerTest();

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

          Future<void> planTest() async {
                fab = find.byTooltip("Create a flight plan");
                await tester.tap(fab);
                await tester.pumpAndSettle();

                fab = find.widgetWithText(TextButton, "Actions");
                await tester.tap(fab);
                await tester.pumpAndSettle();

                fab = find.widgetWithText(TextButton, "Create");
                await tester.tap(fab);
                await tester.pumpAndSettle();

                fab = find.ancestor(
                    of: find.text("Route"),
                    matching: find.byType(TextFormField));
                await tester.enterText(fab, "KBOS BOS CMK KHPN");
                await tester.pumpAndSettle();

                fab = find.widgetWithText(TextButton, "Create As Entered");
                await tester.tap(fab);
                await tester.pumpAndSettle();

                await Future.delayed(const Duration(seconds: 2));
                await tester.pumpAndSettle();

                // distances for this plan
                expect(find.widgetWithText(Expanded, "148"), findsWidgets);
                expect(find.widgetWithText(Expanded, "1"), findsWidgets);
                expect(find.widgetWithText(Expanded, "133"), findsWidgets);
                expect(find.widgetWithText(Expanded, "14"), findsWidgets);
          }

          await planTest();

          Future<void> searchTest() async {
                fab = find.byTooltip("Search for Airports, NavAids, etc.");
                await tester.tap(fab);
                await tester.pumpAndSettle();

                fab = find.ancestor(
                    of: find.text("Find"),
                    matching: find.byType(TextFormField));

                await tester.enterText(fab, "KSBA");
                await tester.pumpAndSettle();
                await Future.delayed(const Duration(seconds: 2));
                await tester.pumpAndSettle();

                // distances for this plan
                expect(find.widgetWithText(
                    Expanded, "SANTA BARBARA MUNI ( AIRPORT )"),
                    findsOneWidget);

                await tester.enterText(fab, "KBVY.R34");
                await tester.pumpAndSettle();
                await Future.delayed(const Duration(seconds: 2));
                await tester.pumpAndSettle();

                // distances for this plan
                expect(find.widgetWithText(Expanded, "KBVY.R34 ( Procedure )"), findsOneWidget);

          }

          await searchTest();

    });
  });
}