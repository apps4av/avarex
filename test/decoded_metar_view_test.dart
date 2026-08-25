import 'package:avaremp/weather/metar.dart';
import 'package:avaremp/weather/decoded_metar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

// Widget-level smoke test for the decoded METAR card: verifies it renders the
// decoded elements and the VFR/IFR selector without needing the emulator UI.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Metar makeMetar(String raw) => Metar(
        'EGLL',
        DateTime.now().toUtc().add(const Duration(hours: 1)),
        DateTime.now().toUtc(),
        'Internet',
        raw,
        Metar.getCategory(raw),
        const LatLng(51.47, -0.45),
      );

  testWidgets('DecodedMetarView shows decoded elements and profile toggle',
      (tester) async {
    final metar = makeMetar(
        'METAR EGLL 240920Z 10018G28KT 3000 BR OVC008 12/11 Q1004');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: DecodedMetarView(metar: metar)),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Decoded METAR'), findsOneWidget);
    // Profile selector present.
    expect(find.text('VFR'), findsWidgets);
    expect(find.text('IFR'), findsWidgets);
    // Some decoded rows present.
    expect(find.text('Wind'), findsOneWidget);
    expect(find.text('Ceiling'), findsOneWidget);
    expect(find.textContaining('gusting 28 kt'), findsOneWidget);

    // Tapping VFR should not throw and should keep the card rendered.
    await tester.tap(find.text('VFR').first);
    await tester.pumpAndSettle();
    expect(find.text('Decoded METAR'), findsOneWidget);
  });
}
