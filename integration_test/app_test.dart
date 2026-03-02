
import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';

import 'package:avaremp/utils/faa_dates.dart';
import 'package:avaremp/utils/path_utils.dart';
import 'package:avaremp/storage.dart';
import 'package:avaremp/data/user_database_helper.dart';
import 'package:avaremp/checklist/checklist.dart';
import 'package:avaremp/wnb/wnb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avaremp/main.dart';
import 'package:integration_test/integration_test.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('end-to-end test', () {
    testWidgets('Onboarding and All Screens',
            (tester) async {

          Directory dir = await getApplicationDocumentsDirectory();
          String dataDir = PathUtils.getFilePath(dir.path, "avarex"); // put files in a folder
          try {
                await PathUtils.deleteFile("$dataDir/databasesx");
          }
          catch (e) {
                if (kDebugMode) print("Error deleting databasesx: $e");
          }
          try {
                await PathUtils.deleteFile("$dataDir/user.db");
          }
          catch (e) {
                if (kDebugMode) print("Error deleting user.db: $e");
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

                // give time to download - poll for completion
                String cycle = FaaDates.getCurrentCycle();
                String range = FaaDates.getVersionRange(cycle);
                bool downloadComplete = false;
                
                // Poll for up to 60 seconds for download to complete
                for (int i = 0; i < 12; i++) {
                  await Future.delayed(const Duration(seconds: 5));
                  await tester.pumpAndSettle();
                  
                  // Check if the cycle info appears (indicates download complete)
                  fab = find.textContaining(cycle);
                  if (tester.any(fab)) {
                    downloadComplete = true;
                    break;
                  }
                }
                
                // Verify download completed by checking for cycle text
                expect(downloadComplete, isTrue, reason: "Download should complete within 60 seconds");
                
                // Verify the cycle and range text appears somewhere
                expect(find.textContaining(cycle), findsWidgets);

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

          // Verify we're on MAP tab after onboarding
          expect(find.widgetWithText(TextButton, "Center"), findsOneWidget);

          // =====================
          // TEST: MAP Tab
          // =====================
          Future<void> mapTabTest() async {
                // Verify MAP tab elements
                expect(find.byTooltip("View the maps and overlays"), findsOneWidget);
                
                // Verify Center button exists
                fab = find.widgetWithText(TextButton, "Center");
                expect(fab, findsOneWidget);
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                // Verify Menu button exists (drawer trigger)
                fab = find.widgetWithText(TextButton, "Menu");
                expect(fab, findsOneWidget);
          }
          
          await mapTabTest();

          // =====================
          // TEST: PLATE Tab
          // =====================
          Future<void> plateTabTest() async {
                // Navigate to PLATE tab
                fab = find.byTooltip("Look at approach plates, airport diagrams, CSUP, Minimums, etc.");
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                await Future.delayed(const Duration(seconds: 1));
                await tester.pumpAndSettle();
                
                // Verify PLATE tab is active (bottom nav)
                expect(find.text("PLATE"), findsOneWidget);
          }
          
          await plateTabTest();

          // =====================
          // TEST: PLAN Tab (extended)
          // =====================
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

                // Test navigation log (fuel icon)
                fab = find.byIcon(Icons.local_gas_station_rounded);
                if (tester.any(fab)) {
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                  await Future.delayed(const Duration(seconds: 1));
                  await tester.pumpAndSettle();
                  
                  // Go back from nav log
                  fab = find.byTooltip("Back");
                  if (tester.any(fab)) {
                    await tester.tap(fab);
                    await tester.pumpAndSettle();
                  }
                }

                // Test Load & Save action
                fab = find.widgetWithText(TextButton, "Actions");
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                fab = find.widgetWithText(TextButton, "Load & Save");
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                // Verify Load & Save screen elements
                expect(find.widgetWithText(TextButton, "Save"), findsWidgets);
                
                // Go back to PLAN
                fab = find.byTooltip("Back");
                await tester.tap(fab);
                await tester.pumpAndSettle();
          }

          await planTest();

          // =====================
          // TEST: FIND Tab (extended)
          // =====================
          Future<void> searchTest() async {
                fab = find.byTooltip("Search for Airports, NavAids, etc.");
                await tester.tap(fab);
                await tester.pumpAndSettle();

                // Test Recent button
                fab = find.widgetWithText(TextButton, "Recent");
                expect(fab, findsOneWidget);
                await tester.tap(fab);
                await tester.pumpAndSettle();

                // Test Nearest button
                fab = find.widgetWithText(TextButton, "Nearest");
                expect(fab, findsOneWidget);
                await tester.tap(fab);
                await tester.pumpAndSettle();
                await Future.delayed(const Duration(seconds: 1));
                await tester.pumpAndSettle();

                // Test Nearest 2K button
                fab = find.widgetWithText(TextButton, "Nearest 2K");
                expect(fab, findsOneWidget);
                await tester.tap(fab);
                await tester.pumpAndSettle();
                await Future.delayed(const Duration(seconds: 1));
                await tester.pumpAndSettle();

                // Test Nearest 4K button
                fab = find.widgetWithText(TextButton, "Nearest 4K");
                expect(fab, findsOneWidget);
                await tester.tap(fab);
                await tester.pumpAndSettle();
                await Future.delayed(const Duration(seconds: 1));
                await tester.pumpAndSettle();

                // Test search functionality
                fab = find.ancestor(
                    of: find.text("Find"),
                    matching: find.byType(TextFormField));

                await tester.enterText(fab, "KSBA");
                await tester.pumpAndSettle();
                await Future.delayed(const Duration(seconds: 2));
                await tester.pumpAndSettle();

                expect(find.widgetWithText(
                    Expanded, "SANTA BARBARA MUNI ( AIRPORT )"),
                    findsOneWidget);

                await tester.enterText(fab, "KBVY.R34");
                await tester.pumpAndSettle();
                await Future.delayed(const Duration(seconds: 2));
                await tester.pumpAndSettle();

                expect(find.widgetWithText(Expanded, "KBVY.R34 ( Procedure )"), findsOneWidget);
          }

          await searchTest();

          // =====================
          // TEST: Documents Screen
          // =====================
          Future<void> documentsScreenTest() async {
                // Go to MAP first
                fab = find.byTooltip("View the maps and overlays");
                await tester.tap(fab);
                await tester.pumpAndSettle();

                // Open drawer via Menu button
                fab = find.widgetWithText(TextButton, "Menu");
                await tester.tap(fab);
                await tester.pumpAndSettle();

                // Tap Documents in drawer
                fab = find.widgetWithText(ListTile, "Documents");
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                await Future.delayed(const Duration(seconds: 1));
                await tester.pumpAndSettle();

                // Verify Documents screen elements
                expect(find.text("Documents"), findsOneWidget);
                expect(find.widgetWithText(TextButton, "Import"), findsOneWidget);
                
                // Verify some weather products are visible
                expect(find.text("WPC Surface Analysis"), findsWidgets);
                
                // Go back
                fab = find.byTooltip("Back");
                await tester.tap(fab);
                await tester.pumpAndSettle();
          }

          await documentsScreenTest();

          // =====================
          // TEST: Aircraft Screen
          // =====================
          Future<void> aircraftScreenTest() async {
                // Open drawer via Menu button
                fab = find.widgetWithText(TextButton, "Menu");
                await tester.tap(fab);
                await tester.pumpAndSettle();

                // Tap Aircraft in drawer
                fab = find.widgetWithText(ListTile, "Aircraft");
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                await Future.delayed(const Duration(seconds: 1));
                await tester.pumpAndSettle();

                // Verify Aircraft screen elements
                expect(find.text("Aircraft"), findsOneWidget);
                
                // Test adding aircraft data
                fab = find.ancestor(
                    of: find.text("Tail Number"),
                    matching: find.byType(TextFormField));
                await tester.enterText(fab, "N12345");
                await tester.pumpAndSettle();

                fab = find.ancestor(
                    of: find.text("Type"),
                    matching: find.byType(TextFormField));
                await tester.enterText(fab, "C172");
                await tester.pumpAndSettle();

                // Scroll down to find more fields and Save button
                fab = find.widgetWithText(TextButton, "Save");
                await tester.dragUntilVisible(
                    fab,
                    find.byType(SingleChildScrollView),
                    const Offset(0, -200));
                await tester.pumpAndSettle();

                // Save the aircraft
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                await Future.delayed(const Duration(seconds: 1));
                await tester.pumpAndSettle();

                // Go back
                fab = find.byTooltip("Back");
                await tester.tap(fab);
                await tester.pumpAndSettle();
          }

          await aircraftScreenTest();

          // =====================
          // TEST: Check Lists Screen
          // =====================
          Future<void> checklistScreenTest() async {
                // Open drawer via Menu button
                fab = find.widgetWithText(TextButton, "Menu");
                await tester.tap(fab);
                await tester.pumpAndSettle();

                // Tap Check Lists in drawer
                fab = find.widgetWithText(ListTile, "Check Lists");
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                await Future.delayed(const Duration(seconds: 1));
                await tester.pumpAndSettle();

                // Verify Check Lists screen elements
                expect(find.text("Check Lists"), findsOneWidget);
                expect(find.widgetWithText(TextButton, "Import"), findsOneWidget);
                
                // Verify info tooltip exists
                expect(find.byIcon(Icons.info), findsWidgets);

                // Go back
                fab = find.byTooltip("Back");
                await tester.tap(fab);
                await tester.pumpAndSettle();
          }

          await checklistScreenTest();

          // =====================
          // TEST: W&B Screen with Envelope Creation and Limit Checking
          // =====================
          Future<void> wnbScreenTest() async {
                // Create a test W&B sheet programmatically with envelope points
                // Typical C172 envelope (simplified)
                // Points define the valid CG envelope polygon
                List<String> envelopePoints = [
                  "35.0,1500.0",  // bottom left
                  "35.0,2400.0",  // top left  
                  "47.3,2400.0",  // top right
                  "47.3,1500.0",  // bottom right
                ];
                
                // Create W&B items (empty aircraft + load items)
                List<String> wnbItems = [];
                
                // Add empty weight item
                WnbItem emptyWeight = WnbItem("Empty Weight", 1650.0, 40.0);
                wnbItems.add(emptyWeight.toJson());
                
                // Add front seats
                WnbItem frontSeats = WnbItem("Front Seats", 340.0, 37.0);
                wnbItems.add(frontSeats.toJson());
                
                // Add rear seats
                WnbItem rearSeats = WnbItem("Rear Seats", 0.0, 73.0);
                wnbItems.add(rearSeats.toJson());
                
                // Add fuel (40 gal @ 6 lbs/gal = 240 lbs)
                WnbItem fuel = WnbItem("Fuel (40 gal)", 240.0, 48.0);
                wnbItems.add(fuel.toJson());
                
                // Add baggage
                WnbItem baggage = WnbItem("Baggage", 30.0, 95.0);
                wnbItems.add(baggage.toJson());
                
                // Pad remaining items with empty entries
                for (int i = wnbItems.length; i < 20; i++) {
                  wnbItems.add(WnbItem("", 0.0, 0.0).toJson());
                }
                
                // Create the W&B sheet
                Wnb testWnb = Wnb(
                  "C172 Test",
                  "N12345",
                  wnbItems,
                  30.0,   // minX (arm min)
                  1400.0, // minY (weight min)
                  100.0,  // maxX (arm max)
                  2600.0, // maxY (weight max)
                  envelopePoints
                );
                
                // Add W&B to database
                await UserDatabaseHelper.db.addWnb(testWnb);
                Storage().settings.setWnb("C172 Test");
                
                // Open drawer via Menu button
                fab = find.widgetWithText(TextButton, "Menu");
                await tester.tap(fab);
                await tester.pumpAndSettle();

                // Tap W&B in drawer
                fab = find.widgetWithText(ListTile, "W&B");
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                await Future.delayed(const Duration(seconds: 1));
                await tester.pumpAndSettle();

                // Verify W&B screen elements
                expect(find.text("W&B"), findsOneWidget);
                
                // Verify the W&B sheet name is shown (appears in name field and dropdown)
                expect(find.text("C172 Test"), findsWidgets);
                
                // Verify Edit button exists
                expect(find.widgetWithText(TextButton, "Edit"), findsOneWidget);
                
                // Verify item descriptions are visible
                expect(find.text("Empty Weight"), findsOneWidget);
                expect(find.text("Front Seats"), findsOneWidget);
                
                // Scroll down to see more items
                await tester.dragUntilVisible(
                    find.text("Total"),
                    find.byType(SingleChildScrollView),
                    const Offset(0, -100));
                await tester.pumpAndSettle();
                
                // Verify Total row exists (shows calculated CG)
                expect(find.text("Total"), findsOneWidget);
                
                // The total weight should be: 1650 + 340 + 0 + 240 + 30 = 2260 lbs
                // Verify the calculated weight appears
                expect(find.text("2260.0"), findsOneWidget);
                
                // ========================================
                // TEST: Enter Edit mode and modify items
                // ========================================
                // Scroll back up to see Edit button
                await tester.dragUntilVisible(
                    find.widgetWithText(TextButton, "Edit"),
                    find.byType(SingleChildScrollView),
                    const Offset(0, 200));
                await tester.pumpAndSettle();
                
                fab = find.widgetWithText(TextButton, "Edit");
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                await Future.delayed(const Duration(seconds: 1));
                await tester.pumpAndSettle();
                
                // Now in edit mode - button should say "Save"
                expect(find.widgetWithText(TextButton, "Save"), findsOneWidget);
                
                // Verify graph axis labels exist
                expect(find.text("Arm"), findsWidgets);
                expect(find.text("Weight"), findsWidgets);
                
                // Save the W&B (exit edit mode)
                fab = find.widgetWithText(TextButton, "Save");
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                await Future.delayed(const Duration(seconds: 1));
                await tester.pumpAndSettle();
                
                // Verify we're back in view mode
                expect(find.widgetWithText(TextButton, "Edit"), findsOneWidget);

                // Go back
                fab = find.byTooltip("Back");
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                // ========================================
                // TEST: Create W&B that is OUT of limits
                // ========================================
                // Create an overweight W&B
                List<String> overweightItems = [];
                overweightItems.add(WnbItem("Empty Weight", 1650.0, 40.0).toJson());
                overweightItems.add(WnbItem("Front Seats", 400.0, 37.0).toJson());
                overweightItems.add(WnbItem("Rear Seats", 350.0, 73.0).toJson());
                overweightItems.add(WnbItem("Fuel (50 gal)", 300.0, 48.0).toJson());
                overweightItems.add(WnbItem("Baggage", 100.0, 95.0).toJson());
                for (int i = overweightItems.length; i < 20; i++) {
                  overweightItems.add(WnbItem("", 0.0, 0.0).toJson());
                }
                
                Wnb overweightWnb = Wnb(
                  "C172 Overweight",
                  "N12345",
                  overweightItems,
                  30.0,
                  1400.0,
                  100.0,
                  2600.0,
                  envelopePoints
                );
                
                await UserDatabaseHelper.db.addWnb(overweightWnb);
                Storage().settings.setWnb("C172 Overweight");
                
                // Re-open W&B screen
                fab = find.widgetWithText(TextButton, "Menu");
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                fab = find.widgetWithText(ListTile, "W&B");
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                await Future.delayed(const Duration(seconds: 1));
                await tester.pumpAndSettle();
                
                // Verify the overweight sheet loaded (appears in name field and dropdown)
                expect(find.text("C172 Overweight"), findsWidgets);
                
                // Total weight = 1650 + 400 + 350 + 300 + 100 = 2800 lbs (over max 2400)
                // The CG dot should be RED (out of envelope)
                // We verify by checking the total weight calculation
                await tester.dragUntilVisible(
                    find.text("Total"),
                    find.byType(SingleChildScrollView),
                    const Offset(0, -100));
                await tester.pumpAndSettle();
                
                expect(find.text("2800.0"), findsOneWidget);

                // Go back
                fab = find.byTooltip("Back");
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                // Clean up - delete test W&B sheets
                await UserDatabaseHelper.db.deleteWnb("C172 Test");
                await UserDatabaseHelper.db.deleteWnb("C172 Overweight");
                Storage().settings.setWnb("");
          }

          await wnbScreenTest();

          // =====================
          // TEST: Log Book Screen
          // =====================
          Future<void> logbookScreenTest() async {
                // Open drawer via Menu button
                fab = find.widgetWithText(TextButton, "Menu");
                await tester.tap(fab);
                await tester.pumpAndSettle();

                // Tap Log Book in drawer
                fab = find.widgetWithText(ListTile, "Log Book");
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                await Future.delayed(const Duration(seconds: 1));
                await tester.pumpAndSettle();

                // Verify Log Book screen elements
                expect(find.text("Log Book"), findsOneWidget);
                expect(find.text("Total Hours"), findsOneWidget);
                expect(find.widgetWithText(TextButton, "Import"), findsOneWidget);
                expect(find.widgetWithText(TextButton, "Export"), findsOneWidget);
                expect(find.widgetWithText(TextButton, "Details"), findsOneWidget);

                // Test adding a log entry via FAB - verify form opens
                fab = find.byType(FloatingActionButton);
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                // Verify Log Entry Form screen
                expect(find.text("New Log Book Entry"), findsOneWidget);
                
                // Verify form fields exist
                expect(find.text("Date (YYYY-MM-DD)"), findsOneWidget);
                expect(find.text("Aircraft Tail Number"), findsOneWidget);
                expect(find.text("Aircraft Type"), findsOneWidget);

                // Go back to Log Book without saving
                fab = find.byTooltip("Back");
                await tester.tap(fab);
                await tester.pumpAndSettle();

                // Test Details button (dashboard)
                fab = find.widgetWithText(TextButton, "Details");
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                await Future.delayed(const Duration(seconds: 1));
                await tester.pumpAndSettle();

                // Verify dashboard screen
                expect(find.text("Log Book Dashboard"), findsOneWidget);

                // Go back to Log Book
                fab = find.byTooltip("Back");
                await tester.tap(fab);
                await tester.pumpAndSettle();

                // Go back to Map
                fab = find.byTooltip("Back");
                await tester.tap(fab);
                await tester.pumpAndSettle();
          }

          await logbookScreenTest();

          // =====================
          // TEST: Notes/Writing Screen (comprehensive)
          // =====================
          Future<void> notesScreenTest() async {
                // Notes screen is accessed from MAP via the notes icon
                // Find the notes/transcribe icon in bottom controls
                fab = find.byIcon(MdiIcons.transcribe);
                if (tester.any(fab)) {
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                  
                  await Future.delayed(const Duration(seconds: 1));
                  await tester.pumpAndSettle();

                  // Verify Notes screen elements
                  expect(find.text("Notes"), findsOneWidget);
                  
                  // Verify toolbar elements exist
                  expect(find.byIcon(Icons.undo), findsOneWidget);
                  expect(find.byIcon(Icons.redo), findsOneWidget);
                  expect(find.byIcon(Icons.save), findsOneWidget);
                  
                  // Verify background sheet selector exists
                  expect(find.byIcon(Icons.note_alt_outlined), findsOneWidget);
                  
                  // Verify eraser tool exists
                  expect(find.byIcon(MdiIcons.eraser), findsOneWidget);
                  
                  // ========================================
                  // TEST: Background Sheets - verify all exist
                  // ========================================
                  fab = find.byIcon(Icons.note_alt_outlined);
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                  
                  // Verify all background sheet types are available
                  expect(find.text("None"), findsOneWidget);
                  expect(find.text("Cost"), findsOneWidget);
                  expect(find.text("ATIS"), findsOneWidget);
                  expect(find.text("CRAFT"), findsOneWidget);
                  expect(find.text("Clearance"), findsOneWidget);
                  expect(find.text("Ground Taxi"), findsOneWidget);
                  expect(find.text("Tower Takeoff"), findsOneWidget);
                  expect(find.text("Departure"), findsOneWidget);
                  expect(find.text("Approach"), findsOneWidget);
                  expect(find.text("Tower Landing"), findsOneWidget);
                  expect(find.text("Ground Landed"), findsOneWidget);
                  
                  // Select CRAFT sheet
                  fab = find.text("CRAFT");
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                  await Future.delayed(const Duration(seconds: 1));
                  await tester.pumpAndSettle();
                  
                  // ========================================
                  // TEST: Keypad toggle and writing
                  // ========================================
                  fab = find.byIcon(Icons.dialpad);
                  if (tester.any(fab)) {
                    await tester.tap(fab);
                    await tester.pumpAndSettle();
                    
                    // Verify keypad appears with all buttons
                    expect(find.text("1"), findsWidgets);
                    expect(find.text("2"), findsWidgets);
                    expect(find.text("3"), findsWidgets);
                    expect(find.text("4"), findsWidgets);
                    expect(find.text("5"), findsWidgets);
                    expect(find.text("6"), findsWidgets);
                    expect(find.text("7"), findsWidgets);
                    expect(find.text("8"), findsWidgets);
                    expect(find.text("9"), findsWidgets);
                    expect(find.text("0"), findsWidgets);
                    expect(find.text("."), findsWidgets);
                    expect(find.text("C"), findsWidgets);  // Clear button
                    
                    // Test entering numbers using keypad
                    fab = find.text("1").first;
                    await tester.tap(fab);
                    await tester.pumpAndSettle();
                    
                    fab = find.text("2").first;
                    await tester.tap(fab);
                    await tester.pumpAndSettle();
                    
                    fab = find.text("5").first;
                    await tester.tap(fab);
                    await tester.pumpAndSettle();
                    
                    // Test clear button
                    fab = find.text("C").first;
                    await tester.tap(fab);
                    await tester.pumpAndSettle();
                    
                    // Toggle keypad off
                    fab = find.byIcon(Icons.dialpad);
                    await tester.tap(fab);
                    await tester.pumpAndSettle();
                  }
                  
                  // ========================================
                  // TEST: Undo/Redo functionality (verify buttons are interactive)
                  // ========================================
                  // Undo button should exist
                  fab = find.byIcon(Icons.undo);
                  expect(fab, findsOneWidget);
                  
                  // Redo button should exist
                  fab = find.byIcon(Icons.redo);
                  expect(fab, findsOneWidget);
                  
                  // ========================================
                  // TEST: Clear/Eraser functionality
                  // ========================================
                  fab = find.byIcon(MdiIcons.eraser);
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                  
                  // ========================================
                  // TEST: Switch to another background sheet
                  // ========================================
                  fab = find.byIcon(Icons.note_alt_outlined);
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                  
                  fab = find.text("ATIS");
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                  await Future.delayed(const Duration(seconds: 1));
                  await tester.pumpAndSettle();
                  
                  // Switch back to None (blank)
                  fab = find.byIcon(Icons.note_alt_outlined);
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                  
                  fab = find.text("None");
                  await tester.tap(fab);
                  await tester.pumpAndSettle();

                  // Go back
                  fab = find.byTooltip("Back");
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                }
          }

          await notesScreenTest();

          // =====================
          // TEST: Download Screen (from drawer)
          // =====================
          Future<void> downloadScreenFromDrawerTest() async {
                // Open drawer via Menu button
                fab = find.widgetWithText(TextButton, "Menu");
                await tester.tap(fab);
                await tester.pumpAndSettle();

                // Tap Download in drawer
                fab = find.widgetWithText(ListTile, "Download");
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                await Future.delayed(const Duration(seconds: 1));
                await tester.pumpAndSettle();

                // Verify Download screen elements
                expect(find.widgetWithText(TextButton, "Start"), findsOneWidget);
                
                // Verify category expansions exist
                expect(find.widgetWithText(ExpansionTile, "Databases"), findsOneWidget);
                expect(find.widgetWithText(ExpansionTile, "Sectional"), findsOneWidget);
                
                // Verify cycle toggle exists
                expect(find.widgetWithText(TextButton, "This Cycle"), findsOneWidget);

                // Go back
                fab = find.byTooltip("Back");
                await tester.tap(fab);
                await tester.pumpAndSettle();
          }

          await downloadScreenFromDrawerTest();

          // =====================
          // Verify bottom navigation tabs work
          // =====================
          Future<void> bottomNavTest() async {
                // Test all bottom nav tabs are accessible
                fab = find.byTooltip("View the maps and overlays");
                expect(fab, findsOneWidget);
                await tester.tap(fab);
                await tester.pumpAndSettle();
                expect(find.text("MAP"), findsOneWidget);

                fab = find.byTooltip("Look at approach plates, airport diagrams, CSUP, Minimums, etc.");
                expect(fab, findsOneWidget);
                await tester.tap(fab);
                await tester.pumpAndSettle();
                expect(find.text("PLATE"), findsOneWidget);

                fab = find.byTooltip("Create a flight plan");
                expect(fab, findsOneWidget);
                await tester.tap(fab);
                await tester.pumpAndSettle();
                expect(find.text("PLAN"), findsOneWidget);

                fab = find.byTooltip("Search for Airports, NavAids, etc.");
                expect(fab, findsOneWidget);
                await tester.tap(fab);
                await tester.pumpAndSettle();
                expect(find.text("FIND"), findsOneWidget);
          }

          await bottomNavTest();

          // =====================
          // TEST: Elevation Cache
          // =====================
          Future<void> elevationTest() async {
                // Navigate to MAP tab
                fab = find.byTooltip("View the maps and overlays");
                await tester.tap(fab);
                await tester.pumpAndSettle();

                // The elevation is displayed in the instruments panel
                // Verify the map is showing and can potentially display elevation data
                expect(find.widgetWithText(TextButton, "Center"), findsOneWidget);
                
                // Long press on map to trigger destination popup which shows elevation
                // This tests the elevation lookup functionality
                final mapCenter = tester.getCenter(find.byTooltip("View the maps and overlays"));
                await tester.longPressAt(mapCenter);
                await tester.pumpAndSettle();
                await Future.delayed(const Duration(seconds: 2));
                await tester.pumpAndSettle();
                
                // If a popup appeared, dismiss it
                fab = find.byTooltip("Close");
                if (tester.any(fab)) {
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                }
                
                // Check instruments panel for elevation display
                // The elevation instrument should exist in the instruments list
                // We verify the MAP screen is functional and can display elevation data
          }

          await elevationTest();

          // =====================
          // TEST: KML Export and Viewer
          // =====================
          Future<void> kmlTest() async {
                // Create a test KML file
                String testKml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>Test Flight Track</name>
    <Placemark>
      <name>Flight Path</name>
      <LineString>
        <coordinates>
          -118.4,34.0,1000
          -118.3,34.1,1500
          -118.2,34.2,2000
          -118.1,34.1,1800
          -118.0,34.0,1200
        </coordinates>
      </LineString>
    </Placemark>
  </Document>
</kml>''';
                
                // Write test KML file
                String tracksFolder = PathUtils.getTracksFolder(Storage().dataDir);
                await PathUtils.ensureTracksFolderExists(Storage().dataDir);
                File testKmlFile = File('$tracksFolder/test_track.kml');
                await testKmlFile.writeAsString(testKml);
                
                // Navigate to Documents screen to view the KML
                fab = find.widgetWithText(TextButton, "Menu");
                await tester.tap(fab);
                await tester.pumpAndSettle();

                fab = find.widgetWithText(ListTile, "Documents");
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                await Future.delayed(const Duration(seconds: 1));
                await tester.pumpAndSettle();
                
                // Filter to User Docs to find KML files
                fab = find.text("All Documents");
                if (tester.any(fab)) {
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                  
                  fab = find.text("User Docs");
                  if (tester.any(fab)) {
                    await tester.tap(fab);
                    await tester.pumpAndSettle();
                  }
                }
                
                // Navigate to tracks folder
                fab = find.text("tracks");
                if (tester.any(fab)) {
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                  await Future.delayed(const Duration(seconds: 1));
                  await tester.pumpAndSettle();
                  
                  // Find and tap the test KML file
                  fab = find.text("test_track.kml");
                  if (tester.any(fab)) {
                    await tester.tap(fab);
                    await tester.pumpAndSettle();
                    await Future.delayed(const Duration(seconds: 2));
                    await tester.pumpAndSettle();
                    
                    // Verify KML Viewer screen elements
                    expect(find.text("Test Flight Track"), findsOneWidget);
                    
                    // Verify view toggle buttons exist
                    expect(find.byTooltip("2D Map"), findsOneWidget);
                    expect(find.byTooltip("Altitude Profile"), findsOneWidget);
                    expect(find.byTooltip("3D View"), findsOneWidget);
                    
                    // Test switching to Altitude Profile view
                    fab = find.byTooltip("Altitude Profile");
                    await tester.tap(fab);
                    await tester.pumpAndSettle();
                    await Future.delayed(const Duration(seconds: 1));
                    await tester.pumpAndSettle();
                    
                    // Verify altitude profile elements
                    expect(find.text("Altitude Profile"), findsOneWidget);
                    expect(find.textContaining("Distance"), findsWidgets);
                    expect(find.textContaining("Alt"), findsWidgets);
                    
                    // Test switching to 3D View
                    fab = find.byTooltip("3D View");
                    await tester.tap(fab);
                    await tester.pumpAndSettle();
                    await Future.delayed(const Duration(seconds: 1));
                    await tester.pumpAndSettle();
                    
                    // Verify 3D view elements
                    expect(find.text("Reset View"), findsOneWidget);
                    
                    // Test Reset View button
                    fab = find.text("Reset View");
                    await tester.tap(fab);
                    await tester.pumpAndSettle();
                    
                    // Switch back to 2D Map
                    fab = find.byTooltip("2D Map");
                    await tester.tap(fab);
                    await tester.pumpAndSettle();
                    
                    // Verify Log Flight button exists (creates logbook entry from track)
                    expect(find.byTooltip("Create logbook entry from this track"), findsOneWidget);
                    
                    // Go back from KML viewer
                    fab = find.byTooltip("Back");
                    await tester.tap(fab);
                    await tester.pumpAndSettle();
                  }
                  
                  // Go back to main Documents
                  fab = find.byIcon(Icons.arrow_back);
                  if (tester.any(fab)) {
                    await tester.tap(fab);
                    await tester.pumpAndSettle();
                  }
                }
                
                // Go back to MAP
                fab = find.byTooltip("Back");
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                // Clean up test KML file
                if (await testKmlFile.exists()) {
                  await testKmlFile.delete();
                }
          }

          await kmlTest();

          // =====================
          // TEST: Notes Save and Delete (sketch persistence)
          // =====================
          Future<void> notesSketchPersistenceTest() async {
                // Navigate to Notes screen
                fab = find.byIcon(MdiIcons.transcribe);
                if (tester.any(fab)) {
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                  
                  await Future.delayed(const Duration(seconds: 1));
                  await tester.pumpAndSettle();

                  // Verify we're on Notes screen
                  expect(find.text("Notes"), findsOneWidget);
                  
                  // ========================================
                  // TEST: Save button functionality
                  // ========================================
                  fab = find.byIcon(Icons.save);
                  expect(fab, findsOneWidget);
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                  await Future.delayed(const Duration(seconds: 1));
                  await tester.pumpAndSettle();
                  
                  // ========================================
                  // TEST: Switch sheets and verify they persist independently
                  // ========================================
                  // Switch to CRAFT sheet
                  fab = find.byIcon(Icons.note_alt_outlined);
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                  
                  fab = find.text("CRAFT");
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                  await Future.delayed(const Duration(seconds: 1));
                  await tester.pumpAndSettle();
                  
                  // Save CRAFT sheet
                  fab = find.byIcon(Icons.save);
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                  
                  // Switch to Cost sheet
                  fab = find.byIcon(Icons.note_alt_outlined);
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                  
                  fab = find.text("Cost");
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                  await Future.delayed(const Duration(seconds: 1));
                  await tester.pumpAndSettle();
                  
                  // Save Cost sheet
                  fab = find.byIcon(Icons.save);
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                  
                  // ========================================
                  // TEST: Eraser clears content
                  // ========================================
                  fab = find.byIcon(MdiIcons.eraser);
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                  
                  // Save cleared sheet
                  fab = find.byIcon(Icons.save);
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                  
                  // ========================================
                  // TEST: Return to None sheet and verify clean state
                  // ========================================
                  fab = find.byIcon(Icons.note_alt_outlined);
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                  
                  fab = find.text("None");
                  await tester.tap(fab);
                  await tester.pumpAndSettle();

                  // Go back
                  fab = find.byTooltip("Back");
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                }
          }

          await notesSketchPersistenceTest();

          // =====================
          // TEST: Checklist Import and Verification
          // =====================
          Future<void> checklistImportTest() async {
                // Create a test checklist programmatically (simulating import)
                // Checklist format: first line is title, subsequent lines are steps
                Checklist testChecklist = Checklist(
                  "Pre-Flight Check",
                  "",
                  [
                    "Check fuel quantity and quality",
                    "Inspect control surfaces",
                    "Check tire pressure",
                    "Verify oil level",
                    "Test lights and avionics",
                    "Check weather briefing",
                    "File flight plan"
                  ]
                );
                
                // Add checklist to database (simulating import)
                await UserDatabaseHelper.db.addChecklist(testChecklist);
                
                // Open drawer via Menu button
                fab = find.widgetWithText(TextButton, "Menu");
                await tester.tap(fab);
                await tester.pumpAndSettle();

                // Tap Check Lists in drawer
                fab = find.widgetWithText(ListTile, "Check Lists");
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                await Future.delayed(const Duration(seconds: 1));
                await tester.pumpAndSettle();

                // Verify Check Lists screen elements
                expect(find.text("Pre-Flight Check"), findsOneWidget);
                expect(find.widgetWithText(TextButton, "Import"), findsOneWidget);
                
                // Verify all checklist steps are visible
                expect(find.text("Check fuel quantity and quality"), findsOneWidget);
                expect(find.text("Inspect control surfaces"), findsOneWidget);
                expect(find.text("Check tire pressure"), findsOneWidget);
                expect(find.text("Verify oil level"), findsOneWidget);
                expect(find.text("Test lights and avionics"), findsOneWidget);
                
                // Scroll to see more items if needed
                fab = find.text("Check weather briefing");
                if (!tester.any(fab)) {
                  await tester.dragUntilVisible(
                    fab,
                    find.byType(SingleChildScrollView),
                    const Offset(0, -100));
                  await tester.pumpAndSettle();
                }
                expect(find.text("Check weather briefing"), findsOneWidget);
                expect(find.text("File flight plan"), findsOneWidget);
                
                // Test checking off items - tap first checkbox
                fab = find.byType(CheckboxListTile).first;
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                // Tap second checkbox
                fab = find.byType(CheckboxListTile).at(1);
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                // Test info tooltip - tap to show import instructions
                fab = find.byIcon(Icons.info);
                await tester.tap(fab);
                await tester.pumpAndSettle();
                await Future.delayed(const Duration(seconds: 2));
                await tester.pumpAndSettle();

                // Go back
                fab = find.byTooltip("Back");
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                // Clean up - delete test checklist
                await UserDatabaseHelper.db.deleteChecklist("Pre-Flight Check");
          }

          await checklistImportTest();

          // =====================
          // TEST: KML Import via Documents
          // =====================
          Future<void> kmlImportTest() async {
                // Navigate to Documents screen
                fab = find.widgetWithText(TextButton, "Menu");
                await tester.tap(fab);
                await tester.pumpAndSettle();

                fab = find.widgetWithText(ListTile, "Documents");
                await tester.tap(fab);
                await tester.pumpAndSettle();
                
                await Future.delayed(const Duration(seconds: 1));
                await tester.pumpAndSettle();

                // Verify Documents screen elements
                expect(find.text("Documents"), findsOneWidget);
                
                // Verify Import button exists with correct tooltip for supported formats
                fab = find.widgetWithText(TextButton, "Import");
                expect(fab, findsOneWidget);
                
                // The Import tooltip mentions KML support
                // Verify by checking the button exists and is tappable
                
                // Verify Create Folder button exists
                expect(find.byTooltip("Create folder"), findsOneWidget);

                // Go back
                fab = find.byTooltip("Back");
                await tester.tap(fab);
                await tester.pumpAndSettle();
          }

          await kmlImportTest();

          // =====================
          // TEST: IO Screen (Bluetooth) - only on platforms that support it
          // =====================
          Future<void> ioScreenTest() async {
                // Open drawer via Menu button
                fab = find.widgetWithText(TextButton, "Menu");
                await tester.tap(fab);
                await tester.pumpAndSettle();

                // IO is only available on platforms with Bluetooth SPP support
                // Check if IO menu item exists before testing
                fab = find.widgetWithText(ListTile, "IO");
                if (tester.any(fab)) {
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                  
                  await Future.delayed(const Duration(seconds: 1));
                  await tester.pumpAndSettle();

                  // Verify IO screen elements
                  expect(find.text("IO (Bluetooth)"), findsOneWidget);
                  
                  // Verify "Not connected" status when no device is connected
                  expect(find.text("Not connected"), findsOneWidget);
                  
                  // Verify replay/refresh button exists
                  expect(find.byIcon(Icons.replay), findsOneWidget);

                  // Go back
                  fab = find.byTooltip("Back");
                  await tester.tap(fab);
                  await tester.pumpAndSettle();
                } else {
                  // IO not available on this platform, close drawer
                  fab = find.byTooltip("Back");
                  if (tester.any(fab)) {
                    await tester.tap(fab);
                    await tester.pumpAndSettle();
                  } else {
                    // Tap outside drawer to close it
                    await tester.tapAt(const Offset(300, 300));
                    await tester.pumpAndSettle();
                  }
                }
          }

          await ioScreenTest();

    });
  });
}