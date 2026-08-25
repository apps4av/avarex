import 'package:flutter_test/flutter_test.dart';

import 'package:avaremp/aip/aip_aero.dart';

void main() {
  group('AipAero.urlForAirport', () {
    test('builds vfr deep links for supported countries', () {
      expect(AipAero.urlForAirport('EDDF'), 'https://aip.aero/de/vfr/?EDDF');
      expect(AipAero.urlForAirport('LOWW'), 'https://aip.aero/at/vfr/?LOWW');
      expect(AipAero.urlForAirport('ESSA'), 'https://aip.aero/se/vfr/?ESSA');
      expect(AipAero.urlForAirport('LSGG'), 'https://aip.aero/ch/vfr/?LSGG');
      expect(AipAero.urlForAirport('EGLL'), 'https://aip.aero/uk/vfr/?EGLL');
      expect(AipAero.urlForAirport('EIDW'), 'https://aip.aero/ie/vfr/?EIDW');
      expect(AipAero.urlForAirport('EPWA'), 'https://aip.aero/pl/vfr/?EPWA');
      expect(AipAero.urlForAirport('UKBB'), 'https://aip.aero/ua/vfr/?UKBB');
      expect(AipAero.urlForAirport('YSSY'), 'https://aip.aero/au/vfr/?YSSY');
      expect(AipAero.urlForAirport('NZAA'), 'https://aip.aero/nz/vfr/?NZAA');
    });

    test('Spanish Canary Islands (GC) resolve to Spain', () {
      expect(AipAero.urlForAirport('GCTS'), 'https://aip.aero/es/vfr/?GCTS');
    });

    test('German military (ET) resolves to Germany', () {
      expect(AipAero.urlForAirport('ETAR'), 'https://aip.aero/de/vfr/?ETAR');
    });

    test('countries without a guessable slug fall back to the landing page', () {
      // France and Belgium/Luxembourg do not expose the vfr airport slug.
      expect(AipAero.urlForAirport('LFPG'), 'https://aip.aero/fr/');
      expect(AipAero.urlForAirport('EBBR'), 'https://aip.aero/be/');
      expect(AipAero.urlForAirport('ELLX'), 'https://aip.aero/be/'); // Luxembourg
    });

    test('disambiguates the shared UT* central-Asia block', () {
      expect(AipAero.urlForAirport('UTAA'), 'https://aip.aero/tm/vfr/?UTAA'); // Turkmenistan
      expect(AipAero.urlForAirport('UTDD'), 'https://aip.aero/tj/vfr/?UTDD'); // Tajikistan
      expect(AipAero.urlForAirport('UTTT'), 'https://aip.aero/uz/vfr/?UTTT'); // Uzbekistan
    });

    test('normalizes case and surrounding whitespace', () {
      expect(AipAero.urlForAirport('  eddf '), 'https://aip.aero/de/vfr/?EDDF');
    });

    test('falls back to the homepage for unknown or invalid identifiers', () {
      expect(AipAero.urlForAirport('KJFK'), 'https://aip.aero/'); // US, not covered
      expect(AipAero.urlForAirport(''), 'https://aip.aero/');
      expect(AipAero.urlForAirport('X'), 'https://aip.aero/');
    });
  });

  group('AipAero.hasChartsFor', () {
    test('true for covered European/Oceania identifiers', () {
      expect(AipAero.hasChartsFor('EDDF'), isTrue);
      expect(AipAero.hasChartsFor('LFPG'), isTrue); // covered via landing page
      expect(AipAero.hasChartsFor('YSSY'), isTrue);
    });

    test('false for uncovered identifiers', () {
      expect(AipAero.hasChartsFor('KJFK'), isFalse); // United States
      expect(AipAero.hasChartsFor(''), isFalse);
    });
  });
}
