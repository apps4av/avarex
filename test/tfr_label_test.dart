// TFR map-label formatting: altitude limits from the FAA XML triple
// (value / unit / reference code, sampled from live detail_*.xml files) and
// the "active in" countdown for TFRs that have not started yet.
import 'package:avaremp/weather/tfr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('formatAltitude', () {
    test('zero floor is SFC regardless of code', () {
      expect(Tfr.formatAltitude('0', 'FT', 'HEI'), 'SFC');
      expect(Tfr.formatAltitude('0', 'FT', 'ALT'), 'SFC');
    });

    test('HEI is AGL, ALT is bare MSL', () {
      expect(Tfr.formatAltitude('4999', 'FT', 'HEI'), '4999 AGL');
      expect(Tfr.formatAltitude('17999', 'FT', 'ALT'), '17999');
      expect(Tfr.formatAltitude('9000', 'FT', 'ALT'), '9000');
    });

    test('flight levels and the 9999 no-ceiling placeholder', () {
      expect(Tfr.formatAltitude('180', 'FL', 'ALT'), 'FL180');
      expect(Tfr.formatAltitude('9999', 'FL', 'ALT'), 'UNL');
    });

    test('non-numeric passes through', () {
      expect(Tfr.formatAltitude('Check NOTAMs', '', ''), 'Check NOTAMs');
    });
  });

  group('formatActiveIn', () {
    const int hour = Duration.millisecondsPerHour;
    const int minute = Duration.millisecondsPerMinute;

    test('already effective is empty', () {
      expect(Tfr.formatActiveIn(0), '');
      expect(Tfr.formatActiveIn(-hour), '');
    });

    test('under an hour is minutes, rounded up', () {
      expect(Tfr.formatActiveIn(45 * minute), 'in 45 min');
      expect(Tfr.formatActiveIn(30 * 1000), 'in 1 min');
    });

    test('under ten hours has one decimal', () {
      expect(Tfr.formatActiveIn((3.5 * hour).round()), 'in 3.5 hrs');
    });

    test('up to four days is whole hours', () {
      expect(Tfr.formatActiveIn(27 * hour), 'in 27 hrs');
    });

    test('beyond four days is days', () {
      expect(Tfr.formatActiveIn(5 * 24 * hour), 'in 5 days');
    });
  });

  test('Tfr labels use the stored altitudes and effective time', () {
    final DateTime now = DateTime.utc(2026, 9, 19, 12);
    final Tfr tfr = Tfr(
      'test', now, now, 'Internet',
      [const LatLng(32.7, -117.2)],
      '4999 AGL', 'SFC',
      now.add(const Duration(hours: 2, minutes: 30)).millisecondsSinceEpoch,
      now.add(const Duration(hours: 5)).millisecondsSinceEpoch,
      0,
    );
    expect(tfr.altitudeLabel(), '4999 AGL/SFC');
    expect(tfr.activeInLabel(now), 'in 2.5 hrs');
    expect(tfr.activeInLabel(now.add(const Duration(hours: 3))), '');
  });
}
