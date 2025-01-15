import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:avaremp/main.dart';
import 'package:integration_test/integration_test.dart';
import 'package:introduction_screen/introduction_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('end-to-end test', () {
    testWidgets('Verify',
            (tester) async {
          // Load app widget.

          await Storage().init();
          Storage().settings.setSign(false);
          Storage().settings.setIntro(true);
          await tester.pumpWidget(const MainApp());

          final fab = find.widgetWithText(TextButton, "Tap here to sign");
          await tester.dragUntilVisible(fab, find.byType(IntroductionScreen), const Offset(0, -250));

          await tester.tap(fab);

          // Trigger a frame.
          await tester.pumpAndSettle();

          // Verify the counter increments by 1.
          expect(find.text("You have signed this document. Please continue on to the next screen."), findsOneWidget);

        });
  });
}