import 'dart:convert';

import 'package:avaremp/weather/weather_cams.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _site(int id, String name, String ident, String icao,
    double lat, double lon,
    {bool active = true, List<int> cameras = const [1, 2]}) {
  return {
    'siteId': id,
    'siteName': name,
    'siteIdentifier': ident,
    'icao': icao,
    'state': 'AK',
    'latitude': lat,
    'longitude': lon,
    'siteActive': active,
    'siteInMaintenance': false,
    'cameras': [
      for (final int c in cameras)
        {
          'cameraId': id * 100 + c,
          'cameraName': 'Camera $c',
          'cameraDirection': c == 1 ? 'East' : 'South',
          'cameraBearing': c == 1 ? 70 : 185,
          'cameraInMaintenance': false,
          'cameraOutOfOrder': false,
          'displayOrder': 10 - c, // camera 2 sorts first
        }
    ],
  };
}

String _sitesBody(List<Map<String, dynamic>> sites) =>
    jsonEncode({'success': true, 'count': sites.length, 'payload': sites});

void main() {
  group('WeatherCams parsing', () {
    test('parses sites and sorts cameras by display order', () {
      final sites = WeatherCams.parseSites(
          _sitesBody([_site(195, 'Wainwright', 'AWI', 'PAWI', 70.63, -160.03)]));
      expect(sites.length, 1);
      expect(sites[0].name, 'Wainwright');
      expect(sites[0].cameras.map((c) => c.cameraId).toList(), [19502, 19501]);
      expect(sites[0].cameras[1].label, 'East (Camera 1)');
    });

    test('skips malformed sites but keeps the rest', () {
      final body = jsonEncode({
        'success': true,
        'payload': [
          {'siteId': 'bad'},
          _site(1, 'Good', 'GD', 'KGD', 40, -100),
        ]
      });
      expect(WeatherCams.parseSites(body).map((s) => s.name).toList(), ['Good']);
    });

    test('drops inactive sites and sites without cameras', () {
      final sites = WeatherCams.parseSites(_sitesBody([
        _site(1, 'Good', 'GD', 'KGD', 40, -100),
        _site(2, 'Inactive', 'OFF', 'KOFF', 40, -100, active: false),
        _site(3, 'No cameras', 'NOC', 'KNOC', 40, -100, cameras: []),
      ]));
      expect(sites.map((s) => s.name).toList(), ['Good']);
      expect(sites[0].coordinate.latitude, 40);
      expect(sites[0].coordinate.longitude, -100);
    });

    test('throws on an unsuccessful response', () {
      expect(() => WeatherCams.parseSites(jsonEncode({'success': false, 'payload': null})),
          throwsFormatException);
    });

    test('keeps the newest image of each camera', () {
      final body = jsonEncode({
        'success': true,
        'payload': [
          {'cameraId': 1, 'imageUri': 'https://x/old.jpg', 'imageDatetime': '2026-10-31T19:00:00.000Z'},
          {'cameraId': 1, 'imageUri': 'https://x/new.jpg', 'imageDatetime': '2026-10-31T19:30:00.000Z'},
          {'cameraId': 2, 'imageUri': 'https://x/two.jpg', 'imageDatetime': '2026-10-31T18:00:00.000Z'},
          {'cameraId': 1, 'imageUri': 'https://x/mid.jpg', 'imageDatetime': '2026-10-31T19:10:00.000Z'},
        ]
      });
      final latest = WeatherCams.parseLatestImages(body);
      expect(latest.length, 2);
      expect(latest[1]!.url, 'https://x/new.jpg');
      expect(latest[2]!.url, 'https://x/two.jpg');
    });
  });
}
