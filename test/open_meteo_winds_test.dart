import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:avaremp/weather/open_meteo_winds.dart';

// Builds a minimal Open-Meteo hourly payload with a single forecast hour,
// providing geopotential height (m), wind speed (kn) and direction (deg) per
// pressure level.
String buildBody({
  required String time,
  required Map<int, ({double ghM, double spdKn, double dirDeg})> levels,
}) {
  final hourly = <String, dynamic>{'time': [time]};
  levels.forEach((hpa, v) {
    hourly['geopotential_height_${hpa}hPa'] = [v.ghM];
    hourly['wind_speed_${hpa}hPa'] = [v.spdKn];
    hourly['wind_direction_${hpa}hPa'] = [v.dirDeg];
  });
  return jsonEncode({'hourly': hourly});
}

void main() {
  group('OpenMeteoWinds.encodeWind (FB token)', () {
    test('encodes direction (tens of deg) and speed', () {
      expect(OpenMeteoWinds.encodeWind(240, 35), '2435');
      expect(OpenMeteoWinds.encodeWind(90, 12), '0912');
    });

    test('light and variable / calm below 5 kt', () {
      expect(OpenMeteoWinds.encodeWind(120, 3), '9900');
      expect(OpenMeteoWinds.encodeWind(0, 0), '9900');
    });

    test('high-speed encoding adds 50 to direction and subtracts 100 kt', () {
      // 270 deg at 120 kt -> dir tens 27 + 50 = 77, speed 20 -> "7720"
      expect(OpenMeteoWinds.encodeWind(270, 120), '7720');
    });

    test('missing inputs yield empty token', () {
      expect(OpenMeteoWinds.encodeWind(null, 20), '');
      expect(OpenMeteoWinds.encodeWind(180, null), '');
    });
  });

  group('OpenMeteoWinds.parse', () {
    // A simple monotonic profile: higher altitude -> stronger, veering wind.
    final body = buildBody(
      time: '2026-08-24T06:00',
      levels: {
        1000: (ghM: 110, spdKn: 8, dirDeg: 200), // ~360 ft
        850: (ghM: 1500, spdKn: 20, dirDeg: 230), // ~4921 ft
        700: (ghM: 3000, spdKn: 30, dirDeg: 250), // ~9843 ft
        500: (ghM: 5600, spdKn: 55, dirDeg: 270), // ~18,373 ft
        300: (ghM: 9000, spdKn: 80, dirDeg: 280), // ~29,528 ft
        250: (ghM: 10400, spdKn: 90, dirDeg: 285), // ~34,121 ft
        200: (ghM: 11800, spdKn: 100, dirDeg: 290), // ~38,714 ft
      },
    );

    test('produces a WindsAloft with the requested station and valid time', () {
      final wa = OpenMeteoWinds.parse('EDDF', body,
          now: DateTime.utc(2026, 8, 24, 0), foreHours: 6);
      expect(wa, isNotNull);
      expect(wa!.station, 'EDDF');
      // Valid time is the selected forecast hour.
      expect(wa.expires.toUtc(), DateTime.utc(2026, 8, 24, 6));
    });

    test('interpolates a mid-level slot between samples', () {
      final wa = OpenMeteoWinds.parse('EDDF', body,
          now: DateTime.utc(2026, 8, 24, 0), foreHours: 6)!;
      // 6000 ft sits between 850 hPa (~4921 ft, 230 deg / 20 kt) and 700 hPa
      // (~9843 ft, 250 deg / 30 kt). The decoded FB token is direction in tens
      // of degrees + speed in kt; interpolated speed must be between 20 and 30.
      // (getWindAtAltitude decodes via Storage, unavailable in unit tests, so we
      //  assert the encoded slot token which is the product of interpolation.)
      final token = wa.w6k;
      expect(token.length, 4);
      final dirTens = int.parse(token.substring(0, 2));
      final spd = int.parse(token.substring(2, 4));
      expect(dirTens, inInclusiveRange(23, 25)); // 230..250 deg
      expect(spd, greaterThan(20));
      expect(spd, lessThan(30));
    });

    test('surface slot uses the lowest level', () {
      final wa = OpenMeteoWinds.parse('EDDF', body,
          now: DateTime.utc(2026, 8, 24, 0), foreHours: 6)!;
      // 0 ft maps to the 1000 hPa sample (200 deg / 8 kt).
      expect(wa.w0k, OpenMeteoWinds.encodeWind(200, 8));
    });

    test('selects the forecast hour nearest now + foreHours', () {
      final multi = jsonEncode({
        'hourly': {
          'time': ['2026-08-24T00:00', '2026-08-24T06:00', '2026-08-24T12:00'],
          'geopotential_height_850hPa': [1500, 1510, 1520],
          'wind_speed_850hPa': [10, 20, 30],
          'wind_direction_850hPa': [200, 230, 260],
        }
      });
      final wa = OpenMeteoWinds.parse('X', multi,
          now: DateTime.utc(2026, 8, 24, 0), foreHours: 6)!;
      // Should pick the 06:00 sample (20 kt / 230 deg) for the 850 hPa-derived
      // altitude (~4921 ft), so the 6000 ft neighbourhood reflects that hour.
      expect(wa.expires.toUtc(), DateTime.utc(2026, 8, 24, 6));
    });

    test('returns null on malformed JSON', () {
      expect(OpenMeteoWinds.parse('X', 'not json'), isNull);
    });

    test('returns null when no usable levels present', () {
      final empty = jsonEncode({'hourly': {'time': ['2026-08-24T06:00']}});
      expect(OpenMeteoWinds.parse('X', empty,
          now: DateTime.utc(2026, 8, 24, 0), foreHours: 6), isNull);
    });
  });

  group('OpenMeteoWinds.buildUrl', () {
    test('uses the free host and knots unit without a key', () {
      final uri = OpenMeteoWinds.buildUrl(50.03, 8.55);
      expect(uri.host, OpenMeteoWinds.freeHost);
      expect(uri.queryParameters['wind_speed_unit'], 'kn');
      expect(uri.queryParameters.containsKey('apikey'), isFalse);
      expect(uri.queryParameters['hourly'], contains('wind_speed_850hPa'));
      expect(uri.queryParameters['hourly'], contains('geopotential_height_500hPa'));
    });

    test('uses the customer host when an API key is supplied', () {
      final uri = OpenMeteoWinds.buildUrl(50.03, 8.55, apiKey: 'secret');
      expect(uri.host, OpenMeteoWinds.customerHost);
      expect(uri.queryParameters['apikey'], 'secret');
    });
  });

  group('OpenMeteoWinds.distanceKm', () {
    test('is unit-independent kilometres', () {
      // Frankfurt to Paris is ~480 km.
      final d = OpenMeteoWinds.distanceKm(
          const LatLng(50.03, 8.55), const LatLng(48.85, 2.35));
      expect(d, greaterThan(430));
      expect(d, lessThan(530));
    });
  });
}
